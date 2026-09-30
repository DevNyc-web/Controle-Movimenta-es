import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { StatusBadge } from "@/components/StatusBadge";
import { format } from "date-fns";

export const Route = createFileRoute("/_app/historico")({
  component: Historico,
});

function Historico() {
  const [items, setItems] = useState<any[]>([]);

  useEffect(() => { load(); }, []);
  async function load() {
    const { data } = await supabase
      .from("ft")
      .select("*, funcionario:funcionarios!ft_funcionario_id_fkey(nome, re)")
      .in("status", ["CANCELADA", "NEGADA"])
      .order("updated_at", { ascending: false });
    setItems(data ?? []);
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-light tracking-tight">Histórico de Cancelamentos</h1>
        <p className="text-muted-foreground mt-1">Movimentações canceladas ou negadas.</p>
      </div>

      <div className="bg-card border border-oak-light rounded-3xl overflow-hidden">
        {items.length === 0 ? (
          <div className="p-12 text-center text-sm text-muted-foreground">Nenhum registro no histórico.</div>
        ) : (
          <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead>
              <tr className="bg-sand/30">
                <Th>Colaborador</Th><Th>Data</Th><Th>Escala</Th><Th>Status</Th><Th>Atualizado em</Th><Th>{"\u00A0"}</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-oak-light">
              {items.map((f) => (
                <tr key={f.id}>
                  <td className="px-8 py-4 text-sm font-medium">{f.funcionario?.nome}</td>
                  <td className="px-8 py-4 text-sm tabular-nums">{format(new Date(f.data_ft + "T00:00:00"), "dd/MM/yyyy")}</td>
                  <td className="px-8 py-4 text-sm">{f.escala_servico ?? f.tipo_folga ?? "—"}</td>
                  <td className="px-8 py-4"><StatusBadge status={f.status} /></td>
                  <td className="px-8 py-4 text-sm tabular-nums">{format(new Date(f.updated_at), "dd/MM/yy HH:mm")}</td>
                  <td className="px-8 py-4 text-right">
                    <Link to="/ft/$id" params={{ id: f.id }} className="text-xs font-semibold text-oak-dark hover:underline">Ver</Link>
                  </td>
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
