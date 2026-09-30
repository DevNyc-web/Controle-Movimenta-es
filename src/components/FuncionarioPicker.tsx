import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Search, X } from "lucide-react";

interface Funcionario {
  id: string;
  nome: string;
  re: string;
}

interface Props {
  label: string;
  value: string;
  onChange: (id: string) => void;
  required?: boolean;
  excludeId?: string;
}

export function FuncionarioPicker({ label, value, onChange, required, excludeId }: Props) {
  const [list, setList] = useState<Funcionario[]>([]);
  const [q, setQ] = useState("");
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    supabase.from("funcionarios").select("id, nome, re").order("nome")
      .then(({ data }) => setList((data ?? []) as Funcionario[]));
  }, []);

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
                    onClick={() => { onChange(f.id); setOpen(false); setQ(""); }}
                    className="w-full text-left px-4 py-2.5 hover:bg-sand text-sm flex items-center justify-between"
                  >
                    <span className="font-medium">{f.nome}</span>
                    <span className="text-xs text-oak-dark/60">RE {f.re}</span>
                  </button>
                </li>
              ))}
            </ul>
          )}
          {open && filtered.length === 0 && (
            <div className="absolute z-20 mt-1 w-full bg-card border border-oak-light rounded-xl shadow-lg p-4 text-xs text-muted-foreground">
              Nenhum funcionário encontrado.
            </div>
          )}
        </div>
      )}
    </div>
  );
}
