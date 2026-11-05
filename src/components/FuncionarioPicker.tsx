import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Search, X } from "lucide-react";
import { formatarData, STATUS_LABEL, statusDe } from "@/lib/funcionario-status";

export interface FuncionarioOpcao {
  id: string;
  nome: string;
  re: string;
  empresa: string | null;
  status: string;
  data_inativacao: string | null;
}

interface Props {
  label: string;
  value: string;
  onChange: (id: string, funcionario?: FuncionarioOpcao) => void;
  required?: boolean;
  excludeId?: string;
  /** Só para o lançamento retroativo do Gestor. O padrão não busca inativos. */
  incluirInativos?: boolean;
}

function Situacao({ f }: { f: FuncionarioOpcao }) {
  const status = statusDe(f.status);
  if (status === "ativo") return null;
  return (
    <span className="ml-2 text-[10px] font-semibold uppercase text-amber-700">
      {status === "inativo" ? `Inativo desde ${formatarData(f.data_inativacao)}` : STATUS_LABEL[status]}
    </span>
  );
}

export function FuncionarioPicker({ label, value, onChange, required, excludeId, incluirInativos = false }: Props) {
  const [list, setList] = useState<FuncionarioOpcao[]>([]);
  const [erro, setErro] = useState(false);
  const [q, setQ] = useState("");
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let query = supabase.from("funcionarios").select("id, nome, re, empresa, status, data_inativacao").order("nome");
    if (!incluirInativos) query = query.neq("status", "inativo");
    let vivo = true; // ao alternar incluirInativos, resposta antiga não sobrescreve a nova
    query.then(({ data, error }) => {
      if (!vivo) return;
      setErro(!!error);
      setList((data ?? []) as FuncionarioOpcao[]);
    });
    return () => { vivo = false; };
  }, [incluirInativos]);

  useEffect(() => {
    function handler(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  const selected = list.find((f) => f.id === value);
  const term = q.toLowerCase().trim();
  const filtered = list
    .filter((f) => f.id !== excludeId)
    .filter((f) => !term || f.nome.toLowerCase().includes(term) || f.re.toLowerCase().includes(term))
    .slice(0, 50);

  return (
    <div ref={ref} className="relative">
      <label className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">{label}</label>
      {selected ? (
        <div className="mt-2 flex items-center justify-between px-4 py-2.5 bg-sand rounded-xl text-sm">
          <div>
            <span className="font-medium">{selected.nome}</span>
            <span className="text-oak-dark/60 ml-2">RE {selected.re}</span>
            {selected.empresa && <span className="text-oak-dark/60 ml-2">• {selected.empresa}</span>}
            <Situacao f={selected} />
          </div>
          <button type="button" onClick={() => { onChange(""); setQ(""); setOpen(true); }} className="p-1 hover:bg-oak-medium/30 rounded-md">
            <X className="size-3.5" />
          </button>
        </div>
      ) : (
        <div className="mt-2 relative">
          <div className="flex items-center gap-2 px-4 py-2.5 bg-sand rounded-xl">
            <Search className="size-3.5 text-oak-dark/40" />
            <input
              required={required && !value}
              value={q}
              onChange={(e) => { setQ(e.target.value); setOpen(true); }}
              onFocus={() => setOpen(true)}
              placeholder="Buscar por nome ou RE..."
              className="flex-1 bg-transparent text-sm focus:outline-none"
            />
          </div>
          {open && filtered.length > 0 && (
            <ul className="absolute z-20 mt-1 w-full bg-card border border-oak-light rounded-xl shadow-lg max-h-64 overflow-y-auto">
              {filtered.map((f) => (
                <li key={f.id}>
                  <button
                    type="button"
                    onClick={() => { onChange(f.id, f); setOpen(false); setQ(""); }}
                    className="w-full text-left px-4 py-2.5 hover:bg-sand text-sm flex items-center justify-between"
                  >
                    <span className="font-medium">{f.nome}<Situacao f={f} /></span>
                    <span className="text-xs text-oak-dark/60 text-right">RE {f.re}{f.empresa && <span className="block text-[10px]">{f.empresa}</span>}</span>
                  </button>
                </li>
              ))}
            </ul>
          )}
          {erro && (
            <p role="alert" className="mt-2 text-xs font-medium text-rose-700">
              Não foi possível carregar os funcionários. Recarregue a página ou avise o suporte.
            </p>
          )}
          {open && !erro && filtered.length === 0 && (
            <div className="absolute z-20 mt-1 w-full bg-card border border-oak-light rounded-xl shadow-lg p-4 text-xs text-muted-foreground">
              Nenhum funcionário encontrado.
            </div>
          )}
        </div>
      )}
    </div>
  );
}
