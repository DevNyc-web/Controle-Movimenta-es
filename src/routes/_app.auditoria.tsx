import { createFileRoute } from "@tanstack/react-router";
import React, { useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/auth";
import { format } from "date-fns";
import { Download } from "lucide-react";
import { toast } from "sonner";
import {
  FILTROS_VAZIOS, LIMITE_CSV, LOTE_CSV, TAMANHO_PAGINA, coletarTodas, contemTexto, juntarPaginas, paramsPagina, periodoInvalido, proximoCursor,
  type Cursor, type FiltrosAuditoria,
} from "@/lib/auditoria";

// Sem beforeLoad: no SSR não há sessão (fica no navegador) e ele redirecionava F5/URL para /login → Dashboard.
// A sessão é exigida pelo AppGuard de _app.tsx; o acesso, pelo isGestor da página e pelas funções auditoria_pagina/auditoria_filtros (recusam quem não é Gestor).
export const Route = createFileRoute("/_app/auditoria")({
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
  FT_RETROATIVA_EXCECAO: "Lançou FT retroativa por exceção",
  ANULAR_INATIVIDADE: "Anulou período de inatividade",
  CONFERENCIA_CRIADA: "Iniciou importação oficial",
  CONFERENCIA_QUADRO_COMPLETO: "Confirmou quadro completo",
  CONFERENCIA_EXPIRADA: "Importação expirada",
  CPF_ALTERADO: "Corrigiu CPF",
  CPF_INFORMADO: "Informou CPF",
  CONFERENCIA_DECISAO: "Revisou item da importação",
  CONFERENCIA_ITEM_APLICADO: "Aplicou item da importação",
  CONFERENCIA_APLICADA: "Aplicou importação oficial",
  CONFERENCIA_DESCARTADA: "Descartou importação oficial",
};

const entityLabel: Record<string, string> = {
  ft: "Movimentação",
  funcionarios: "Funcionários",
  profiles: "Usuários",
  user_roles: "Perfis de acesso",
  funcionario_inatividades: "Períodos de inatividade",
  conferencias: "Importação oficial",
  conferencia_itens: "Itens de importação",
  importacao_empresas: "Primeira importação por empresa",
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

type Opcoes = { usuarios: { id: string; username: string | null }[]; acoes: string[]; perfis: string[]; modulos: string[] };
const OPCOES_VAZIAS: Opcoes = { usuarios: [], acoes: [], perfis: [], modulos: [] };
const perfilLabel: Record<string, string> = { gestor: "Gestor", apontamento: "Apontamento", supervisor: "Supervisor", admin: "Admin", rh: "RH" };

const buscarPagina = async (f: FiltrosAuditoria, cursor: Cursor, tamanho: number) => {
  // Sem leitura direta de audit_logs: a função do Gestor devolve uma página com CPF mascarado (os registros gravados não mudam).
  const { data, error } = await supabase.rpc("auditoria_pagina", paramsPagina(f, cursor, tamanho));
  if (error) throw error;
  return (data ?? []) as Log[];
};

const textoDoRegistro = (l: Log) => [l.username, getAction(l), getModule(l), getObjectDescription(l), l.description, l.entity_id];

function AuditoriaPage() {
  const { isGestor } = useAuth();
  const [filtros, setFiltros] = useState<FiltrosAuditoria>(FILTROS_VAZIOS);
  const [opcoes, setOpcoes] = useState<Opcoes>(OPCOES_VAZIAS);
  const [logs, setLogs] = useState<Log[]>([]);
  const [cursor, setCursor] = useState<Cursor>(null);
  const [loading, setLoading] = useState(true);
  const [carregandoMais, setCarregandoMais] = useState(false);
  const [erro, setErro] = useState("");
  const [pesquisa, setPesquisa] = useState("");
  const [exportando, setExportando] = useState<number | null>(null);
  const [expanded, setExpanded] = useState<string | null>(null);
  // Só a resposta da consulta mais recente é usada (filtros trocados rapidamente não misturam resultados).
  const consulta = useRef(0);

  const invalido = periodoInvalido(filtros);

  useEffect(() => {
    if (!isGestor) return;
    supabase.rpc("auditoria_filtros").then(({ data, error }) => {
      if (error) return;
      const o = (data ?? {}) as Partial<Opcoes>;
      setOpcoes({ usuarios: o.usuarios ?? [], acoes: o.acoes ?? [], perfis: o.perfis ?? [], modulos: o.modulos ?? [] });
    });
  }, [isGestor]);

  // Filtro mudou → recomeça do início (cursor zerado).
  useEffect(() => {
    if (!isGestor || invalido) return;
    const n = ++consulta.current;
    setLoading(true); setErro(""); setLogs([]); setCursor(null); setExpanded(null);
    buscarPagina(filtros, null, TAMANHO_PAGINA)
      .then((p) => { if (n !== consulta.current) return; setLogs(p); setCursor(proximoCursor(p, TAMANHO_PAGINA)); })
      .catch(() => { if (n === consulta.current) setErro("Não foi possível carregar a auditoria."); })
      .finally(() => { if (n === consulta.current) setLoading(false); });
  }, [isGestor, filtros, invalido]);

  async function carregarMais() {
    if (!cursor) return;
    const n = consulta.current;
    setCarregandoMais(true);
    try {
      const p = await buscarPagina(filtros, cursor, TAMANHO_PAGINA);
      if (n !== consulta.current) return;
      setLogs((atual) => juntarPaginas(atual, p));
      setCursor(proximoCursor(p, TAMANHO_PAGINA));
    } catch {
      if (n === consulta.current) toast.error("Não foi possível carregar mais registros.");
    } finally {
      setCarregandoMais(false);
    }
  }

  const visiveis = useMemo(() => logs.filter((l) => contemTexto(textoDoRegistro(l), pesquisa)), [logs, pesquisa]);

  if (!isGestor) return <div className="text-sm text-muted-foreground">Acesso restrito ao Gestor.</div>;

  const mudar = (campo: keyof FiltrosAuditoria) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
    setFiltros((f) => ({ ...f, [campo]: e.target.value }));

  async function exportCsv() {
    setExportando(0);
    try {
      const r = await coletarTodas((c) => buscarPagina(filtros, c, LOTE_CSV), { progresso: setExportando });
      if (r.excedeu) {
        toast.error(`Este filtro tem mais de ${LIMITE_CSV.toLocaleString("pt-BR")} registros. Nenhum arquivo foi gerado: restrinja o período ou os filtros e exporte de novo.`, { duration: 10000 });
        return;
      }
      const linhas = r.linhas.filter((l) => contemTexto(textoDoRegistro(l), pesquisa));
      const headers = ["Data", "Usuário", "Permissão", "Ação", "Módulo", "Registro", "Descrição"];
      const out = [headers.join(";")];
      linhas.forEach((l) => {
        out.push([
          format(new Date(l.created_at), "dd/MM/yyyy HH:mm:ss"),
          l.username ?? "",
          l.role ?? "",
          getAction(l),
          getModule(l),
          l.entity_id ?? "",
          (l.description ?? "").replace(/[;\n]/g, " "),
        ].join(";"));
      });
      const blob = new Blob(["﻿" + out.join("\n")], { type: "text/csv;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `auditoria_${format(new Date(), "yyyyMMdd_HHmm")}.csv`;
      a.click();
      URL.revokeObjectURL(url);
      toast.success(`CSV com ${linhas.length.toLocaleString("pt-BR")} registro(s) de ${r.linhas.length.toLocaleString("pt-BR")} do filtro${pesquisa.trim() ? " (pesquisa aplicada)" : ""}.`);
    } catch {
      toast.error("Não foi possível exportar. Nenhum arquivo foi gerado.");
    } finally {
      setExportando(null);
    }
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-light tracking-tight">Auditoria</h1>
        <p className="text-muted-foreground mt-1">Registro imutável com usuário, ação, módulo e detalhes do que foi alterado.</p>
      </div>

      <div className="bg-card border border-oak-light rounded-3xl p-6 space-y-4">
        <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-6 gap-3 items-end">
          <Field label="Usuário">
            <select value={filtros.userId} onChange={mudar("userId")} className={inp} aria-label="Usuário">
              <option value="">Todos</option>
              {opcoes.usuarios.map((u) => <option key={u.id} value={u.id}>{u.username ?? u.id}</option>)}
            </select>
          </Field>
          <Field label="Permissão">
            <select value={filtros.role} onChange={mudar("role")} className={inp} aria-label="Permissão">
              <option value="">Todas</option>
              {opcoes.perfis.map((p) => <option key={p} value={p}>{perfilLabel[p] ?? p}</option>)}
            </select>
          </Field>
          <Field label="Ação">
            <select value={filtros.action} onChange={mudar("action")} className={inp} aria-label="Ação">
              <option value="">Todas</option>
              {opcoes.acoes.map((a) => <option key={a} value={a}>{actionLabel[a] ?? a}</option>)}
            </select>
          </Field>
          <Field label="Tipo">
            <select value={filtros.entityType} onChange={mudar("entityType")} className={inp} aria-label="Tipo">
              <option value="">Todos</option>
              {opcoes.modulos.map((m) => <option key={m} value={m}>{entityLabel[m] ?? m}</option>)}
            </select>
          </Field>
          <Field label="De"><input type="date" value={filtros.de} onChange={mudar("de")} className={inp} aria-label="De" /></Field>
          <Field label="Até"><input type="date" value={filtros.ate} onChange={mudar("ate")} className={inp} aria-label="Até" /></Field>
        </div>
        {invalido && <p className="text-sm text-destructive">A data inicial é posterior à final.</p>}
        <div className="grid grid-cols-1 md:grid-cols-[1fr_auto] gap-3 items-end">
          <Field label="Pesquisar nos registros carregados">
            <input value={pesquisa} onChange={(e) => setPesquisa(e.target.value)} className={inp} placeholder="Texto em usuário, ação, módulo ou descrição" aria-label="Pesquisar nos registros carregados" />
          </Field>
          <button onClick={exportCsv} disabled={exportando !== null || invalido || loading} className="w-full md:w-auto inline-flex items-center justify-center gap-2 px-4 py-2.5 bg-oak-dark text-primary-foreground rounded-xl text-sm font-medium hover:opacity-90 disabled:opacity-50">
            <Download className="size-4" /> {exportando === null ? "CSV" : `Exportando ${exportando.toLocaleString("pt-BR")}...`}
          </button>
        </div>
        <p className="text-xs text-muted-foreground">
          Usuário, permissão, ação, tipo e período consultam todo o histórico no servidor. A pesquisa de texto vale só para os{" "}
          {logs.length.toLocaleString("pt-BR")} registro(s) já carregados, com CPF mascarado; para encontrar registros antigos, use os filtros
          ou “Carregar mais”. O CSV traz todos os registros dos filtros (e da pesquisa, se houver), até {LIMITE_CSV.toLocaleString("pt-BR")}.
        </p>
      </div>

      <div className="bg-card border border-oak-light rounded-3xl overflow-hidden">
        {loading ? (
          <div className="p-12 text-center text-sm text-muted-foreground">Carregando...</div>
        ) : erro ? (
          <div className="p-12 text-center text-sm text-destructive">{erro}</div>
        ) : visiveis.length === 0 ? (
          <div className="p-12 text-center text-sm text-muted-foreground">
            {logs.length && pesquisa.trim() ? "Nenhum registro carregado contém esse texto." : "Nenhum registro."}
          </div>
        ) : (
          <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead>
              <tr className="bg-sand/30">
                <Th>Data/Hora</Th><Th>Usuário</Th><Th>Ação</Th><Th>Módulo</Th><Th>O que mudou</Th><Th>Descrição</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-oak-light">
              {visiveis.map((l) => (
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
        {!loading && !erro && (
          <div className="flex flex-col sm:flex-row items-center justify-between gap-3 px-6 py-4 border-t border-oak-light text-sm">
            <span className="text-muted-foreground">
              {logs.length.toLocaleString("pt-BR")} registro(s) carregado(s){pesquisa.trim() ? `; ${visiveis.length.toLocaleString("pt-BR")} com o texto pesquisado` : ""}
            </span>
            {cursor ? (
              <button onClick={carregarMais} disabled={carregandoMais} className="px-4 py-2 bg-sand rounded-xl font-medium hover:opacity-90 disabled:opacity-50">
                {carregandoMais ? "Carregando..." : `Carregar mais ${TAMANHO_PAGINA}`}
              </button>
            ) : (
              <span className="text-muted-foreground">Fim do histórico para estes filtros.</span>
            )}
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
