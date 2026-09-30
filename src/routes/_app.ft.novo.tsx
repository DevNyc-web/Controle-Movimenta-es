import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/auth";
import { toast } from "sonner";
import { FuncionarioPicker } from "@/components/FuncionarioPicker";
import { PostoCombobox } from "@/components/PostoCombobox";

export const Route = createFileRoute("/_app/ft/novo")({
  component: NovaMovimentacao,
});

const ESCALAS = ["06x18", "18x06", "07x19", "19x07", "08x18", "Outros"];
const MOTIVOS = ["Falta", "Atestado", "Remanejamento", "Reciclagem", "Falta de efetivo"];

function NovaMovimentacao() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [form, setForm] = useState({
    funcionario_id: "",
    funcionario_faltante_id: "",
    data_ft: new Date().toISOString().split("T")[0],
    escala_servico: "06x18",
    escala_outros: "",
    motivo: "Falta",
    horas_compensadas: 0,
    observacao: "",
    posto_falta: "",
  });
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!form.funcionario_id) return toast.error("Selecione um funcionário");
    if (!form.posto_falta.trim()) return toast.error("Selecione o posto onde ocorreu a falta");
    if (form.escala_servico === "Outros" && !form.escala_outros.trim())
      return toast.error("Informe a escala em 'Outros'");

    setLoading(true);
    const escala = form.escala_servico === "Outros" ? form.escala_outros.trim() : form.escala_servico;
    const horasMap: Record<string, number> = { "06x18": 12, "18x06": 12, "07x19": 12, "19x07": 12, "08x18": 10 };
    const horas = horasMap[form.escala_servico] ?? 0;

    const { error } = await supabase.from("ft").insert({
      funcionario_id: form.funcionario_id,
      funcionario_faltante_id: form.funcionario_faltante_id || null,
      data_ft: form.data_ft,
      escala_servico: escala,
      motivo: form.motivo,
      horas_trabalhadas: horas,
      horas_compensadas: Number(form.horas_compensadas),
      observacao: form.observacao || null,
      posto_falta: form.posto_falta,
      lancado_por: user?.id,
    });
    setLoading(false);
    if (error) {
      if (error.code === "23505") toast.error("Já existe uma movimentação para este funcionário nesta data.");
      else toast.error(error.message);
    } else {
      toast.success("Movimentação registrada");
      navigate({ to: "/ft" });
    }
  }

  const set = (k: string) => (e: any) => setForm({ ...form, [k]: e.target.value });

  return (
    <div className="space-y-8 max-w-3xl">
      <div>
        <h1 className="text-3xl font-light tracking-tight">Nova Movimentação</h1>
        <p className="text-muted-foreground mt-1">Registrar uma movimentação operacional.</p>
      </div>

      <form onSubmit={handleSubmit} className="bg-card border border-oak-light rounded-3xl p-8 space-y-6">
        <FuncionarioPicker
          label="Funcionário"
          value={form.funcionario_id}
          onChange={(id) => setForm({ ...form, funcionario_id: id })}
          required
          excludeId={form.funcionario_faltante_id}
        />

        <FuncionarioPicker
          label="Funcionário faltante"
          value={form.funcionario_faltante_id}
          onChange={(id) => setForm({ ...form, funcionario_faltante_id: id })}
          excludeId={form.funcionario_id}
        />

        <PostoCombobox
          value={form.posto_falta}
          onChange={(posto_falta) => setForm({ ...form, posto_falta })}
          required
        />

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
          <div>
            <label className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">Data</label>
            <input type="date" required value={form.data_ft} onChange={set("data_ft")} className="mt-2 w-full px-4 py-2.5 bg-sand rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-oak-dark/20" />
          </div>
          <div>
            <label className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">Horas trabalhadas (escala)</label>
            <select value={form.escala_servico} onChange={set("escala_servico")} className="mt-2 w-full px-4 py-2.5 bg-sand rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-oak-dark/20">
              {ESCALAS.map((e) => <option key={e}>{e}</option>)}
            </select>
          </div>
          {form.escala_servico === "Outros" && (
            <div className="col-span-2">
              <label className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">Especifique a escala</label>
              <input required value={form.escala_outros} onChange={set("escala_outros")} className="mt-2 w-full px-4 py-2.5 bg-sand rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-oak-dark/20" placeholder="Digite a escala" />
            </div>
          )}
          <div>
            <label className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">Horas compensadas</label>
            <input type="number" step="0.5" min="0" value={form.horas_compensadas} onChange={set("horas_compensadas")} className="mt-2 w-full px-4 py-2.5 bg-sand rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-oak-dark/20" />
          </div>
          <div>
            <label className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">Motivo da cobertura</label>
            <select value={form.motivo} onChange={set("motivo")} className="mt-2 w-full px-4 py-2.5 bg-sand rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-oak-dark/20">
              {MOTIVOS.map((m) => <option key={m}>{m}</option>)}
            </select>
          </div>
        </div>

        <div>
          <label className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">Observações</label>
          <textarea value={form.observacao} onChange={set("observacao")} rows={3} className="mt-2 w-full px-4 py-2.5 bg-sand rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-oak-dark/20" />
        </div>

        <div className="flex flex-col-reverse gap-3 pt-4 border-t border-oak-light sm:flex-row sm:justify-end">
          <button type="button" onClick={() => navigate({ to: "/ft" })} className="w-full sm:w-auto px-5 py-2.5 text-sm font-medium text-oak-dark hover:bg-oak-medium/20 rounded-xl">Cancelar</button>
          <button type="submit" disabled={loading} className="w-full sm:w-auto px-6 py-2.5 bg-oak-dark text-primary-foreground text-sm font-medium rounded-xl hover:opacity-90 disabled:opacity-50">
            {loading ? "Salvando..." : "Registrar Movimentação"}
          </button>
        </div>
      </form>
    </div>
  );
}
