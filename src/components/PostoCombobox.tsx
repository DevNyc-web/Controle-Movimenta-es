import { useEffect, useRef, useState } from "react";
import { Search, X, ChevronDown } from "lucide-react";
import { POSTOS_FALTA } from "@/lib/postos";

interface Props {
  label?: string;
  value: string;
  onChange: (value: string) => void;
  required?: boolean;
}

export function PostoCombobox({ label = "Posto onde ocorreu a falta", value, onChange, required }: Props) {
  const [q, setQ] = useState("");
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handler(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  const term = q.toLowerCase().trim();
  const filtered = POSTOS_FALTA.filter((p) => !term || p.toLowerCase().includes(term));

  return (
    <div ref={ref} className="relative">
      <label className="text-[10px] font-bold text-oak-dark/60 uppercase tracking-widest">{label}</label>
      {value ? (
        <div className="mt-2 flex items-center justify-between gap-2 px-4 py-2.5 bg-sand rounded-xl text-sm">
          <span className="font-medium leading-snug">{value}</span>
          <button
            type="button"
            onClick={() => {
              onChange("");
              setQ("");
              setOpen(true);
            }}
            className="shrink-0 p-1 hover:bg-oak-medium/30 rounded-md"
            aria-label="Limpar posto"
          >
            <X className="size-3.5" />
          </button>
        </div>
      ) : (
        <div className="mt-2 relative">
          <div className="flex items-center gap-2 px-4 py-2.5 bg-sand rounded-xl">
            <Search className="size-3.5 text-oak-dark/40 shrink-0" />
            <input
              required={required && !value}
              value={q}
              onChange={(e) => {
                setQ(e.target.value);
                setOpen(true);
              }}
              onFocus={() => setOpen(true)}
              placeholder="Digite para buscar o posto..."
              className="flex-1 bg-transparent text-sm focus:outline-none min-w-0"
            />
            <ChevronDown className="size-3.5 text-oak-dark/40 shrink-0" />
          </div>
          {open && (
            <ul className="absolute z-30 mt-1 w-full bg-card border border-oak-light rounded-xl shadow-lg max-h-72 overflow-y-auto">
              {filtered.length === 0 ? (
                <li className="px-4 py-3 text-xs text-muted-foreground">Nenhum posto encontrado.</li>
              ) : (
                filtered.map((p) => (
                  <li key={p}>
                    <button
                      type="button"
                      onClick={() => {
                        onChange(p);
                        setOpen(false);
                        setQ("");
                      }}
                      className="w-full text-left px-4 py-2.5 hover:bg-sand text-sm leading-snug"
                    >
                      {p}
                    </button>
                  </li>
                ))
              )}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}
