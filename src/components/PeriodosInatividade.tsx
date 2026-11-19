import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/auth";
import { toast } from "sonner";
import { format } from "date-fns";
import { formatarData, JUSTIFICATIVA_MIN, justificativaValida, mensagemRegra } from "@/lib/funcionario-status";

interface Periodo {
  id: string;
  inicio: string;
  fim: string | null;
  motivo_reativacao: string | null;
  anulada_em: string | null;
  anulacao_justificativa: string | null;
}

/** Histórico de inatividade do funcionário, visível ao Gestor. A RLS e a RPC são quem decide; a tela só oferece a ação. */
export function PeriodosInatividade({ funcionarioId, inativo }: { funcionarioId: string; inativo: boolean }) {
  const { isGestor } = useAuth();
  const [periodos, setPeriodos] = useState<Periodo[]>([]);

  const carregar = useCallback(async () => {
    const { data, error } = await supabase
      .from("funcionario_inatividades")
      .select("id, inicio, fim, motivo_reativacao, anulada_em, anulacao_justificativa")
      .eq("funcionario_id", funcionarioId)
      .order("inicio", { ascending: false });
    if (error) toast.error("Não foi possível carregar os períodos de inatividade.");
    setPeriodos((data ?? []) as Periodo[]);
  }, [funcionarioId]);

  useEffect(() => {
    if (isGestor) carregar();
  }, [carregar, isGestor]);

  async function anular(p: Periodo) {
    const justificativa = prompt(
      `Anular o período de ${formatarData(p.inicio)} a ${formatarData(p.fim)}? Use só se foi registrado por engano. A ação é auditada e não pode ser desfeita.\n\nJustificativa (pelo menos ${JUSTIFICATIVA_MIN} letras ou números):`,
    );
    if (justificativa === null) return;
    if (!justificativaValida(justificativa)) return toast.error(`Informe a justificativa com pelo menos ${JUSTIFICATIVA_MIN} letras ou números.`);
    const { error } = await supabase.rpc("anular_inatividade", { _periodo_id: p.id, _justificativa: justificativa.trim() });
    if (error) toast.error(mensagemRegra(error.message));
    else {
      toast.success("Período anulado");
      carregar();
    }
  }

  if (!isGestor || periodos.length === 0) return null;

  return (
    <section className="bg-card border border-oak-light rounded-3xl p-8 space-y-4">
      <h2 className="text-sm font-medium">Períodos de inatividade</h2>
      <ul className="divide-y divide-oak-light text-sm">
        {periodos.map((p) => (
          <li key={p.id} className="py-3 flex flex-wrap items-start justify-between gap-3">
            <div className={p.anulada_em ? "text-oak-dark/60" : ""}>
              <p className="font-medium">
                {formatarData(p.inicio)} a {p.fim ? formatarData(p.fim) : "em curso"}
                {p.anulada_em && <span className="ml-2 text-[10px] font-semibold uppercase text-amber-700">Anulado</span>}
              </p>
              {p.motivo_reativacao && <p className="text-xs mt-1">Reativação: {p.motivo_reativacao}</p>}
              {p.anulada_em && (
                <p className="text-xs mt-1">
                  Anulado em {format(new Date(p.anulada_em), "dd/MM/yyyy HH:mm")}: {p.anulacao_justificativa}
                </p>
              )}
            </div>
            {p.fim && !p.anulada_em && !inativo && (
              <button type="button" onClick={() => anular(p)} className="text-xs text-rose-600 hover:underline">
                Anular período
              </button>
            )}
          </li>
        ))}
      </ul>
    </section>
  );
}
