import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/auth";
import { StatusBadge } from "@/components/StatusBadge";
import { Plus, Search } from "lucide-react";
import { format } from "date-fns";

export const Route = createFileRoute("/_app/ft/")({
  component: FtList,
});

function FtList() {
  const { user, isSupervisor } = useAuth();
  const [items, setItems] = useState<any[]>([]);
  const [statusFilter, setStatusFilter] = useState<string>("TODOS");
  const [q, setQ] = useState("");
  const navigate = useNavigate();

  useEffect(() => { load(); }, []);
  async function load() {
    let query = supabase
      .from("ft")
      .select("*, funcionario:funcionarios!ft_funcionario_id_fkey(nome, cargo, re)")
      .order("data_ft", { ascending: false });
    if (isSupervisor) query = query.eq("lancado_por", user!.id);
    const { data } = await query;
    setItems(data ?? []);
  }

  const filtered = items.filter((i) => {
    if (statusFilter !== "TODOS" && i.status !== statusFilter) return false;
    if (q && !(i.funcionario?.nome?.toLowerCase().includes(q.toLowerCase()) || i.funcionario?.re?.includes(q))) return false;
    return true;
  });

  return (
    <div className="space-y-8">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 className="text-3xl font-light tracking-tight">Movimentações Operacionais</h1>
          <p className="text-muted-foreground mt-1">{items.length} lançamentos no total.</p>
        </div>
        <Link to="/ft/novo" className="inline-flex items-center justify-center gap-2 bg-oak-dark text-primary-foreground px-5 py-2.5 rounded-xl text-sm font-medium hover:opacity-90 w-full sm:w-auto">
          <Plus className="size-4" /> Nova Movimentação
        </Link>
      </div>

      <div className="bg-card border border-oak-light rounded-3xl overflow-hidden">
        <div className="px-8 py-5 border-b border-oak-light flex flex-col gap-4 sm:flex-row sm:items-center">
          <div className="flex items-center gap-2 flex-1">
            <Search className="size-4 text-oak-dark/40" />
            <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar colaborador..." className="bg-transparent text-sm focus:outline-none flex-1" />
          </div>
          <div className="flex flex-wrap gap-1">
            {["TODOS", "PENDENTE", "APROVADA", "NEGADA", "CANCELADA"].map((s) => (
              <button key={s} onClick={() => setStatusFilter(s)} className={`px-3 py-1.5 rounded-lg text-[10px] font-bold uppercase tracking-wider transition-colors ${statusFilter === s ? "bg-oak-dark text-primary-foreground" : "text-oak-dark/60 hover:bg-oak-medium/30"}`}>
                {s}
              </button>
            ))}
          </div>
        </div>

        {filtered.length === 0 ? (
          <div className="p-12 text-center text-sm text-muted-foreground">Nenhuma movimentação encontrada.</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left">
              <thead>
                <tr className="bg-sand/30">
                  <Th>Nº</Th><Th>Colaborador</Th><Th>Data</Th><Th>Posto</Th><Th>Escala</Th><Th>Horas</Th><Th>Status</Th>
                </tr>
              </thead>
              <tbody className="divide-y divide-oak-light">
                {filtered.map((f) => (
                  <tr key={f.id} className="hover:bg-sand/20 cursor-pointer" onClick={() => navigate({ to: "/ft/$id", params: { id: f.id } })}>
                    <td className="px-8 py-5">
                      <p className="text-xs font-mono text-oak-dark/70">{f.numero_ft ?? "—"}</p>
                    </td>
                    <td className="px-8 py-5">
                      <p className="text-sm font-medium">{f.funcionario?.nome ?? "—"}</p>
                      <p className="text-[10px] text-oak-dark/60">RE {f.funcionario?.re}</p>
                    </td>
                    <td className="px-8 py-5 text-sm tabular-nums">{format(new Date(f.data_ft + "T00:00:00"), "dd/MM/yyyy")}</td>
                    <td className="px-8 py-5 text-sm max-w-[200px] truncate" title={f.posto_falta ?? ""}>{f.posto_falta ?? "—"}</td>
                    <td className="px-8 py-5 text-sm">{f.escala_servico ?? f.tipo_folga ?? "—"}</td>
                    <td className="px-8 py-5 text-sm font-medium tabular-nums">{f.horas_trabalhadas}h</td>
                    <td className="px-8 py-5"><StatusBadge status={f.status} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}

function Th({ children }: { children: React.ReactNode }) {
  return <th className="px-8 py-4 text-[10px] font-bold text-oak-dark/50 uppercase tracking-widest">{children}</th>;
}
