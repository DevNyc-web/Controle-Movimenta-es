import { createFileRoute, useParams, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/auth";
import { StatusBadge } from "@/components/StatusBadge";
import { toast } from "sonner";
import { ChevronLeft, Check, X, Ban, AlertTriangle, Save } from "lucide-react";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { useServerFn } from "@tanstack/react-start";
import { getLancadorFt } from "@/lib/ft.functions";
import { centavosDe, descreverCorrecao, formatarCentavos, montarCorrecao, parseValorCentavos, valorNoRelatorio } from "@/lib/ft-valor";

export const Route = createFileRoute("/_app/ft/$id")({
  component: FtDetalhe,
});

function FtDetalhe() {
  const { id } = useParams({ from: "/_app/ft/$id" });
  const { user, isGestor, isSupervisor } = useAuth();
  const navigate = useNavigate();
  const [ft, setFt] = useState<any>(null);
  const [historico, setHistorico] = useState<any[]>([]);
  // undefined = carregando; null = não identificado (sem lancado_por, sem perfil ou falha). Nunca o aprovador.
  const [lancador, setLancador] = useState<string | null | undefined>(undefined);
  const buscarLancador = useServerFn(getLancadorFt);

  const [showCancelModal, setShowCancelModal] = useState(false);
  const [motivo, setMotivo] = useState("");
  const [submitting, setSubmitting] = useState(false);

  // Correção financeira (gestor, FT pendente). valorTxt é o texto digitado; comparação sempre em centavos.
  const [valorTxt, setValorTxt] = useState("");
  const [folha, setFolha] = useState(false);
  const [salvando, setSalvando] = useState(false);
  const [conflito, setConflito] = useState(false);

  useEffect(() => { load(); }, [id]);
  useEffect(() => {
    let vivo = true;
    setLancador(undefined);
    buscarLancador({ data: { ftId: id } })
      .then((r) => { if (vivo) setLancador(r.nome); })
      .catch(() => { if (vivo) setLancador(null); });
    return () => { vivo = false; };
  }, [id]);
  async function load() {
    const { data } = await supabase.from("ft").select("*, funcionario:funcionarios!ft_funcionario_id_fkey(*), funcionario_faltante:funcionarios!ft_funcionario_faltante_id_fkey(nome, re, empresa)").eq("id", id).maybeSingle();
    setFt(data);
    if (data) {
      setValorTxt(formatarCentavos(centavosDe(data.valor_pago)));
      setFolha(!!data.pagamento_em_folha);
      setConflito(false);
    }
    const { data: h } = await supabase.from("ft_historico").select("*").eq("ft_id", id).order("created_at", { ascending: false });
    setHistorico(h ?? []);
  }

  async function changeStatus(status: "APROVADA" | "NEGADA" | "CANCELADA") {
    const payload: any = { status };
    if (status === "APROVADA" || status === "NEGADA") payload.aprovado_por = user?.id;
    if (status === "CANCELADA") payload.data_cancelamento = new Date().toISOString();
    const { error } = await supabase.from("ft").update(payload).eq("id", id);
    if (error) toast.error(error.message);
    else {
      toast.success(`Movimentação ${status.toLowerCase()}`);
      load();
    }
  }

  async function salvarCorrecao() {
    const centavos = parseValorCentavos(valorTxt);
    if (centavos === null) return;
    const patch = montarCorrecao(ft, centavos, folha);
    if (Object.keys(patch).length === 0) return;
    setSalvando(true);
    // Trava otimista no próprio UPDATE (um único comando SQL): só grava se a FT ainda está PENDENTE e ninguém a alterou
    // desde o carregamento (updated_at muda em todo UPDATE). 0 linhas = conflito; nada é sobrescrito.
    const { data, error } = await supabase.from("ft").update(patch).eq("id", id).eq("status", "PENDENTE").eq("updated_at", ft.updated_at).select("id").maybeSingle();
    if (error || !data) {
      setSalvando(false);
      if (error) toast.error(`Erro ao salvar: ${error.message}`);
      else {
        setConflito(true);
        toast.error("Esta movimentação foi alterada por outro usuário (ou não está mais pendente). Nada foi salvo.");
      }
      return;
    }
    // Fonte de auditoria garantida: audit_logs, gravado por trigger NA MESMA transação do UPDATE. O histórico da FT abaixo
    // é um segundo comando (melhor esforço, para exibição): sem RPC/migration não dá para torná-lo atômico.
    const { error: hErr } = await supabase.from("ft_historico").insert({ ft_id: id, acao: "VALORES_CORRIGIDOS", alterado_por: user!.id, observacao: descreverCorrecao(ft, patch) });
    setSalvando(false);
    if (hErr) toast.warning("Valores salvos, mas o histórico da FT não foi registrado (a auditoria geral registrou).");
    else toast.success("Valores salvos");
    load();
  }

  async function solicitarCancelamento() {
    if (!motivo.trim()) return;
    setSubmitting(true);
    const { error } = await supabase.from("ft_cancelamento_solicitacoes").insert({
      ft_id: id,
      solicitado_por: user!.id,
      motivo: motivo.trim(),
    });
    setSubmitting(false);
    if (error) {
      toast.error(error.message);
    } else {
      toast.success("Solicitação de cancelamento enviada");
      setShowCancelModal(false);
      setMotivo("");
      load();
    }
  }

  if (!ft) return <div className="text-sm text-muted-foreground">Carregando...</div>;

  const isPending = ft.status === "PENDENTE";
  const isCanceled = ft.status === "CANCELADA";
  const centavosDigitados = parseValorCentavos(valorTxt);
  const pendenteDeSalvar = centavosDigitados !== centavosDe(ft.valor_pago) || folha !== !!ft.pagamento_em_folha;

  return (
    <div className="space-y-8 max-w-4xl">
      <Link to="/ft" className="inline-flex items-center gap-1 text-xs text-oak-dark hover:underline">
        <ChevronLeft className="size-3" /> Voltar
      </Link>

      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">Movimentação {ft.numero_ft ?? `#${ft.id.slice(0, 8)}`}</p>
          <h1 className="text-3xl font-light tracking-tight mt-1">{ft.funcionario?.nome}</h1>
          <p className="text-muted-foreground mt-1">{[ft.funcionario?.cargo, ft.funcionario?.setor].filter(Boolean).join(" • ")}</p>
        </div>
        <StatusBadge status={ft.status} />
      </div>

      <div className="bg-card border border-oak-light rounded-3xl p-8 grid grid-cols-1 sm:grid-cols-2 gap-6">
        <Info label="Empresa" value={ft.funcionario?.empresa ?? "Não informada"} className="col-span-2" />
        <Info label="Data" value={format(new Date(ft.data_ft + "T00:00:00"), "dd 'de' MMMM, yyyy", { locale: ptBR })} />
        <Info label="Posto da falta" value={ft.posto_falta ?? "—"} className="col-span-2" />
        <Info label="Escala" value={ft.escala_servico ?? ft.tipo_folga ?? "—"} />
        <Info label="Horas trabalhadas" value={`${ft.horas_trabalhadas}h`} />
        <Info label="Horas compensadas" value={`${ft.horas_compensadas}h`} />
        {ft.motivo && <Info label="Motivo da cobertura" value={ft.motivo} />}
        {ft.funcionario_faltante && (
          <Info label="Funcionário faltante" value={`${ft.funcionario_faltante.nome} (RE ${ft.funcionario_faltante.re})${ft.funcionario_faltante.empresa ? ` — ${ft.funcionario_faltante.empresa}` : ""}`} className="col-span-2" />
        )}
        {ft.observacao && <Info label="Observação" value={ft.observacao} className="col-span-2" />}
        <Info label="Lançado por" value={lancador === undefined ? "Carregando..." : lancador ?? "Não identificado"} />
        <Info label="Data do lançamento" value={format(new Date(ft.created_at), "dd/MM/yyyy HH:mm")} />
        {ft.data_cancelamento && <Info label="Cancelada em" value={format(new Date(ft.data_cancelamento), "dd/MM/yyyy HH:mm")} />}
      </div>

      <div className="bg-card border border-oak-light rounded-3xl p-8 space-y-4">
        <div>
          <p className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">Valor no relatório</p>
          <p className="text-sm mt-1 tabular-nums">{valorNoRelatorio(ft)}{ft.pagamento_em_folha && <span className="text-oak-dark/60"> — não entra no total fora da folha</span>}</p>
        </div>
        {isPending && isGestor && (
          <div className="space-y-4">
            <div>
              <label htmlFor="ft-valor" className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">Valor (R$)</label>
              <input id="ft-valor" inputMode="decimal" value={valorTxt} onChange={(e) => setValorTxt(e.target.value)} aria-invalid={centavosDigitados === null} className="mt-2 block w-full sm:w-48 px-4 py-2.5 bg-sand rounded-xl text-sm tabular-nums focus:outline-none focus:ring-2 focus:ring-oak-dark/20 aria-[invalid=true]:ring-2 aria-[invalid=true]:ring-rose-400" />
              {centavosDigitados === null && <p className="text-xs text-rose-700 mt-1">Valor inválido. Use o formato 250,00 (até 2 casas, sem negativo, máx. R$ 99.999,99).</p>}
            </div>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={folha} onChange={(e) => setFolha(e.target.checked)} className="size-4 accent-[var(--oak-dark)]" />
              Pagamento em folha
            </label>
            {conflito && (
              <p className="text-xs text-rose-700">
                Esta movimentação foi alterada por outro usuário ou não está mais pendente. Nada foi salvo.{" "}
                <button onClick={load} className="underline font-medium">Recarregar dados atuais</button> (suas alterações serão descartadas).
              </p>
            )}
            <div className="flex flex-wrap items-center gap-3">
              <button onClick={salvarCorrecao} disabled={!pendenteDeSalvar || centavosDigitados === null || salvando || conflito} className="inline-flex items-center gap-2 px-5 py-2.5 text-sm font-medium bg-oak-dark text-white rounded-xl hover:opacity-90 disabled:opacity-50">
                <Save className="size-4" /> {salvando ? "Salvando..." : "Salvar valores"}
              </button>
              {pendenteDeSalvar && !salvando && (
                <>
                  <span className="text-xs text-amber-700">Alterações não salvas.</span>
                  <button onClick={load} className="text-xs underline text-oak-dark/70">Descartar</button>
                </>
              )}
            </div>
          </div>
        )}
      </div>

      {isPending && isGestor && pendenteDeSalvar && (
        <p className="text-xs text-amber-700">Salve ou descarte as alterações de valor antes de aprovar ou negar.</p>
      )}
      {isPending && isGestor && (
        <div className="flex flex-col gap-3 sm:flex-row">
          <button onClick={() => changeStatus("APROVADA")} disabled={pendenteDeSalvar} className="flex-1 inline-flex items-center justify-center gap-2 bg-emerald-600 text-white px-5 py-3 rounded-xl text-sm font-medium hover:bg-emerald-700 disabled:opacity-50">
            <Check className="size-4" /> Aprovar
          </button>
          <button onClick={() => changeStatus("NEGADA")} disabled={pendenteDeSalvar} className="flex-1 inline-flex items-center justify-center gap-2 bg-rose-600 text-white px-5 py-3 rounded-xl text-sm font-medium hover:bg-rose-700 disabled:opacity-50">
            <X className="size-4" /> Negar
          </button>
        </div>
      )}

      {isSupervisor && isPending && ft.lancado_por === user?.id && (
        <button
          onClick={() => setShowCancelModal(true)}
          className="inline-flex items-center gap-2 text-xs text-orange-600 hover:underline"
        >
          <AlertTriangle className="size-3" /> Solicitar cancelamento
        </button>
      )}

      {isGestor && !isCanceled && (
        <button onClick={() => { if (confirm("Cancelar esta movimentação?")) changeStatus("CANCELADA"); }} className="inline-flex items-center gap-2 text-xs text-rose-600 hover:underline">
          <Ban className="size-3" /> Cancelar lançamento
        </button>
      )}

      <Dialog open={showCancelModal} onOpenChange={(open) => { setShowCancelModal(open); if (!open) setMotivo(""); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Solicitar cancelamento</DialogTitle>
          </DialogHeader>
          <div className="space-y-3 py-2">
            <p className="text-sm text-muted-foreground">
              Informe o motivo do cancelamento. A solicitação será analisada pelo gestor.
            </p>
            <Textarea
              placeholder="Motivo obrigatório..."
              value={motivo}
              onChange={(e) => setMotivo(e.target.value)}
              rows={4}
              className="resize-none"
            />
          </div>
          <DialogFooter>
            <button
              onClick={() => { setShowCancelModal(false); setMotivo(""); }}
              className="px-4 py-2 text-sm border border-oak-medium rounded-xl hover:bg-oak-medium/20"
            >
              Voltar
            </button>
            <button
              onClick={solicitarCancelamento}
              disabled={!motivo.trim() || submitting}
              className="px-4 py-2 text-sm bg-orange-600 text-white rounded-xl hover:bg-orange-700 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {submitting ? "Enviando..." : "Enviar solicitação"}
            </button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <div className="bg-card border border-oak-light rounded-3xl overflow-hidden">
        <div className="px-8 py-5 border-b border-oak-light">
          <h3 className="text-sm font-medium">Histórico de alterações</h3>
        </div>
        {historico.length === 0 ? (
          <div className="p-8 text-center text-sm text-muted-foreground">Sem alterações.</div>
        ) : (
          <ul className="divide-y divide-oak-light">
            {historico.map((h) => (
              <li key={h.id} className="px-8 py-4 flex flex-wrap items-center justify-between gap-x-4 gap-y-1 text-sm">
                <div>
                  <span className="font-medium">{h.acao}</span>
                  {h.status_anterior && <span className="text-oak-dark/60"> • {h.status_anterior} → {h.status_novo}</span>}
                  {h.observacao && <span className="text-oak-dark/60"> • {h.observacao}</span>}
                </div>
                <span className="text-xs text-oak-dark/60 tabular-nums">{format(new Date(h.created_at), "dd/MM/yy HH:mm")}</span>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

function Info({ label, value, className = "" }: { label: string; value: string; className?: string }) {
  return (
    <div className={className}>
      <p className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">{label}</p>
      <p className="text-sm mt-1">{value}</p>
    </div>
  );
}
