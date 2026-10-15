// Correção manual de valor_pago / pagamento_em_folha nos detalhes da FT. Tudo em centavos inteiros (sem float).
import { LABEL_FOLHA } from "./relatorio.ts";

/** Teto contra erro de digitação (valores por cargo hoje ficam entre R$ 130 e R$ 200). */
export const VALOR_MAXIMO_CENTAVOS = 9_999_999; // R$ 99.999,99

/** "250", "250,5", "1.250,00", "R$ 250,50" e "250.50" -> centavos. Inválido (negativo, >2 casas, texto) -> null. */
export function parseValorCentavos(txt: string): number | null {
  const s = txt.trim().replace(/^R\$\s*/i, "");
  const m = /^(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?$/.exec(s) ?? /^(\d+)\.(\d{1,2})$/.exec(s);
  if (!m) return null;
  const c = Number(m[1].replace(/\./g, "")) * 100 + Number((m[2] ?? "").padEnd(2, "0"));
  return Number.isSafeInteger(c) && c <= VALOR_MAXIMO_CENTAVOS ? c : null;
}

export const centavosDe = (v: number | string | null | undefined) => Math.round(Number(v ?? 0) * 100);

export const formatarCentavos = (c: number) =>
  `${Math.trunc(c / 100).toLocaleString("pt-BR")},${String(c % 100).padStart(2, "0")}`;

/** Exatamente o que o relatório mostra na coluna Valor. */
export const valorNoRelatorio = (ft: { valor_pago?: number | string | null; pagamento_em_folha?: boolean | null }) =>
  ft.pagamento_em_folha ? LABEL_FOLHA : `R$ ${Number(ft.valor_pago ?? 0).toFixed(2)}`;

type Atual = { valor_pago?: number | string | null; pagamento_em_folha?: boolean | null };

/** Só os campos que mudaram. valor_pago vai como número com no máximo 2 casas (centavos / 100 é exato em JSON). */
export function montarCorrecao(atual: Atual, centavos: number, folha: boolean) {
  const patch: { valor_pago?: number; pagamento_em_folha?: boolean } = {};
  if (centavos !== centavosDe(atual.valor_pago)) patch.valor_pago = centavos / 100;
  if (folha !== !!atual.pagamento_em_folha) patch.pagamento_em_folha = folha;
  return patch;
}

/** Texto do histórico da FT: "Valor: R$ 200,00 → R$ 250,00 · Pagamento em folha: Não → Sim". */
export function descreverCorrecao(atual: Atual, patch: ReturnType<typeof montarCorrecao>) {
  const partes: string[] = [];
  if (patch.valor_pago !== undefined)
    partes.push(`Valor: R$ ${formatarCentavos(centavosDe(atual.valor_pago))} → R$ ${formatarCentavos(centavosDe(patch.valor_pago))}`);
  if (patch.pagamento_em_folha !== undefined)
    partes.push(`Pagamento em folha: ${atual.pagamento_em_folha ? "Sim" : "Não"} → ${patch.pagamento_em_folha ? "Sim" : "Não"}`);
  return partes.join(" · ");
}
