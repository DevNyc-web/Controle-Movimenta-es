import { createFileRoute, redirect } from "@tanstack/react-router";
import React, { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/auth";
import { format } from "date-fns";
import { Download } from "lucide-react";

export const Route = createFileRoute("/_app/auditoria")({
  beforeLoad: async () => {
    const { data } = await supabase.auth.getSession();
    if (!data.session) throw redirect({ to: "/login" });
  },
  component: AuditoriaPage,
});

type Log = {
  id: string;
  user_id: string | null;
  username: string | null;
  role: string | null;
  action: string;
  entity_type: string;
  entity_id: string | null;
  description: string | null;
  old_data: any;
  new_data: any;
  observacao: string | null;
  created_at: string;
};

const actionLabel: Record<string, string> = {
  INSERT: "Criou",
  UPDATE: "Alterou",
  DELETE: "Excluiu",
  CRIAR_USUARIO: "Criou usuário",
  ATIVAR_USUARIO: "Ativou usuário",
  DESATIVAR_USUARIO: "Desativou usuário",
  ALTERAR_PERMISSAO: "Alterou perfil de acesso",
  RESET_SENHA: "Redefiniu senha",
  EXCLUIR_USUARIO: "Excluiu usuário",
  ATUALIZAR_USUARIO: "Atualizou usuário",
};

const entityLabel: Record<string, string> = {
  ft: "Movimentação",
  funcionarios: "Funcionários",
  profiles: "Usuários",
  user_roles: "Perfis de acesso",
};

function getModule(log: Log) {
  const fromData = (log.new_data as any)?.modulo ?? (log.old_data as any)?.modulo;
  if (typeof fromData === "string" && fromData.trim()) return fromData;
  return entityLabel[log.entity_type] ?? log.entity_type;
}

function getAction(log: Log) {
  return actionLabel[log.action] ?? log.action;
}

function getObjectDescription(log: Log) {
  const oldData = (log.old_data as any) ?? {};
  const newData = (log.new_data as any) ?? {};
  const username = newData.username ?? oldData.username;
  const nome = newData.nome ?? oldData.nome;
  const role = newData.role ?? (Array.isArray(newData.roles) ? newData.roles.join(", ") : undefined);
  const parts = [username, nome, role].filter(Boolean);
  return parts.length ? parts.join(" | ") : (log.entity_id ?? "—");
}

function AuditoriaPage() {
  const { isGestor } = useAuth();
  const [logs, setLogs] = useState<Log[]>([]);
  const [loading, setLoading] = useState(true);
  const [fUser, setFUser] = useState("");
  const [fRole, setFRole] = useState("");
  const [fAction, setFAction] = useState("");
  const [fEntity, setFEntity] = useState("");
  const [fStart, setFStart] = useState("");
  const [fEnd, setFEnd] = useState("");
  const [expanded, setExpanded] = useState<string | null>(null);

  useEffect(() => { if (isGestor) load(); }, [isGestor]);

  async function load() {
    setLoading(true);
    const { data, error } = await supabase
      .from("audit_logs")
      .select("*")
      .order("created_at", { ascending: false })
      .limit(2000);
    if (error) console.error(error);
    setLogs((data ?? []) as Log[]);
    setLoading(false);
  }

  const filtered = useMemo(() => {
    return logs.filter((l) => {
      if (fUser && !(l.username ?? "").toLowerCase().includes(fUser.toLowerCase())) return false;
      if (fRole && l.role !== fRole) return false;
      if (fAction) {
        const actionText = `${l.action} ${getAction(l)}`.toLowerCase();
        if (!actionText.includes(fAction.toLowerCase())) return false;
      }
      if (fEntity && l.entity_type !== fEntity) return false;
      if (fStart && l.created_at < fStart) return false;
      if (fEnd && l.created_at > fEnd + "T23:59:59") return false;
      return true;
    });
  }, [logs, fUser, fRole, fAction, fEntity, fStart, fEnd]);

  if (!isGestor) return <div className="text-sm text-muted-foreground">Acesso restrito ao Gestor.</div>;

  function exportCsv() {
    const headers = ["Data", "Usuário", "Permissão", "Ação", "Módulo", "Registro", "Descrição"];
    const lines = [headers.join(";")];
    filtered.forEach((l) => {
      lines.push([
        format(new Date(l.created_at), "dd/MM/yyyy HH:mm:ss"),
        l.username ?? "",
        l.role ?? "",
        getAction(l),
        getModule(l),
        l.entity_id ?? "",
        (l.description ?? "").replace(/[;\n]/g, " "),
      ].join(";"));
    });
    const blob = new Blob(["\ufeff" + lines.join("\n")], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `auditoria_${format(new Date(), "yyyyMMdd_HHmm")}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-light tracking-tight">Auditoria</h1>
        <p className="text-muted-foreground mt-1">Registro imutável com usuário, ação, módulo e detalhes do que foi alterado.</p>
      </div>

      <div className="bg-card border border-oak-light rounded-3xl p-6 grid grid-cols-1 sm:grid-cols-2 md:grid-cols-7 gap-3 items-end">
        <Field label="Usuário"><input value={fUser} onChange={(e) => setFUser(e.target.value)} className={inp} placeholder="username" /></Field>
        <Field label="Permissão">
          <select value={fRole} onChange={(e) => setFRole(e.target.value)} className={inp}>
            <option value="">Todas</option>
            <option value="gestor">Gestor</option>
            <option value="apontamento">Apontamento</option>
            <option value="supervisor">Supervisor</option>
          </select>
        </Field>
        <Field label="Ação"><input value={fAction} onChange={(e) => setFAction(e.target.value)} className={inp} placeholder="Criou, alterou, excluiu..." /></Field>
        <Field label="Tipo">
          <select value={fEntity} onChange={(e) => setFEntity(e.target.value)} className={inp}>
            <option value="">Todos</option>
            <option value="ft">Movimentação</option>
            <option value="funcionarios">Funcionário</option>
            <option value="profiles">Usuário</option>
            <option value="user_roles">Permissão</option>
          </select>
        </Field>
        <Field label="De"><input type="date" value={fStart} onChange={(e) => setFStart(e.target.value)} className={inp} /></Field>
        <Field label="Até"><input type="date" value={fEnd} onChange={(e) => setFEnd(e.target.value)} className={inp} /></Field>
        <button onClick={exportCsv} disabled={!filtered.length} className="w-full sm:w-auto inline-flex items-center justify-center gap-2 px-4 py-2.5 bg-oak-dark text-primary-foreground rounded-xl text-sm font-medium hover:opacity-90 disabled:opacity-50">
          <Download className="size-4" /> CSV
        </button>
      </div>

      <div className="bg-card border border-oak-light rounded-3xl overflow-hidden">
        {loading ? (
          <div className="p-12 text-center text-sm text-muted-foreground">Carregando...</div>
        ) : filtered.length === 0 ? (
          <div className="p-12 text-center text-sm text-muted-foreground">Nenhum registro.</div>
        ) : (
          <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead>
              <tr className="bg-sand/30">
                <Th>Data/Hora</Th><Th>Usuário</Th><Th>Ação</Th><Th>Módulo</Th><Th>O que mudou</Th><Th>Descrição</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-oak-light">
              {filtered.map((l) => (
                <React.Fragment key={l.id}>
                  <tr className="hover:bg-sand/20 cursor-pointer" onClick={() => setExpanded(expanded === l.id ? null : l.id)}>
                    <td className="px-6 py-3 text-xs tabular-nums">{format(new Date(l.created_at), "dd/MM/yy HH:mm:ss")}</td>
                    <td className="px-6 py-3 text-sm font-medium">{l.username ?? "—"}</td>
                    <td className="px-6 py-3 text-xs"><span className="px-2 py-0.5 bg-sand rounded">{getAction(l)}</span></td>
                    <td className="px-6 py-3 text-xs">{getModule(l)}</td>
                    <td className="px-6 py-3 text-xs">{getObjectDescription(l)}</td>
                    <td className="px-6 py-3 text-sm">{l.description ?? "—"}</td>
                  </tr>
                  {expanded === l.id && (l.old_data || l.new_data) && (
                    <tr><td colSpan={6} className="px-6 py-4 bg-sand/10">
                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-xs">
                        <div><div className="font-bold mb-1">Antes</div><pre className="bg-card p-3 rounded overflow-auto max-h-60">{JSON.stringify(l.old_data, null, 2)}</pre></div>
                        <div><div className="font-bold mb-1">Depois</div><pre className="bg-card p-3 rounded overflow-auto max-h-60">{JSON.stringify(l.new_data, null, 2)}</pre></div>
                      </div>
                    </td></tr>
                  )}
                </React.Fragment>
              ))}
            </tbody>
          </table>
          </div>
        )}
      </div>
    </div>
  );
}

const inp = "w-full px-3 py-2 bg-sand rounded-xl text-sm border-none focus:outline-none focus:ring-2 focus:ring-oak-dark/20";
function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <div><label className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">{label}</label><div className="mt-1">{children}</div></div>;
}
function Th({ children }: { children: React.ReactNode }) { return <th className="px-6 py-3 text-[10px] font-bold text-oak-dark/50 uppercase tracking-widest">{children}</th>; }
