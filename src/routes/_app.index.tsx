import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { StatusBadge } from "@/components/StatusBadge";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
import { ClipboardList, CheckCircle2, XCircle, Clock } from "lucide-react";

export const Route = createFileRoute("/_app/")({
  component: Dashboard,
});

interface Kpis {
  pendentes: number;
  aprovadas: number;
  negadas: number;
  horas: number;
}

function Dashboard() {
  const [kpis, setKpis] = useState<Kpis>({ pendentes: 0, aprovadas: 0, negadas: 0, horas: 0 });
  const [recent, setRecent] = useState<any[]>([]);
  const [chartData, setChartData] = useState<{ dia: string; total: number }[]>([]);

  useEffect(() => {
    load();
  }, []);

  async function load() {
    const monthStart = new Date();
    monthStart.setDate(1);
    monthStart.setHours(0, 0, 0, 0);
    const iso = monthStart.toISOString().split("T")[0];

    const { data: ftAll } = await supabase
      .from("ft")
      .select("status, horas_trabalhadas, data_ft")
      .gte("data_ft", iso);

    const k: Kpis = { pendentes: 0, aprovadas: 0, negadas: 0, horas: 0 };
    const byDay: Record<string, number> = {};
    (ftAll ?? []).forEach((f: any) => {
      if (f.status === "PENDENTE") k.pendentes++;
      if (f.status === "APROVADA") {
        k.aprovadas++;
        k.horas += Number(f.horas_trabalhadas);
      }
      if (f.status === "NEGADA") k.negadas++;
      byDay[f.data_ft] = (byDay[f.data_ft] ?? 0) + 1;
    });
    setKpis(k);

    const days = Object.keys(byDay).sort().slice(-7);
    setChartData(days.map((d) => ({ dia: d.slice(8, 10), total: byDay[d] })));

    const { data: rec } = await supabase
      .from("ft")
      .select("id, data_ft, horas_trabalhadas, status, motivo, funcionario:funcionarios!ft_funcionario_id_fkey(nome, cargo)")
      .order("created_at", { ascending: false })
      .limit(5);
    setRecent(rec ?? []);
  }

  const maxBar = Math.max(...chartData.map((d) => d.total), 1);

  return (
    <div className="space-y-10">
      <div>
        <h1 className="text-3xl font-light tracking-tight">Painel de Controle</h1>
        <p className="text-muted-foreground mt-1">Monitoramento de Movimentações Operacionais no mês corrente.</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <KpiCard label="Movimentações Pendentes" value={kpis.pendentes} icon={<Clock className="size-4" />} />
        <KpiCard label="Aprovadas" value={kpis.aprovadas} icon={<CheckCircle2 className="size-4" />} />
        <KpiCard label="Negadas" value={kpis.negadas} icon={<XCircle className="size-4" />} />
        <KpiCard label="Horas no Mês" value={`${kpis.horas}h`} icon={<ClipboardList className="size-4" />} />
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-8">
        <div className="xl:col-span-2 bg-card rounded-3xl border border-oak-light overflow-hidden shadow-sm">
          <div className="px-8 py-6 border-b border-oak-light flex items-center justify-between">
            <h2 className="text-lg font-medium">Solicitações Recentes</h2>
            <Link to="/ft" className="text-xs font-semibold text-oak-dark hover:underline">Ver todas</Link>
          </div>
          {recent.length === 0 ? (
            <div className="p-12 text-center text-sm text-muted-foreground">
              Nenhuma movimentação registrada ainda.{" "}
              <Link to="/ft/novo" className="text-oak-dark font-medium hover:underline">Registrar primeira movimentação</Link>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-left">
                <thead>
                  <tr className="bg-sand/30">
                    <Th>Colaborador</Th>
                    <Th>Data</Th>
                    <Th>Horas</Th>
                    <Th>Status</Th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-oak-light">
                  {recent.map((r) => (
                    <tr key={r.id} className="hover:bg-sand/20 transition-colors">
                      <td className="px-8 py-5">
                        <p className="text-sm font-medium">{r.funcionario?.nome ?? "—"}</p>
                        <p className="text-[10px] text-oak-dark/60">{r.funcionario?.cargo ?? ""}</p>
                      </td>
                      <td className="px-8 py-5 text-sm tabular-nums">
                        {format(new Date(r.data_ft + "T00:00:00"), "dd MMM", { locale: ptBR })}
                      </td>
                      <td className="px-8 py-5 text-sm font-medium tabular-nums">{r.horas_trabalhadas}h</td>
                      <td className="px-8 py-5"><StatusBadge status={r.status} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

        <div className="space-y-8">
          <div className="bg-oak-dark text-primary-foreground p-8 rounded-3xl shadow-xl shadow-oak-dark/20 relative overflow-hidden">
            <div className="relative z-10">
              <h3 className="text-lg font-light italic opacity-90 mb-6">Volume Semanal</h3>
              {chartData.length === 0 ? (
                <p className="text-xs opacity-70">Sem dados ainda</p>
              ) : (
                <>
                  <div className="flex items-end gap-3 h-32 mb-6">
                    {chartData.map((d, i) => (
                      <div key={i} className="flex-1 bg-primary-foreground/30 rounded-t-lg flex items-end justify-center" style={{ height: `${(d.total / maxBar) * 100}%` }}>
                        <span className="text-[10px] opacity-0">{d.total}</span>
                      </div>
                    ))}
                  </div>
                  <div className="flex justify-between text-[10px] opacity-70">
                    {chartData.map((d, i) => <span key={i}>{d.dia}</span>)}
                  </div>
                </>
              )}
            </div>
            <div className="absolute -right-10 -bottom-10 size-40 bg-primary-foreground/10 blur-3xl rounded-full" />
          </div>

          <div className="bg-card border border-oak-light p-6 rounded-3xl">
            <h3 className="text-[10px] font-bold uppercase tracking-widest text-oak-dark/50 mb-4">Atalhos</h3>
            <div className="space-y-2">
              <Link to="/ft/novo" className="block px-4 py-3 bg-sand rounded-xl text-sm font-medium hover:bg-oak-medium/30 transition-colors">+ Nova Movimentação</Link>
              <Link to="/funcionarios/novo" className="block px-4 py-3 bg-sand rounded-xl text-sm font-medium hover:bg-oak-medium/30 transition-colors">+ Cadastrar funcionário</Link>
              <Link to="/aprovacoes" className="block px-4 py-3 bg-sand rounded-xl text-sm font-medium hover:bg-oak-medium/30 transition-colors">Aprovações pendentes</Link>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function KpiCard({ label, value, icon }: { label: string; value: number | string; icon: React.ReactNode }) {
  return (
    <div className="bg-card border border-oak-light p-6 rounded-2xl transition-all duration-300 hover:shadow-lg hover:shadow-oak-dark/5">
      <div className="flex items-start justify-between">
        <span className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">{label}</span>
        <div className="text-oak-dark/40">{icon}</div>
      </div>
      <p className="text-4xl font-light tabular-nums mt-3">{value}</p>
    </div>
  );
}

function Th({ children }: { children: React.ReactNode }) {
  return <th className="px-8 py-4 text-[10px] font-bold text-oak-dark/50 uppercase tracking-widest">{children}</th>;
}
