import { supabaseAdmin } from "@/integrations/supabase/client.server";

export async function assertGestor(supabase: any, userId: string) {
  // has_role é a mesma regra da RLS: perfil existente e conta ativa.
  const { data, error } = await supabase.rpc("has_role", { _user_id: userId, _role: "gestor" });
  if (error || data !== true) throw new Error("Apenas Gestor pode executar esta ação.");
}

export async function logAudit(
  action: string,
  entity: string,
  entityId: string,
  description: string,
  actor: { id: string; username?: string | null; role?: string | null },
  extra?: Record<string, any>,
) {
  await supabaseAdmin.from("audit_logs").insert({
    user_id: actor.id,
    username: actor.username ?? null,
    role: actor.role ?? null,
    action,
    entity_type: entity,
    entity_id: entityId,
    description,
    ...extra,
  });
}

export async function getActor(userId: string) {
  const { data: prof } = await supabaseAdmin.from("profiles").select("username").eq("id", userId).maybeSingle();
  const { data: r } = await supabaseAdmin.from("user_roles").select("role").eq("user_id", userId).maybeSingle();
  return { id: userId, username: prof?.username ?? null, role: (r as any)?.role ?? null };
}
