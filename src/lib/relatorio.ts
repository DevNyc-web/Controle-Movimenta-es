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

/* ---- Limite mensal: sinalização (não bloqueia) ---------------------------------------------------------------
   Regra (mesma semântica do antigo bloqueio do banco): por funcionario_id + mês de data_ft, contam TODAS as FTs exceto
   CANCELADA (PENDENTE, APROVADA e NEGADA contam; pagamento_em_folha conta para a quantidade). Excedeu = mais de 4. */
export const LIMITE_MENSAL = 4;

export interface FtContagem { funcionario_id: string; data_ft: string; status: string }

/** "AAAA-MM" lido da string; data_ft é DATE, então nada de new Date() (evita erro de fuso). */
export const mesDe = (dataFt: string) => dataFt.slice(0, 7);
export const chaveMes = (funcionarioId: string, dataFt: string) => `${funcionarioId}|${mesDe(dataFt)}`;

/** Chaves (funcionario_id|AAAA-MM) com mais de LIMITE_MENSAL movimentações. Nunca usa o nome. */
export function mesesExcedidos(rows: FtContagem[]): Set<string> {
  const qtd = new Map<string, number>();
  for (const r of rows) {
    if (r.status === "CANCELADA") continue;
    const k = chaveMes(r.funcionario_id, r.data_ft);
    qtd.set(k, (qtd.get(k) ?? 0) + 1);
  }
  return new Set([...qtd].filter(([, n]) => n > LIMITE_MENSAL).map(([k]) => k));
}

/** Lê todas as páginas de uma consulta. Avança pelo que o servidor DEVOLVEU (não por tamanho fixo): se o PostgREST
 *  limitar a resposta abaixo de `tamanho` (max_rows), nenhuma linha é pulada. Para só numa página vazia. */
export async function lerTodas<T>(pagina: (from: number, to: number) => Promise<T[]>, tamanho = 1000): Promise<T[]> {
  const out: T[] = [];
  for (let from = 0; ; ) {
    const rows = await pagina(from, from + tamanho - 1);
    if (rows.length === 0) break;
    out.push(...rows);
    from += rows.length;
  }
  return out;
}

/** Meses INTEIROS tocados pelo período: 15/10..31/10 => 01/10..31/10; 15/09..10/10 => 01/09..31/10. */
export function mesesInteiros(start: string, end: string): { inicio: string; fim: string } {
  const [y, m] = [Number(end.slice(0, 4)), Number(end.slice(5, 7))];
  const ultimo = new Date(Date.UTC(y, m, 0)).getUTCDate(); // dia 0 do mês seguinte, em UTC: independe do fuso
  return { inicio: `${start.slice(0, 7)}-01`, fim: `${mesDe(end)}-${String(ultimo).padStart(2, "0")}` };
}

export const linhaExcedeu = (i: Pick<FtRow, "funcionario_id" | "data_ft">, exc: ReadonlySet<string>) => exc.has(chaveMes(i.funcionario_id, i.data_ft));
/** Funcionário aparece em vermelho no cabeçalho se QUALQUER mês do relatório excedeu. */
export const grupoExcedeu = (g: Grupo, exc: ReadonlySet<string>) => g.items.some((i) => linhaExcedeu(i, exc));

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
