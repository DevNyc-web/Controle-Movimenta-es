import { celulaTexto, type Campo } from "@/lib/importacao-funcionarios";
import { leituraDa, mapeada, type Aba, type CampoMapa } from "@/lib/mapa-aba";

const inp = "w-full px-3 py-2 bg-sand rounded-xl text-sm border-none focus:outline-none focus:ring-2 focus:ring-oak-dark/20";

/** Mapeamento de uma aba. Fechado quando a detecção é confiável, mas sempre pode ser aberto e corrigido. Só os campos listados são lidos. */
export function MapaAba({ aba, campos, alterar }: { aba: Aba; campos: CampoMapa[]; alterar: (m: Partial<Aba>) => void }) {
  const problema = aba.usar && !mapeada(aba);
  const rotulos = (aba.linha >= 0 ? aba.matriz[aba.linha] ?? [] : []).map((c) => celulaTexto(c));
  const opcoes = rotulos.map((r, i) => ({ i, r })).filter((o) => o.r);
  const definir = (campo: Campo, v: string) => {
    const colunas = { ...aba.colunas };
    if (v === "") delete colunas[campo];
    else colunas[campo] = Number(v);
    alterar({ colunas });
  };
  return (
    <details open={aba.duvida} className="border border-oak-light rounded-2xl p-4">
      <summary className="cursor-pointer text-sm font-medium">
        {aba.nome} {aba.oculta && <span className="text-amber-700 text-xs">· aba oculta no Excel</span>} {problema ? <span className="text-amber-700 text-xs">· informe as colunas de CPF e nome</span> : <span className="text-oak-dark/60 text-xs">· {aba.usar ? `${leituraDa(aba).linhas.length} linha(s)` : "ignorada"}</span>}
      </summary>
      <div className="mt-4 space-y-4">
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={aba.usar} onChange={(e) => alterar({ usar: e.target.checked })} /> {aba.oculta ? "Usar esta aba oculta (não usada por padrão)" : "Usar esta aba"}
        </label>
        {aba.usar && (
          <div className="grid gap-3 sm:grid-cols-2 md:grid-cols-4">
            <label className="text-xs">
              Linha do cabeçalho
              <input type="number" min={1} value={aba.linha >= 0 ? aba.linha + 1 : ""} onChange={(e) => alterar({ linha: Number(e.target.value) - 1, colunas: {} })} className={`${inp} mt-1`} />
            </label>
            {campos.map(({ campo, label, obrigatorio }) => (
              <label key={campo} className="text-xs">
                {label}{obrigatorio ? " *" : ""}
                <select value={aba.colunas[campo] ?? ""} onChange={(e) => definir(campo, e.target.value)} className={`${inp} mt-1`} aria-label={`Coluna de ${label}`}>
                  <option value="">{obrigatorio ? "Selecione" : "Não usar"}</option>
                  {opcoes.map((o) => <option key={o.i} value={o.i}>{o.r}</option>)}
                </select>
              </label>
            ))}
          </div>
        )}
      </div>
    </details>
  );
}
