import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/auth";
import { toast } from "sonner";
import { Plus, Pencil, Trash2, Search } from "lucide-react";


export const Route = createFileRoute("/_app/funcionarios/")({
  component: FuncionariosList,
});

function FuncionariosList() {
  const [items, setItems] = useState<any[]>([]);
  const [q, setQ] = useState("");
  const { isGestor } = useAuth();
  const navigate = useNavigate();

  useEffect(() => { load(); }, []);
  async function load() {
    const { data } = await supabase.from("funcionarios").select("*").order("nome");
    setItems(data ?? []);
  }

  const filtered = items.filter(
    (i) => i.nome.toLowerCase().includes(q.toLowerCase()) || (i.re ?? "").includes(q)
  );

  async function handleDelete(id: string) {
    if (!confirm("Excluir este funcionário?")) return;
    const { error } = await supabase.from("funcionarios").delete().eq("id", id);
    if (error) toast.error(error.message);
    else {
      toast.success("Funcionário excluído");
      load();
    }
  }

  return (
    <div className="space-y-8">
      <div className="flex items-end justify-between">
        <div>
          <h1 className="text-3xl font-light tracking-tight">Funcionários</h1>
          <p className="text-muted-foreground mt-1">{items.length} cadastrados.</p>
        </div>
        <div className="flex gap-2">
          {isGestor && (
            <Link to="/funcionarios/importar" className="inline-flex items-center gap-2 bg-secondary text-foreground px-5 py-2.5 rounded-xl text-sm font-medium hover:bg-accent">
              Importar XLSX
            </Link>
          )}
          <Link to="/funcionarios/novo" className="inline-flex items-center gap-2 bg-primary text-primary-foreground px-5 py-2.5 rounded-xl text-sm font-medium hover:opacity-90">
            <Plus className="size-4" /> Novo funcionário
          </Link>
        </div>
      </div>

      <div className="bg-card border border-border rounded-3xl overflow-hidden">
        <div className="px-8 py-5 border-b border-border flex items-center gap-3">
          <Search className="size-4 text-muted-foreground" />
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Buscar por nome ou RE..."
            className="flex-1 bg-transparent text-sm focus:outline-none"
          />
        </div>

        {filtered.length === 0 ? (
          <div className="p-12 text-center text-sm text-muted-foreground">Nenhum funcionário encontrado.</div>
        ) : (
          <table className="w-full text-left">
            <thead>
              <tr className="table-head-row">
                <Th>Nome</Th><Th>RE</Th><Th>Cargo</Th><Th>Supervisor</Th><Th>Turno</Th><Th>Banco horas</Th><Th>Status</Th><Th>Ações</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {filtered.map((f) => (
                <tr key={f.id} className="table-row-hover cursor-pointer" onClick={() => navigate({ to: "/funcionarios/$id", params: { id: f.id } })}>
                  <td className="px-8 py-5 text-sm font-medium">{f.nome}</td>
                  <td className="px-8 py-5 text-sm tabular-nums">{f.re}</td>
                  <td className="px-8 py-5 text-sm">{f.cargo}</td>
                  <td className="px-8 py-5 text-sm">{f.supervisor ?? "—"}</td>
                  <td className="px-8 py-5 text-sm">{f.turno}</td>
                  <td className="px-8 py-5 text-sm">{f.usa_banco_horas ? "Sim" : "Não"}</td>
                  <td className="px-8 py-5">
                    <span className={`px-2.5 py-1 rounded-full text-[10px] font-semibold uppercase ${f.status_ativo ? "bg-emerald-50 text-emerald-700" : "bg-stone-100 text-stone-600"}`}>
                      {f.status_ativo ? "Ativo" : "Inativo"}
                    </span>
                  </td>
                  <td className="px-8 py-5" onClick={(e) => e.stopPropagation()}>
                    <div className="flex gap-2">
                      <Link to="/funcionarios/$id" params={{ id: f.id }} className="p-2 hover:bg-accent rounded-lg" title="Editar">
                        <Pencil className="size-3.5 text-primary" />
                      </Link>
                      {isGestor && (
                        <button onClick={() => handleDelete(f.id)} className="p-2 hover:bg-rose-100 rounded-lg" title="Excluir">
                          <Trash2 className="size-3.5 text-rose-600" />
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

function Th({ children }: { children: React.ReactNode }) {
  return <th className="px-8 py-4 text-[10px] font-bold text-muted-foreground uppercase tracking-widest">{children}</th>;
}
