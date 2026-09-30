// Lógica pura do relatório (sem React/Supabase) para ser testável.
export const LABEL_FOLHA = "PAGAMENTO EM FOLHA";

export interface FtRow {
  id: string;
  funcionario_id: string;
  data_ft: string;
  numero_ft?: string | null;
  horas_trabalhadas: number | string;
  valor_pago?: number | string | null;
  pagamento_em_folha?: boolean | null;
  status: string;
  funcionario?: { nome?: string; re?: string; cargo?: string } | null;
  [k: string]: unknown;
}

export interface Grupo<T extends FtRow = FtRow> {
  funcionarioId: string;
  nome: string;
  re: string;
  items: T[];
  horas: number;
  valor: number;
}

/** Valor a receber; FT em folha não entra em nenhum total. */
export const valorRecebido = (i: FtRow) => (i.pagamento_em_folha ? 0 : Number(i.valor_pago ?? 0));

const cmp = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);

/** Agrupa por funcionario_id (nunca por nome). Grupos por nome/id; itens por data/numero_ft. */
export function agruparPorFuncionario<T extends FtRow>(items: T[]): Grupo<T>[] {
  const map = new Map<string, Grupo<T>>();
  for (const i of items) {
    let g = map.get(i.funcionario_id);
    if (!g) {
      g = { funcionarioId: i.funcionario_id, nome: i.funcionario?.nome ?? "—", re: i.funcionario?.re ?? "—", items: [], horas: 0, valor: 0 };
      map.set(i.funcionario_id, g);
    }
    g.items.push(i);
    g.horas += Number(i.horas_trabalhadas);
    g.valor += valorRecebido(i);
  }
  const grupos = [...map.values()];
  grupos.forEach((g) => g.items.sort((a, b) => cmp(a.data_ft, b.data_ft) || cmp(a.numero_ft ?? a.id, b.numero_ft ?? b.id)));
  return grupos.sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR") || cmp(a.funcionarioId, b.funcionarioId));
}

/** Totais gerais; valor exclui FT em folha. */
export function totaisGerais(items: FtRow[]) {
  const t: Record<string, number> = { total: 0, horas: 0, valor: 0, PENDENTE: 0, APROVADA: 0, NEGADA: 0, CANCELADA: 0 };
  for (const i of items) {
    t.total++;
    t.horas += Number(i.horas_trabalhadas);
    t.valor += valorRecebido(i);
    t[i.status] = (t[i.status] ?? 0) + 1;
  }
  return t;
}
