import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/auth";
import { StatusBadge } from "@/components/StatusBadge";
import { toast } from "sonner";
import { Check, X } from "lucide-react";
import { format } from "date-fns";

export const Route = createFileRoute("/_app/aprovacoes")({
  component: Aprovacoes,
});

function Aprovacoes() {
  const { user, isGestor } = useAuth();
  const [items, setItems] = useState<any[]>([]);
  const navigate = useNavigate();

  useEffect(() => { load(); }, []);
  async function load() {
    const { data } = await supabase.from("ft").select("*, funcionario:funcionarios!ft_funcionario_id_fkey(nome, cargo, re)").eq("status", "PENDENTE").order("data_lancamento");
    setItems(data ?? []);
  }

  async function decide(id: string, status: "APROVADA" | "NEGADA") {
    const { error } = await supabase.from("ft").update({ status, aprovado_por: user?.id }).eq("id", id);
    if (error) toast.error(error.message);
    else {
      toast.success(`Movimentação ${status.toLowerCase()}`);
      load();
    }
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-light tracking-tight">Aprovações Pendentes</h1>
        <p className="text-muted-foreground mt-1">{items.length} movimentação(ões) aguardando análise.</p>
      </div>

      {!isGestor && (
        <div className="bg-amber-50 border border-amber-200 text-amber-800 rounded-2xl p-4 text-sm">
          Somente gestores podem aprovar ou negar movimentações. Você pode visualizar a fila.
        </div>
      )}

      {items.length === 0 ? (
        <div className="bg-card border border-border rounded-3xl p-12 text-center text-sm text-muted-foreground">
          Nenhuma movimentação pendente. Tudo em dia! ✨
        </div>
      ) : (
        <div className="space-y-4">
          {items.map((f) => (
            <div key={f.id} className="bg-card border border-border rounded-3xl p-6 flex items-center gap-6 hover:shadow-md transition-shadow">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-3">
                  <p className="font-medium">{f.funcionario?.nome}</p>
                  <StatusBadge status={f.status} />
                </div>
                <p className="text-xs text-muted-foreground mt-1">
                  {f.funcionario?.cargo} • RE {f.funcionario?.re} • {format(new Date(f.data_ft + "T00:00:00"), "dd/MM/yyyy")} • {f.posto_falta ?? "—"} • {f.horas_trabalhadas}h • {f.escala_servico ?? f.tipo_folga ?? "—"}
                </p>
                {f.observacao && <p className="text-sm mt-2 text-foreground/80">{f.observacao}</p>}
              </div>
              <div className="flex gap-2 shrink-0">
                <button onClick={() => navigate({ to: "/ft/$id", params: { id: f.id } })} className="px-4 py-2 text-xs font-medium border border-border rounded-xl hover:bg-accent">
                  Detalhes
                </button>
                {isGestor && (
                  <>
                    <button onClick={() => decide(f.id, "APROVADA")} className="inline-flex items-center gap-1 px-4 py-2 text-xs font-medium bg-emerald-600 text-white rounded-xl hover:bg-emerald-700">
                      <Check className="size-3" /> Aprovar
                    </button>
                    <button onClick={() => decide(f.id, "NEGADA")} className="inline-flex items-center gap-1 px-4 py-2 text-xs font-medium bg-rose-600 text-white rounded-xl hover:bg-rose-700">
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
  );
}
