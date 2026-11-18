// Auditoria paginada no servidor (migration 20261118120000, função auditoria_pagina).
// Cursor = (created_at, id) do último registro recebido. created_at fica como TEXTO do jeito que a API devolve: convertê-lo
// para Date perderia os microssegundos e a página seguinte repetiria ou pularia registros com o mesmo milissegundo.

export const TAMANHO_PAGINA = 100;
export const LOTE_CSV = 500; // sempre abaixo das 1000 linhas por resposta da API
export const LIMITE_CSV = 20000;

export type FiltrosAuditoria = { de: string; ate: string; userId: string; role: string; action: string; entityType: string };
export const FILTROS_VAZIOS: FiltrosAuditoria = { de: "", ate: "", userId: "", role: "", action: "", entityType: "" };
export type Cursor = { em: string; id: string } | null;
type ComCursor = { id: string; created_at: string };

const valor = (s: string) => (s.trim() ? s.trim() : null);

/** Argumentos de auditoria_pagina: filtros vazios viram null (sem filtro). */
export function paramsPagina(f: FiltrosAuditoria, cursor: Cursor, tamanho: number) {
  return {
    _de: valor(f.de), _ate: valor(f.ate), _user_id: valor(f.userId), _role: valor(f.role), _action: valor(f.action),
    _entity_type: valor(f.entityType), _antes_em: cursor?.em ?? null, _antes_id: cursor?.id ?? null, _tamanho: tamanho,
  };
}

/** Período inválido (início depois do fim) não vai ao servidor. Datas no formato do <input type="date"> (AAAA-MM-DD). */
export function periodoInvalido(f: FiltrosAuditoria) {
  return !!f.de && !!f.ate && f.de > f.ate;
}

/** Cursor da próxima página, ou null quando a página veio incompleta (fim do histórico para o filtro). */
export function proximoCursor(pagina: ComCursor[], tamanho: number): Cursor {
  if (pagina.length < tamanho) return null;
  const u = pagina[pagina.length - 1];
  return { em: u.created_at, id: u.id };
}

/** Acrescenta a página nova sem repetir registros (defesa extra; o cursor já não repete). */
export function juntarPaginas<T extends { id: string }>(atual: T[], nova: T[]): T[] {
  const vistos = new Set(atual.map((l) => l.id));
  return [...atual, ...nova.filter((l) => !vistos.has(l.id))];
}

export type ResultadoColeta<T> = { excedeu: false; linhas: T[] } | { excedeu: true; lidas: number };

/**
 * Busca TODAS as páginas de um filtro (exportação). Se passar do limite, NÃO devolve linhas: quem chama avisa e não gera arquivo
 * (nunca um CSV silenciosamente incompleto). `buscar` recebe o cursor e devolve até `lote` registros.
 */
export async function coletarTodas<T extends ComCursor>(
  buscar: (cursor: Cursor) => Promise<T[]>,
  { lote = LOTE_CSV, limite = LIMITE_CSV, progresso }: { lote?: number; limite?: number; progresso?: (n: number) => void } = {},
): Promise<ResultadoColeta<T>> {
  let linhas: T[] = [];
  let cursor: Cursor = null;
  for (;;) {
    const pagina = await buscar(cursor);
    linhas = juntarPaginas(linhas, pagina);
    if (linhas.length > limite) return { excedeu: true, lidas: linhas.length };
    progresso?.(linhas.length);
    cursor = proximoCursor(pagina, lote);
    if (!cursor) return { excedeu: false, linhas };
  }
}

/** Pesquisa de texto LOCAL: só sobre os campos já mascarados que estão na tela. */
export function contemTexto(campos: (string | null | undefined)[], termo: string) {
  const t = termo.trim().toLowerCase();
  if (!t) return true;
  return campos.some((c) => (c ?? "").toLowerCase().includes(t));
}
