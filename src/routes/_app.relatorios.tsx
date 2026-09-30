import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { StatusBadge } from "@/components/StatusBadge";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
import { agruparPorFuncionario, totaisGerais, LABEL_FOLHA } from "@/lib/relatorio";
import { buildWorkbook } from "@/lib/relatorio-excel";
import { FileSpreadsheet } from "lucide-react";
import { POSTOS_FALTA } from "@/lib/postos";

export const Route = createFileRoute("/_app/relatorios")({
  component: Relatorios,
});

const CARGOS = ["", "Vigilante", "Porteiro", "ASG", "Recepcionista", "Manutencista", "Freelancer"];

function Relatorios() {
  const today = new Date();
  const first = new Date(today.getFullYear(), today.getMonth(), 1);
  const last = new Date(today.getFullYear(), today.getMonth() + 1, 0);

  const [start, setStart] = useState(first.toISOString().split("T")[0]);
  const [end, setEnd] = useState(last.toISOString().split("T")[0]);
  const [nome, setNome] = useState("");
  const [cargo, setCargo] = useState("");
  const [posto, setPosto] = useState("");
  const [raw, setRaw] = useState<any[]>([]);
  const [exporting, setExporting] = useState(false);

  useEffect(() => { load(); }, [start, end]);
  async function load() {
    const { data } = await supabase
      .from("ft")
      .select("*, funcionario:funcionarios!ft_funcionario_id_fkey(nome, re, setor, cargo), funcionario_faltante:funcionarios!ft_funcionario_faltante_id_fkey(nome, re)")
      .gte("data_ft", start)
      .lte("data_ft", end)
      .order("data_ft");
    setRaw(data ?? []);
  }

  const items = useMemo(() => raw.filter((i) => {
    if (nome && !(i.funcionario?.nome ?? "").toLowerCase().includes(nome.toLowerCase())) return false;
    if (cargo && i.funcionario?.cargo !== cargo) return false;
    if (posto && i.posto_falta !== posto) return false;
    return true;
  }), [raw, nome, cargo, posto]);

  const totals = useMemo(() => totaisGerais(items), [items]);
  const grupos = useMemo(() => agruparPorFuncionario(items), [items]);

  async function exportExcel() {
    setExporting(true);
    try {
      const emitido = `Emitido em ${format(new Date(), "dd 'de' MMMM 'de' yyyy 'às' HH:mm", { locale: ptBR })}`;
      const wb = buildWorkbook(items, start, end, emitido);
      const buf = await wb.xlsx.writeBuffer();
      const blob = new Blob([buf], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `movimentacao_operacional_${start}_${end}.xlsx`;
      a.click();
      URL.revokeObjectURL(url);
    } finally {
      setExporting(false);
    }
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-light tracking-tight">Relatórios</h1>
        <p className="text-muted-foreground mt-1">Consolidado de Movimentações Operacionais por período.</p>
      </div>

      <div className="bg-card border border-oak-light rounded-3xl p-6 flex flex-col gap-5 sm:flex-row sm:flex-wrap sm:items-end">
        <div className="w-full sm:w-auto">
          <label className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">Início</label>
          <input type="date" value={start} onChange={(e) => setStart(e.target.value)} className="mt-2 w-full px-4 py-2.5 bg-sand rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-oak-dark/20" />
        </div>
        <div className="w-full sm:w-auto">
          <label className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">Fim</label>
          <input type="date" value={end} onChange={(e) => setEnd(e.target.value)} className="mt-2 w-full px-4 py-2.5 bg-sand rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-oak-dark/20" />
        </div>
        <div className="w-full sm:w-auto">
          <label className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">Nome</label>
          <input type="text" value={nome} onChange={(e) => setNome(e.target.value)} placeholder="buscar..." className="mt-2 w-full px-4 py-2.5 bg-sand rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-oak-dark/20" />
        </div>
        <div className="w-full sm:w-auto">
          <label className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">Cargo</label>
          <select value={cargo} onChange={(e) => setCargo(e.target.value)} className="mt-2 w-full px-4 py-2.5 bg-sand rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-oak-dark/20">
            {CARGOS.map((c) => <option key={c} value={c}>{c || "Todos"}</option>)}
          </select>
        </div>
        <div className="w-full sm:min-w-[200px] sm:flex-1">
          <label className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">Posto da falta</label>
          <select value={posto} onChange={(e) => setPosto(e.target.value)} className="mt-2 w-full px-4 py-2.5 bg-sand rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-oak-dark/20">
            <option value="">Todos</option>
            {POSTOS_FALTA.map((p) => <option key={p} value={p}>{p}</option>)}
          </select>
        </div>
        <button onClick={exportExcel} disabled={exporting || items.length === 0} className="w-full sm:w-auto sm:ml-auto inline-flex items-center justify-center gap-2 px-5 py-2.5 bg-oak-dark text-primary-foreground rounded-xl text-sm font-medium hover:opacity-90 disabled:opacity-50">
          <FileSpreadsheet className="size-4" />
          {exporting ? "Gerando..." : "Exportar Excel"}
        </button>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-5 gap-4">
        <Stat label="Total" value={totals.total} />
        <Stat label="Horas trab." value={`${totals.horas}h`} />
        <Stat label="Valor total" value={`R$ ${totals.valor.toFixed(2)}`} />
        <Stat label="Aprovadas" value={totals.APROVADA} />
        <Stat label="Pendentes" value={totals.PENDENTE} />
      </div>

      <div className="bg-card border border-oak-light rounded-3xl overflow-hidden">
        {items.length === 0 ? (
          <div className="p-12 text-center text-sm text-muted-foreground">Nenhuma movimentação no período.</div>
        ) : (
          <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead>
              <tr className="bg-sand/30">
                <Th>Data</Th><Th>Colaborador</Th><Th>Cargo</Th><Th>Funcionário faltante</Th><Th>Posto</Th><Th>Horas</Th><Th>Valor</Th><Th>Status</Th>
              </tr>
            </thead>
            {grupos.map((g) => (
              <tbody key={g.funcionarioId} className="divide-y divide-oak-light border-t-4 border-oak-light">
                <tr className="bg-sand/50">
                  <td colSpan={8} className="px-6 py-3 text-sm font-semibold">{g.nome} <span className="text-[10px] font-normal text-oak-dark/60">RE {g.re}</span></td>
                </tr>
                {g.items.map((i: any) => (
                  <tr key={i.id}>
                    <td className="px-6 py-4 text-sm tabular-nums">{format(new Date(i.data_ft + "T00:00:00"), "dd/MM/yy")}</td>
                    <td className="px-6 py-4 text-sm font-medium">{i.funcionario?.nome}</td>
                    <td className="px-6 py-4 text-sm">{i.funcionario?.cargo ?? "—"}</td>
                    <td className="px-6 py-4 text-sm">{i.funcionario_faltante?.nome ?? "—"}</td>
                    <td className="px-6 py-4 text-sm max-w-[180px] truncate" title={i.posto_falta ?? ""}>{i.posto_falta ?? "—"}</td>
                    <td className="px-6 py-4 text-sm tabular-nums">{i.horas_trabalhadas}h</td>
                    <td className="px-6 py-4 text-sm tabular-nums">{i.pagamento_em_folha ? <span className="text-[10px] font-bold uppercase tracking-wider text-oak-dark/70">{LABEL_FOLHA}</span> : `R$ ${Number(i.valor_pago ?? 0).toFixed(2)}`}</td>
                    <td className="px-6 py-4"><StatusBadge status={i.status} /></td>
                  </tr>
                ))}
                <tr className="bg-sand/30 font-semibold">
                  <td colSpan={5} className="px-6 py-3 text-sm text-right">TOTAL {g.nome}</td>
                  <td className="px-6 py-3 text-sm tabular-nums">{g.horas}h</td>
                  <td className="px-6 py-3 text-sm tabular-nums">R$ {g.valor.toFixed(2)}</td>
                  <td className="px-6 py-3 text-xs text-oak-dark/60">{g.items.length} reg.</td>
                </tr>
              </tbody>
            ))}
          </table>
          </div>
        )}
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="bg-card border border-oak-light p-5 rounded-2xl">
      <p className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">{label}</p>
      <p className="text-2xl font-light tabular-nums mt-2">{value}</p>
    </div>
  );
}

function Th({ children }: { children: React.ReactNode }) {
  return <th className="px-6 py-4 text-[10px] font-bold text-oak-dark/50 uppercase tracking-widest">{children}</th>;
}
