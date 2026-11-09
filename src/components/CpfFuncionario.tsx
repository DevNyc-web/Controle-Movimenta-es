import { useCallback, useEffect, useState } from "react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useAuth } from "@/lib/auth";
import { JUSTIFICATIVA_MIN, justificativaValida, mensagemRegra } from "@/lib/funcionario-status";
import { cpfDaCelula, cpfValido, mascararCpf } from "@/lib/importacao-funcionarios";

const inp = "w-full px-3 py-2 bg-sand rounded-xl text-sm border-none focus:outline-none focus:ring-2 focus:ring-oak-dark/20";
const btn = "px-3 py-2 rounded-xl text-xs font-medium disabled:opacity-50";

/** CPF nos detalhes: só o Gestor vê (pela função do banco), mascarado por padrão. Alterar exige justificativa e fica auditado. */
export function CpfFuncionario({ funcionarioId }: { funcionarioId: string }) {
  const { isGestor } = useAuth();
  const [cpf, setCpf] = useState<string | null | undefined>(undefined);
  const [mostrar, setMostrar] = useState(false);
  const [editando, setEditando] = useState(false);

  const carregar = useCallback(async () => {
    const { data, error } = await supabase.rpc("funcionario_cpf", { _id: funcionarioId });
    if (error) return void setCpf(undefined);
    setCpf(data ?? null);
  }, [funcionarioId]);
  useEffect(() => { if (isGestor) carregar(); }, [isGestor, carregar]);

  if (!isGestor || cpf === undefined) return null;
  return (
    <section className="bg-card border border-oak-light rounded-3xl p-8 space-y-3">
      <h2 className="text-sm font-medium">CPF</h2>
      <div className="flex flex-wrap items-center gap-3 text-sm">
        <span className="tabular-nums" aria-label="CPF do funcionário">{cpf ? (mostrar ? cpf.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, "$1.$2.$3-$4") : mascararCpf(cpf)) : "Não informado"}</span>
        {cpf && <button onClick={() => setMostrar((m) => !m)} className={`${btn} bg-oak-medium/30`}>{mostrar ? "Ocultar" : "Mostrar"}</button>}
        <button onClick={() => setEditando(true)} className={`${btn} bg-oak-dark text-primary-foreground`}>{cpf ? "Corrigir CPF" : "Informar CPF"}</button>
      </div>
      {editando && <DialogoCpf funcionarioId={funcionarioId} temCpf={!!cpf} fechar={() => setEditando(false)} concluido={() => { setEditando(false); setMostrar(false); carregar(); }} />}
    </section>
  );
}

function DialogoCpf({ funcionarioId, temCpf, fechar, concluido }: { funcionarioId: string; temCpf: boolean; fechar: () => void; concluido: () => void }) {
  const [novo, setNovo] = useState("");
  const [justificativa, setJustificativa] = useState("");
  const [salvando, setSalvando] = useState(false);
  const digitos = cpfDaCelula(novo);
  const valido = cpfValido(digitos) && justificativaValida(justificativa);
  async function salvar() {
    setSalvando(true);
    const { error } = await supabase.rpc("funcionario_alterar_cpf", { _id: funcionarioId, _cpf: digitos, _justificativa: justificativa.trim() });
    setSalvando(false);
    if (error) return void toast.error(mensagemRegra(error.message));
    toast.success("CPF atualizado.");
    concluido();
  }
  return (
    <Dialog open onOpenChange={(o) => !o && fechar()}>
      <DialogContent>
        <DialogHeader><DialogTitle>{temCpf ? "Corrigir CPF" : "Informar CPF"}</DialogTitle></DialogHeader>
        <div className="space-y-3 text-sm">
          <label className="block text-xs">Novo CPF *
            <input value={novo} onChange={(e) => setNovo(e.target.value)} inputMode="numeric" className={`${inp} mt-1`} aria-label="Novo CPF" />
          </label>
          {novo && !cpfValido(digitos) && <p className="text-xs text-amber-800">CPF inválido.</p>}
          <label className="block text-xs">Justificativa * (pelo menos {JUSTIFICATIVA_MIN} letras ou números)
            <textarea value={justificativa} onChange={(e) => setJustificativa(e.target.value)} rows={3} className={`${inp} mt-1`} />
          </label>
          <p className="text-xs text-oak-dark/70">A alteração fica registrada na auditoria. As FTs do funcionário não são alteradas.</p>
        </div>
        <DialogFooter>
          <button onClick={fechar} className={`${btn} bg-oak-medium/30`}>Cancelar</button>
          <button onClick={salvar} disabled={!valido || salvando} className={`${btn} bg-oak-dark text-primary-foreground`}>Salvar</button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
