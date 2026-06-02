import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { supabaseAdmin } from "@/integrations/supabase/client.server";
import { assertGestor, getActor, logAudit } from "./admin.server";

const RoleEnum = z.enum(["admin", "gestor", "rh", "apontamento", "supervisor"]);

async function countOtherGestores(excludeUserId: string) {
  const { data, error } = await supabaseAdmin.from("user_roles").select("user_id").eq("role", "gestor");
  if (error) throw new Error(error.message);
  return (data ?? []).filter((r) => r.user_id !== excludeUserId).length;
}

async function assertCanChangeRole(actorId: string, targetUserId: string, newRole: z.infer<typeof RoleEnum>) {
  if (targetUserId === actorId && newRole !== "gestor") {
    const outrosGestores = await countOtherGestores(actorId);
    if (outrosGestores === 0) {
      throw new Error(
        "Você é o único Gestor. Não é possível alterar seu próprio perfil pela interface. " +
          "Execute supabase/restore_gestor.sql no SQL Editor do Supabase para voltar a ser Gestor.",
      );
    }
  }
}

function toFriendlyError(error: unknown, fallback: string) {
  const msg = (error as any)?.message ?? fallback;
  if (typeof msg !== "string") return fallback;
  if (msg.includes("Missing Supabase server environment variables")) {
    return "Configuração ausente no servidor: defina SUPABASE_SERVICE_ROLE_KEY para habilitar cadastro/edição de acessos.";
  }
  if (msg.includes("SUPABASE_URL aponta para o projeto")) return msg;
  if (/invalid api key|invalid jwt|invalid.*key/i.test(msg)) {
    return (
      "Chave administrativa inválida para este SUPABASE_URL. " +
      "Copie a service_role do mesmo projeto em Settings → API (sem prefixo VITE_) e reinicie o servidor (npm run dev)."
    );
  }
  return msg;
}

export const listUsers = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    await assertGestor(context.supabase, context.userId);
    const { data: profiles } = await supabaseAdmin
      .from("profiles")
      .select("id, username, nome, email, ativo, created_at")
      .order("created_at", { ascending: false });
    const { data: roles } = await supabaseAdmin.from("user_roles").select("user_id, role");
    const roleMap = new Map<string, string>();
    (roles ?? []).forEach((r: any) => roleMap.set(r.user_id, r.role));
    return (profiles ?? []).map((p: any) => ({ ...p, role: roleMap.get(p.id) ?? null }));
  });

export const createUser = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input) =>
    z.object({
      username: z.string().min(2).max(40).regex(/^[a-zA-Z0-9_.-]+$/),
      password: z.string().min(6).max(72),
      nome: z.string().min(1).max(120),
      role: RoleEnum,
    }).parse(input)
  )
  .handler(async ({ context, data }) => {
    try {
      await assertGestor(context.supabase, context.userId);
      const username = data.username.trim().toLowerCase();
      const email = `${username}@interno.local`;

      const { data: created, error } = await supabaseAdmin.auth.admin.createUser({
        email,
        password: data.password,
        email_confirm: true,
        user_metadata: { username, nome: data.nome, role: data.role },
      });
      if (error) throw new Error(error.message);
      if (!created.user?.id) throw new Error("Falha ao criar usuário no Auth.");

      const uid = created.user.id;
      const { error: profileErr } = await supabaseAdmin
        .from("profiles")
        .upsert({ id: uid, nome: data.nome, email, username, ativo: true }, { onConflict: "id" });
      if (profileErr) throw new Error(profileErr.message);

      const { error: roleErr } = await supabaseAdmin
        .from("user_roles")
        .upsert({ user_id: uid, role: data.role }, { onConflict: "user_id,role" });
      if (roleErr) throw new Error(roleErr.message);

      const actor = await getActor(context.userId);
      await logAudit("CRIAR_USUARIO", "profiles", uid, `${actor.username ?? "?"} criou o usuário ${username} (${data.role})`, actor, {
        old_data: null,
        new_data: { modulo: "Usuários", username, nome: data.nome, role: data.role, ativo: true },
      });

      return { id: uid };
    } catch (error) {
      throw new Error(toFriendlyError(error, "Erro ao criar usuário."));
    }
  });

export const setUserActive = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input) => z.object({ userId: z.string().uuid(), ativo: z.boolean() }).parse(input))
  .handler(async ({ context, data }) => {
    await assertGestor(context.supabase, context.userId);
    const { data: before, error: beforeErr } = await supabaseAdmin
      .from("profiles")
      .select("id, username, nome, ativo")
      .eq("id", data.userId)
      .maybeSingle();
    if (beforeErr) throw new Error(beforeErr.message);
    const { error: updateErr } = await supabaseAdmin.from("profiles").update({ ativo: data.ativo }).eq("id", data.userId);
    if (updateErr) throw new Error(updateErr.message);
    const actor = await getActor(context.userId);
    await logAudit(
      data.ativo ? "ATIVAR_USUARIO" : "DESATIVAR_USUARIO",
      "profiles",
      data.userId,
      `${actor.username ?? "?"} ${data.ativo ? "ativou" : "desativou"} o usuário ${before?.username ?? data.userId}`,
      actor,
      {
        old_data: before ? { modulo: "Usuários", ...before } : null,
        new_data: { modulo: "Usuários", ...(before ?? {}), ativo: data.ativo },
      },
    );
    return { ok: true };
  });

export const updateUser = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input) =>
    z
      .object({
        userId: z.string().uuid(),
        username: z.string().min(2).max(40).regex(/^[a-zA-Z0-9_.-]+$/),
        nome: z.string().min(1).max(120),
        role: RoleEnum,
        password: z.union([z.string().min(6).max(72), z.literal("")]).optional(),
      })
      .parse(input),
  )
  .handler(async ({ context, data }) => {
    await assertGestor(context.supabase, context.userId);
    await assertCanChangeRole(context.userId, data.userId, data.role);

    const username = data.username.trim().toLowerCase();
    const email = `${username}@interno.local`;

    const { data: before, error: beforeErr } = await supabaseAdmin
      .from("profiles")
      .select("id, username, nome, email, ativo")
      .eq("id", data.userId)
      .maybeSingle();
    if (beforeErr) throw new Error(beforeErr.message);

    const authUpdate: { email: string; password?: string; user_metadata: Record<string, string> } = {
      email,
      user_metadata: { username, nome: data.nome, role: data.role },
    };
    if (data.password && data.password.length >= 6) {
      authUpdate.password = data.password;
    }

    const { error: authErr } = await supabaseAdmin.auth.admin.updateUserById(data.userId, authUpdate);
    if (authErr) throw new Error(authErr.message);

    const { error: profileErr } = await supabaseAdmin
      .from("profiles")
      .update({ nome: data.nome, username, email })
      .eq("id", data.userId);
    if (profileErr) throw new Error(profileErr.message);

    const { data: oldRoles, error: oldErr } = await supabaseAdmin.from("user_roles").select("role").eq("user_id", data.userId);
    if (oldErr) throw new Error(oldErr.message);
    const { error: delErr } = await supabaseAdmin.from("user_roles").delete().eq("user_id", data.userId);
    if (delErr) throw new Error(delErr.message);
    const { error: insErr } = await supabaseAdmin.from("user_roles").insert({ user_id: data.userId, role: data.role });
    if (insErr) throw new Error(insErr.message);

    const actor = await getActor(context.userId);
    await logAudit("ATUALIZAR_USUARIO", "profiles", data.userId, `${actor.username ?? "?"} atualizou o usuário ${username}`, actor, {
      old_data: { modulo: "Usuários", ...(before ?? {}), roles: (oldRoles ?? []).map((r: any) => r.role) },
      new_data: { modulo: "Usuários", username, nome: data.nome, role: data.role, senha_alterada: Boolean(data.password) },
    });

    return { ok: true };
  });

export const updateUserRole = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input) => z.object({ userId: z.string().uuid(), role: RoleEnum }).parse(input))
  .handler(async ({ context, data }) => {
    await assertGestor(context.supabase, context.userId);
    await assertCanChangeRole(context.userId, data.userId, data.role);
    const { data: oldRoles, error: oldErr } = await supabaseAdmin.from("user_roles").select("role").eq("user_id", data.userId);
    if (oldErr) throw new Error(oldErr.message);
    const { error: delErr } = await supabaseAdmin.from("user_roles").delete().eq("user_id", data.userId);
    if (delErr) throw new Error(delErr.message);
    const { error: insErr } = await supabaseAdmin.from("user_roles").insert({ user_id: data.userId, role: data.role });
    if (insErr) throw new Error(insErr.message);
    const actor = await getActor(context.userId);
    await logAudit("ALTERAR_PERMISSAO", "user_roles", data.userId,
      `${actor.username ?? "?"} alterou a permissão do usuário ${data.userId} para ${data.role}`, actor, {
        old_data: { modulo: "Usuários", roles: (oldRoles ?? []).map((r: any) => r.role) },
        new_data: { modulo: "Usuários", roles: [data.role] },
      });
    return { ok: true };
  });

export const resetUserPassword = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input) => z.object({ userId: z.string().uuid(), password: z.string().min(6).max(72) }).parse(input))
  .handler(async ({ context, data }) => {
    await assertGestor(context.supabase, context.userId);
    const { error } = await supabaseAdmin.auth.admin.updateUserById(data.userId, { password: data.password });
    if (error) throw new Error(error.message);
    const actor = await getActor(context.userId);
    await logAudit("RESET_SENHA", "profiles", data.userId, `${actor.username ?? "?"} redefiniu a senha do usuário ${data.userId}`, actor, {
      new_data: { modulo: "Usuários" },
    });
    return { ok: true };
  });

export const deleteUser = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input) => z.object({ userId: z.string().uuid() }).parse(input))
  .handler(async ({ context, data }) => {
    await assertGestor(context.supabase, context.userId);

    const { data: profile, error: profileErr } = await supabaseAdmin
      .from("profiles")
      .select("id, username, nome, email, ativo")
      .eq("id", data.userId)
      .maybeSingle();
    if (profileErr) throw new Error(profileErr.message);

    const { data: roles, error: roleErr } = await supabaseAdmin
      .from("user_roles")
      .select("role")
      .eq("user_id", data.userId);
    if (roleErr) throw new Error(roleErr.message);

    const { error } = await supabaseAdmin.auth.admin.deleteUser(data.userId, true);
    if (error) throw new Error(error.message);

    const actor = await getActor(context.userId);
    await logAudit("EXCLUIR_USUARIO", "profiles", data.userId, `${actor.username ?? "?"} excluiu o usuário ${profile?.username ?? data.userId}`, actor, {
      old_data: { modulo: "Usuários", ...(profile ?? {}), roles: (roles ?? []).map((r: any) => r.role) },
      new_data: null,
    });

    return { ok: true };
  });
