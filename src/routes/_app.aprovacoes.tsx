import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/auth";
import { StatusBadge } from "@/components/StatusBadge";
import { toast } from "sonner";
import { Check, X } from "lucide-react";
import { format } from "date-fns";
import { carregarPendentes, lerFiltroAprovacoes, salvarFiltroAprovacoes } from "@/lib/aprovacoes";

export const Route = createFileRoute("/_app/aprovacoes")({
  component: Aprovacoes,
});

function Aprovacoes() {
  const { user, isGestor } = useAuth();
  const [items, setItems] = useState<any[]>([]);
  const [solicitacoes, setSolicitacoes] = useState<any[]>([]);
  const [obsMap, setObsMap] = useState<Record<string, string>>({});
  // Filtro por data_ft (data do serviço). Vazio = lista completa. Vale só para as FTs pendentes.
  const [inicio, setInicio] = useState("");
  const [fim, setFim] = useState("");
  const navigate = useNavigate();
  const seq = useRef(0); // descarta respostas antigas se o período mudar antes de a consulta anterior terminar
  const uid = user?.id;
  const [filtroDe, setFiltroDe] = useState<string | null>(null); // usuário cujo filtro salvo já foi restaurado

  // Restaura o filtro salvo antes da primeira consulta (evita uma busca sem filtro no meio).
  useEffect(() => {
    if (!uid) return;
    const f = lerFiltroAprovacoes(uid);
    setInicio(f.inicio);
    setFim(f.fim);
    setFiltroDe(uid);
  }, [uid]);

  useEffect(() => {
    if (!uid || filtroDe !== uid) return;
    salvarFiltroAprovacoes(uid, inicio, fim);
    load();
  }, [uid, filtroDe, inicio, fim]);

  async function load() {
    const minha = ++seq.current;
    try {
      const fts = await carregarPendentes(supabase, inicio, fim);
      if (minha === seq.current) setItems(fts);
    } catch (e: any) {
      toast.error(e.message ?? "Erro ao carregar movimentações");
    }

    const { data: sols } = await supabase
      .from("ft_cancelamento_solicitacoes")
      .select(
        "*, ft:ft(numero_ft, data_ft, lancado_por, funcionario:funcionarios!ft_funcionario_id_fkey(nome, re, empresa))",
      )
      .eq("status", "PENDENTE")
      .order("created_at");

    if (sols && sols.length > 0) {
      // Solicitante (quem pediu) e lançador (quem criou a FT) podem ser supervisores diferentes.
      const ids = [
        ...new Set(
          sols
            .flatMap((s) => [s.solicitado_por, s.ft?.lancado_por])
            .filter((x): x is string => !!x),
        ),
      ];
      const { data: profs } = await supabase.from("profiles").select("id, nome").in("id", ids);
      const profileMap = Object.fromEntries((profs ?? []).map((p: any) => [p.id, p.nome]));
      setSolicitacoes(
        sols.map((s) => ({
          ...s,
          solicitante_nome: profileMap[s.solicitado_por] ?? "—",
          lancador_nome: (s.ft?.lancado_por && profileMap[s.ft.lancado_por]) ?? "—",
        })),
      );
    } else {
      setSolicitacoes([]);
    }
  }

  async function decide(id: string, status: "APROVADA" | "NEGADA") {
    const { error } = await supabase.from("ft").update({ status, aprovado_por: user?.id }).eq("id", id);
    if (error) toast.error(error.message);
    else {
      toast.success(`Movimentação ${status.toLowerCase()}`);
      load();
    }
  }

  async function decidirCancelamento(solicitacaoId: string, acao: "aprovar" | "rejeitar") {
    const obs = obsMap[solicitacaoId]?.trim() || undefined;
    const fn = acao === "aprovar" ? "aprovar_cancelamento" : "rejeitar_cancelamento";
    const { error } = await supabase.rpc(fn, { _solicitacao_id: solicitacaoId, _obs: obs });
    if (error) {
      toast.error(error.message);
    } else {
      toast.success(acao === "aprovar" ? "Cancelamento aprovado" : "Solicitação rejeitada — movimentação voltou para PENDENTE");
      setObsMap((prev) => { const next = { ...prev }; delete next[solicitacaoId]; return next; });
      load();
    }
  }

  return (
    <div className="space-y-10">
      {/* ── Aprovações de FT ──────────────────────────────── */}
      <div className="space-y-6">
        <div>
          <h1 className="text-3xl font-light tracking-tight">Aprovações Pendentes</h1>
          <p className="text-muted-foreground mt-1">{items.length} movimentação(ões) aguardando análise{inicio || fim ? " no período" : ""}.</p>
        </div>

        <div className="bg-card border border-oak-light rounded-3xl p-6 flex flex-col gap-5 sm:flex-row sm:flex-wrap sm:items-end">
          <div className="w-full sm:w-auto">
            <label htmlFor="ap-inicio" className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">Data da FT — de</label>
            <input id="ap-inicio" type="date" value={inicio} max={fim || undefined} onChange={(e) => setInicio(e.target.value)} className="mt-2 w-full px-4 py-2.5 bg-sand rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-oak-dark/20" />
          </div>
          <div className="w-full sm:w-auto">
            <label htmlFor="ap-fim" className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">até</label>
            <input id="ap-fim" type="date" value={fim} min={inicio || undefined} onChange={(e) => setFim(e.target.value)} className="mt-2 w-full px-4 py-2.5 bg-sand rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-oak-dark/20" />
          </div>
          <button onClick={() => { setInicio(""); setFim(""); }} disabled={!inicio && !fim} className="w-full sm:w-auto px-5 py-2.5 text-sm font-medium border border-oak-medium rounded-xl hover:bg-oak-medium/20 disabled:opacity-50">
            Limpar filtros
          </button>
          {inicio && fim && inicio > fim && <p className="w-full text-xs text-rose-700">A data inicial é maior que a final.</p>}
        </div>

        {!isGestor && (
          <div className="bg-amber-50 border border-amber-200 text-amber-800 rounded-2xl p-4 text-sm">
            Somente gestores podem aprovar ou negar movimentações. Você pode visualizar a fila.
          </div>
        )}

        {items.length === 0 ? (
          <div className="bg-card border border-oak-light rounded-3xl p-12 text-center text-sm text-muted-foreground">
            {inicio || fim ? "Nenhuma movimentação pendente no período selecionado." : "Nenhuma movimentação pendente. Tudo em dia! ✨"}
          </div>
        ) : (
          <div className="space-y-4">
            {items.map((f) => (
              <div key={f.id} className="bg-card border border-oak-light rounded-3xl p-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:gap-6 hover:shadow-md transition-shadow">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-3">
                    <p className="font-medium">{f.funcionario?.nome}</p>
                    <StatusBadge status={f.status} />
                  </div>
                  <p className="text-xs text-oak-dark/60 mt-1">
                    {f.funcionario?.cargo} • RE {f.funcionario?.re} • {f.funcionario?.empresa ?? "Empresa não informada"} • {format(new Date(f.data_ft + "T00:00:00"), "dd/MM/yyyy")} • {f.posto_falta ?? "—"} • {f.horas_trabalhadas}h • {f.escala_servico ?? f.tipo_folga ?? "—"}
                  </p>
                  {f.observacao && <p className="text-sm mt-2 text-oak-dark/80">{f.observacao}</p>}
                </div>
                <div className="flex flex-wrap gap-2 sm:shrink-0">
                  <button onClick={() => navigate({ to: "/ft/$id", params: { id: f.id } })} className="flex-1 sm:flex-none px-4 py-2 text-xs font-medium border border-oak-medium rounded-xl hover:bg-oak-medium/20">
                    Detalhes
                  </button>
                  {isGestor && (
                    <>
                      <button onClick={() => decide(f.id, "APROVADA")} className="flex-1 sm:flex-none inline-flex items-center justify-center gap-1 px-4 py-2 text-xs font-medium bg-emerald-600 text-white rounded-xl hover:bg-emerald-700">
                        <Check className="size-3" /> Aprovar
                      </button>
                      <button onClick={() => decide(f.id, "NEGADA")} className="flex-1 sm:flex-none inline-flex items-center justify-center gap-1 px-4 py-2 text-xs font-medium bg-rose-600 text-white rounded-xl hover:bg-rose-700">
                        <X className="size-3" /> Negar
                      </button>
                    </>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* ── Solicitações de Cancelamento ──────────────────── */}
      {isGestor && (
        <div className="space-y-6">
          <div>
            <h2 className="text-xl font-light tracking-tight">Solicitações de Cancelamento</h2>
            <p className="text-muted-foreground mt-1">{solicitacoes.length} solicitação(ões) aguardando decisão.</p>
          </div>

          {solicitacoes.length === 0 ? (
            <div className="bg-card border border-oak-light rounded-3xl p-12 text-center text-sm text-muted-foreground">
              Nenhuma solicitação de cancelamento pendente.
            </div>
          ) : (
            <div className="space-y-4">
              {solicitacoes.map((s) => (
                <div key={s.id} className="bg-card border border-orange-200 rounded-3xl p-6 space-y-4">
                  <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                    <div className="space-y-1">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="font-mono text-xs text-oak-dark/60">{s.ft?.numero_ft ?? "—"}</span>
                        <span className="font-medium">{s.ft?.funcionario?.nome ?? "—"}</span>
                        <span className="text-xs text-oak-dark/60">RE {s.ft?.funcionario?.re}{s.ft?.funcionario?.empresa && ` • ${s.ft.funcionario.empresa}`}</span>
                      </div>
                      <p className="text-xs text-oak-dark/60">
                        Data da FT: {s.ft?.data_ft ? format(new Date(s.ft.data_ft + "T00:00:00"), "dd/MM/yyyy") : "—"}
                        {" · "}Solicitado por: {s.solicitante_nome}
                        {" · "}Lançado por: {s.lancador_nome}
                        {" · "}Solicitado em: {format(new Date(s.created_at), "dd/MM/yyyy HH:mm")}
                      </p>
                      <p className="text-sm mt-2 text-oak-dark/90">
                        <span className="font-medium text-xs text-oak-dark/50 uppercase tracking-wider">Motivo: </span>
                        {s.motivo}
                      </p>
                    </div>
                    <button
                      onClick={() => navigate({ to: "/ft/$id", params: { id: s.ft_id } })}
                      className="shrink-0 px-3 py-1.5 text-xs font-medium border border-oak-medium rounded-xl hover:bg-oak-medium/20 w-full sm:w-auto"
                    >
                      Ver FT
                    </button>
                  </div>

                  <div className="flex flex-col gap-3 pt-2 border-t border-oak-light sm:flex-row sm:items-center">
                    <input
                      type="text"
                      placeholder="Observação (opcional)"
                      value={obsMap[s.id] ?? ""}
                      onChange={(e) => setObsMap((prev) => ({ ...prev, [s.id]: e.target.value }))}
                      className="flex-1 text-sm bg-transparent border border-oak-light rounded-xl px-3 py-2 focus:outline-none focus:border-oak-medium w-full"
                    />
                    <button
                      onClick={() => decidirCancelamento(s.id, "aprovar")}
                      className="inline-flex items-center justify-center gap-1 px-4 py-2 text-xs font-medium bg-emerald-600 text-white rounded-xl hover:bg-emerald-700 shrink-0 w-full sm:w-auto"
                    >
                      <Check className="size-3" /> Aprovar
                    </button>
                    <button
                      onClick={() => decidirCancelamento(s.id, "rejeitar")}
                      className="inline-flex items-center justify-center gap-1 px-4 py-2 text-xs font-medium bg-rose-600 text-white rounded-xl hover:bg-rose-700 shrink-0 w-full sm:w-auto"
                    >
                      <X className="size-3" /> Rejeitar
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
