import { createFileRoute, redirect } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { useServerFn } from "@tanstack/react-start";
import { useAuth } from "@/lib/auth";
import { supabase } from "@/integrations/supabase/client";
import {
  listUsers,
  createUser,
  updateUser,
  setUserActive,
  resetUserPassword,
  deleteUser,
} from "@/lib/admin.functions";
import { toast } from "sonner";
import { Plus, Power, Key, Trash2, Pencil } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

export const Route = createFileRoute("/_app/usuarios")({
  beforeLoad: async () => {
    const { data } = await supabase.auth.getSession();
    if (!data.session) throw redirect({ to: "/login" });
  },
  component: UsuariosPage,
});

type Row = { id: string; username: string | null; nome: string; email: string; ativo: boolean; role: string | null };
type AppRole = "admin" | "gestor" | "rh" | "apontamento" | "supervisor";
type UserForm = { username: string; nome: string; password: string; role: AppRole };

const roleOptions: Array<{ value: AppRole; label: string }> = [
  { value: "admin", label: "Admin" },
  { value: "gestor", label: "Gestor" },
  { value: "rh", label: "RH" },
  { value: "apontamento", label: "Apontamento" },
  { value: "supervisor", label: "Supervisor" },
];

const emptyForm: UserForm = { username: "", nome: "", password: "", role: "apontamento" };

function roleLabel(role: string | null) {
  return roleOptions.find((r) => r.value === role)?.label ?? role ?? "—";
}

function UsuariosPage() {
  const { isGestor, user } = useAuth();
  const list = useServerFn(listUsers);
  const create = useServerFn(createUser);
  const update = useServerFn(updateUser);
  const setActive = useServerFn(setUserActive);
  const resetPwd = useServerFn(resetUserPassword);
  const removeUser = useServerFn(deleteUser);

  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);
  const [createForm, setCreateForm] = useState<UserForm>({ ...emptyForm });

  const [editOpen, setEditOpen] = useState(false);
  const [editRow, setEditRow] = useState<Row | null>(null);
  const [editForm, setEditForm] = useState<UserForm>({ ...emptyForm });
  const [savingEdit, setSavingEdit] = useState(false);

  async function reload() {
    setLoading(true);
    try {
      const data = await list();
      setRows(data as Row[]);
    } catch (e: any) {
      toast.error(e.message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    if (isGestor) reload();
  }, [isGestor]);

  if (!isGestor) {
    return (
      <div className="space-y-4 max-w-lg">
        <p className="text-sm text-muted-foreground">Acesso restrito ao Gestor.</p>
        <p className="text-sm text-muted-foreground">
          Se você alterou seu próprio perfil por engano, execute o arquivo{" "}
          <code className="text-xs bg-sand px-1 py-0.5 rounded">supabase/restore_gestor.sql</code>{" "}
          no SQL Editor do Supabase e faça login novamente.
        </p>
      </div>
    );
  }

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault();
    setCreating(true);
    try {
      await create({
        data: {
          username: createForm.username.trim(),
          nome: createForm.nome.trim(),
          password: createForm.password,
          role: createForm.role,
        },
      });
      toast.success(`Usuário "${createForm.username}" criado`);
      setCreateForm({ ...emptyForm });
      reload();
    } catch (e: any) {
      toast.error(e.message);
    } finally {
      setCreating(false);
    }
  }

  function openEdit(r: Row) {
    setEditRow(r);
    setEditForm({
      username: r.username ?? "",
      nome: r.nome,
      password: "",
      role: (r.role as AppRole) ?? "apontamento",
    });
    setEditOpen(true);
  }

  async function handleEditSave(e: React.FormEvent) {
    e.preventDefault();
    if (!editRow) return;
    setSavingEdit(true);
    try {
      await update({
        data: {
          userId: editRow.id,
          username: editForm.username.trim(),
          nome: editForm.nome.trim(),
          role: editForm.role,
          password: editForm.password.trim() || undefined,
        },
      });
      toast.success("Usuário atualizado");
      setEditOpen(false);
      setEditRow(null);
      reload();
    } catch (e: any) {
      toast.error(e.message);
    } finally {
      setSavingEdit(false);
    }
  }

  async function toggleActive(r: Row) {
    try {
      await setActive({ data: { userId: r.id, ativo: !r.ativo } });
      toast.success(r.ativo ? "Desativado" : "Ativado");
      reload();
    } catch (e: any) {
      toast.error(e.message);
    }
  }

  async function handleReset(r: Row) {
    const pwd = window.prompt(`Nova senha para ${r.username ?? r.nome} (mín. 6 caracteres):`);
    if (!pwd) return;
    if (pwd.length < 6) {
      toast.error("A senha deve ter pelo menos 6 caracteres");
      return;
    }
    try {
      await resetPwd({ data: { userId: r.id, password: pwd } });
      toast.success("Senha redefinida");
    } catch (e: any) {
      toast.error(e.message);
    }
  }

  async function handleDelete(r: Row) {
    if (r.id === user?.id) {
      toast.error("Você não pode excluir seu próprio usuário");
      return;
    }
    const confirm = window.confirm(
      `Excluir permanentemente o usuário "${r.username ?? r.id}"?\n\nEssa ação remove login, perfil e permissões.`,
    );
    if (!confirm) return;
    try {
      await removeUser({ data: { userId: r.id } });
      toast.success("Usuário excluído");
      reload();
    } catch (e: any) {
      toast.error(e.message);
    }
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-light tracking-tight">Usuários</h1>
        <p className="text-muted-foreground mt-1">
          Cada pessoa tem login, nome e senha próprios. Use o botão Editar para alterar depois de criar.
        </p>
      </div>

      <form
        onSubmit={handleCreate}
        autoComplete="off"
        className="bg-card border border-oak-light rounded-3xl p-6 space-y-4"
      >
        <h2 className="text-sm font-medium text-oak-dark">Novo usuário</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <Field label="Usuário (login)">
            <input
              required
              autoComplete="off"
              value={createForm.username}
              onChange={(e) => setCreateForm({ ...createForm, username: e.target.value })}
              className={inp}
              placeholder="ex: maria.silva"
            />
          </Field>
          <Field label="Nome completo">
            <input
              required
              autoComplete="off"
              value={createForm.nome}
              onChange={(e) => setCreateForm({ ...createForm, nome: e.target.value })}
              className={inp}
              placeholder="Maria Silva"
            />
          </Field>
          <Field label="Senha inicial">
            <input
              required
              type="text"
              autoComplete="new-password"
              minLength={6}
              value={createForm.password}
              onChange={(e) => setCreateForm({ ...createForm, password: e.target.value })}
              className={inp}
              placeholder="mín. 6 caracteres"
            />
          </Field>
          <Field label="Permissão">
            <select
              value={createForm.role}
              onChange={(e) => setCreateForm({ ...createForm, role: e.target.value as AppRole })}
              className={inp}
            >
              {roleOptions.map((role) => (
                <option key={role.value} value={role.value}>
                  {role.label}
                </option>
              ))}
            </select>
          </Field>
        </div>
        <button
          disabled={creating}
          type="submit"
          className="inline-flex items-center justify-center gap-2 px-5 py-2.5 bg-oak-dark text-primary-foreground rounded-xl text-sm font-medium hover:opacity-90 disabled:opacity-50 w-full sm:w-auto"
        >
          <Plus className="size-4" /> {creating ? "Criando..." : "Criar usuário"}
        </button>
      </form>

      <div className="bg-card border border-oak-light rounded-3xl overflow-hidden">
        {loading ? (
          <div className="p-12 text-center text-sm text-muted-foreground">Carregando...</div>
        ) : rows.length === 0 ? (
          <div className="p-12 text-center text-sm text-muted-foreground">Nenhum usuário cadastrado.</div>
        ) : (
          <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead>
              <tr className="bg-sand/30">
                <Th>Usuário</Th>
                <Th>Nome</Th>
                <Th>Permissão</Th>
                <Th>Status</Th>
                <Th>Ações</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-oak-light">
              {rows.map((r) => (
                <tr key={r.id} className={r.id === user?.id ? "bg-oak-light/10" : undefined}>
                  <td className="px-6 py-4 text-sm font-medium">
                    {r.username ?? "—"}
                    {r.id === user?.id && (
                      <span className="ml-2 text-[10px] uppercase text-oak-dark/50">(você)</span>
                    )}
                  </td>
                  <td className="px-6 py-4 text-sm">{r.nome}</td>
                  <td className="px-6 py-4 text-sm">
                    <span className="px-2 py-1 bg-sand rounded-lg text-xs">{roleLabel(r.role)}</span>
                  </td>
                  <td className="px-6 py-4 text-xs">
                    <span
                      className={`px-2 py-1 rounded-full ${r.ativo ? "bg-green-100 text-green-800" : "bg-red-100 text-red-800"}`}
                    >
                      {r.ativo ? "Ativo" : "Desativado"}
                    </span>
                  </td>
                  <td className="px-6 py-4 text-sm flex flex-wrap gap-2">
                    <button
                      type="button"
                      onClick={() => openEdit(r)}
                      className="inline-flex items-center gap-1 px-3 py-1.5 bg-sand rounded-lg text-xs hover:bg-oak-medium"
                    >
                      <Pencil className="size-3" />
                      Editar
                    </button>
                    <button
                      type="button"
                      onClick={() => toggleActive(r)}
                      className="inline-flex items-center gap-1 px-3 py-1.5 bg-sand rounded-lg text-xs hover:bg-oak-medium"
                    >
                      <Power className="size-3" />
                      {r.ativo ? "Desativar" : "Ativar"}
                    </button>
                    <button
                      type="button"
                      onClick={() => handleReset(r)}
                      className="inline-flex items-center gap-1 px-3 py-1.5 bg-sand rounded-lg text-xs hover:bg-oak-medium"
                    >
                      <Key className="size-3" />
                      Senha
                    </button>
                    <button
                      type="button"
                      onClick={() => handleDelete(r)}
                      disabled={r.id === user?.id}
                      className="inline-flex items-center gap-1 px-3 py-1.5 bg-red-100 text-red-800 rounded-lg text-xs hover:bg-red-200 disabled:opacity-40"
                    >
                      <Trash2 className="size-3" />
                      Excluir
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          </div>
        )}
      </div>

      <Dialog open={editOpen} onOpenChange={setEditOpen}>
        <DialogContent className="sm:max-w-md">
          <form onSubmit={handleEditSave} autoComplete="off">
            <DialogHeader>
              <DialogTitle>Editar usuário</DialogTitle>
              <DialogDescription>
                Altere login, nome, permissão e senha. Deixe a senha em branco para não mudar.
              </DialogDescription>
            </DialogHeader>
            <div className="grid gap-4 py-4">
              <Field label="Usuário (login)">
                <input
                  required
                  autoComplete="off"
                  value={editForm.username}
                  onChange={(e) => setEditForm({ ...editForm, username: e.target.value })}
                  className={inp}
                />
              </Field>
              <Field label="Nome completo">
                <input
                  required
                  autoComplete="off"
                  value={editForm.nome}
                  onChange={(e) => setEditForm({ ...editForm, nome: e.target.value })}
                  className={inp}
                />
              </Field>
              <Field label="Nova senha (opcional)">
                <input
                  type="text"
                  autoComplete="new-password"
                  minLength={6}
                  value={editForm.password}
                  onChange={(e) => setEditForm({ ...editForm, password: e.target.value })}
                  className={inp}
                  placeholder="Deixe vazio para manter a atual"
                />
              </Field>
              <Field label="Permissão">
                <select
                  value={editForm.role}
                  onChange={(e) => setEditForm({ ...editForm, role: e.target.value as AppRole })}
                  className={inp}
                >
                  {roleOptions.map((role) => (
                    <option key={role.value} value={role.value}>
                      {role.label}
                    </option>
                  ))}
                </select>
              </Field>
            </div>
            <DialogFooter>
              <button
                type="button"
                onClick={() => setEditOpen(false)}
                className="px-4 py-2 text-sm rounded-xl bg-sand hover:bg-oak-medium"
              >
                Cancelar
              </button>
              <button
                type="submit"
                disabled={savingEdit}
                className="px-4 py-2 text-sm rounded-xl bg-oak-dark text-primary-foreground hover:opacity-90 disabled:opacity-50"
              >
                {savingEdit ? "Salvando..." : "Salvar alterações"}
              </button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}

const inp =
  "w-full px-4 py-2.5 bg-sand rounded-xl text-sm border-none focus:outline-none focus:ring-2 focus:ring-oak-dark/20";
function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <label className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">{label}</label>
      <div className="mt-2">{children}</div>
    </div>
  );
}
function Th({ children }: { children: React.ReactNode }) {
  return (
    <th className="px-6 py-4 text-[10px] font-bold text-oak-dark/50 uppercase tracking-widest">{children}</th>
  );
}
