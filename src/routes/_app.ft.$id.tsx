import { createFileRoute, useParams, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/auth";
import { StatusBadge } from "@/components/StatusBadge";
import { toast } from "sonner";
import { ChevronLeft, Check, X, Ban } from "lucide-react";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";

export const Route = createFileRoute("/_app/ft/$id")({
  component: FtDetalhe,
});

function FtDetalhe() {
  const { id } = useParams({ from: "/_app/ft/$id" });
  const { user, isGestor } = useAuth();
  const navigate = useNavigate();
  const [ft, setFt] = useState<any>(null);
  const [historico, setHistorico] = useState<any[]>([]);

  useEffect(() => { load(); }, [id]);
  async function load() {
    const { data } = await supabase.from("ft").select("*, funcionario:funcionarios!ft_funcionario_id_fkey(*), funcionario_faltante:funcionarios!ft_funcionario_faltante_id_fkey(nome, re)").eq("id", id).maybeSingle();
    setFt(data);
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

  if (!ft) return <div className="text-sm text-muted-foreground">Carregando...</div>;

  const isPending = ft.status === "PENDENTE";
  const isCanceled = ft.status === "CANCELADA";

  return (
    <div className="space-y-8 max-w-4xl">
      <Link to="/ft" className="inline-flex items-center gap-1 text-xs text-primary hover:underline">
        <ChevronLeft className="size-3" /> Voltar
      </Link>

      <div className="flex items-start justify-between">
        <div>
          <p className="text-[10px] font-bold text-muted-foreground uppercase tracking-widest">Movimentação #{ft.id.slice(0, 8)}</p>
          <h1 className="text-3xl font-light tracking-tight mt-1">{ft.funcionario?.nome}</h1>
          <p className="text-muted-foreground mt-1">{ft.funcionario?.cargo} • {ft.funcionario?.setor}</p>
        </div>
        <StatusBadge status={ft.status} />
      </div>

      <div className="bg-card border border-border rounded-3xl p-8 grid grid-cols-2 gap-6">
        <Info label="Data" value={format(new Date(ft.data_ft + "T00:00:00"), "dd 'de' MMMM, yyyy", { locale: ptBR })} />
        <Info label="Posto da falta" value={ft.posto_falta ?? "—"} className="col-span-2" />
        <Info label="Escala" value={ft.escala_servico ?? ft.tipo_folga ?? "—"} />
        <Info label="Horas trabalhadas" value={`${ft.horas_trabalhadas}h`} />
        <Info label="Horas compensadas" value={`${ft.horas_compensadas}h`} />
        {ft.motivo && <Info label="Motivo da cobertura" value={ft.motivo} />}
        {ft.funcionario_faltante && (
          <Info label="Funcionário faltante" value={`${ft.funcionario_faltante.nome} (RE ${ft.funcionario_faltante.re})`} className="col-span-2" />
        )}
        {ft.observacao && <Info label="Observação" value={ft.observacao} className="col-span-2" />}
        <Info label="Lançada em" value={format(new Date(ft.data_lancamento), "dd/MM/yyyy HH:mm")} />
        {ft.data_cancelamento && <Info label="Cancelada em" value={format(new Date(ft.data_cancelamento), "dd/MM/yyyy HH:mm")} />}
      </div>

      {isPending && isGestor && (
        <div className="flex gap-3">
          <button onClick={() => changeStatus("APROVADA")} className="flex-1 inline-flex items-center justify-center gap-2 bg-emerald-600 text-white px-5 py-3 rounded-xl text-sm font-medium hover:bg-emerald-700">
            <Check className="size-4" /> Aprovar
          </button>
          <button onClick={() => changeStatus("NEGADA")} className="flex-1 inline-flex items-center justify-center gap-2 bg-rose-600 text-white px-5 py-3 rounded-xl text-sm font-medium hover:bg-rose-700">
            <X className="size-4" /> Negar
          </button>
        </div>
      )}

      {!isCanceled && (
        <button onClick={() => { if (confirm("Cancelar esta movimentação?")) changeStatus("CANCELADA"); }} className="inline-flex items-center gap-2 text-xs text-rose-600 hover:underline">
          <Ban className="size-3" /> Cancelar lançamento
        </button>
      )}

      <div className="bg-card border border-border rounded-3xl overflow-hidden">
        <div className="px-8 py-5 border-b border-border">
          <h3 className="text-sm font-medium">Histórico de alterações</h3>
        </div>
        {historico.length === 0 ? (
          <div className="p-8 text-center text-sm text-muted-foreground">Sem alterações.</div>
        ) : (
          <ul className="divide-y divide-border">
            {historico.map((h) => (
              <li key={h.id} className="px-8 py-4 flex items-center justify-between text-sm">
                <div>
                  <span className="font-medium">{h.acao}</span>
                  {h.status_anterior && <span className="text-muted-foreground"> • {h.status_anterior} → {h.status_novo}</span>}
                </div>
                <span className="text-xs text-muted-foreground tabular-nums">{format(new Date(h.created_at), "dd/MM/yy HH:mm")}</span>
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
      <p className="text-[10px] font-bold text-muted-foreground uppercase tracking-widest">{label}</p>
      <p className="text-sm mt-1">{value}</p>
    </div>
  );
}
