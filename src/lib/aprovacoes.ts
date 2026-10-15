import { lerTodas } from "./relatorio.ts";

/** FTs aguardando aprovação (PENDENTE), opcionalmente por período de data_ft (data do serviço — nunca created_at /
 *  data_lancamento). Datas "AAAA-MM-DD", inclusivas; vazio = sem limite. O filtro só ACRESCENTA condições à consulta
 *  do usuário logado: a RLS (janela do supervisor) continua decidindo o que é visível. Pagina para não truncar em 1000. */
export function carregarPendentes(client: any, inicio = "", fim = ""): Promise<any[]> {
  return lerTodas(async (from, to) => {
    let q = client
      .from("ft")
      .select("*, funcionario:funcionarios!ft_funcionario_id_fkey(nome, cargo, re)")
      .eq("status", "PENDENTE");
    if (inicio) q = q.gte("data_ft", inicio);
    if (fim) q = q.lte("data_ft", fim);
    const { data, error } = await q.order("data_lancamento").order("id").range(from, to); // ordem total p/ paginar
    if (error) throw error;
    return data ?? [];
  });
}

/** Filtro de data_ft das Aprovações persistido no navegador, isolado por usuário. Guarda só as datas. */
type Armazenamento = Pick<Storage, "getItem" | "setItem" | "removeItem">;
const chaveFiltro = (uid: string) => `aprovacoes:filtro-data:${uid}`;
const dataValida = (v: unknown): v is string =>
  typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v) && !Number.isNaN(Date.parse(v));

export function lerFiltroAprovacoes(uid: string, storage?: Armazenamento): { inicio: string; fim: string } {
  try {
    const salvo = JSON.parse((storage ?? globalThis.localStorage).getItem(chaveFiltro(uid)) ?? "null");
    return { inicio: dataValida(salvo?.inicio) ? salvo.inicio : "", fim: dataValida(salvo?.fim) ? salvo.fim : "" };
  } catch {
    return { inicio: "", fim: "" }; // corrompido ou storage indisponível = sem filtro
  }
}

/** Ambas vazias ("Limpar filtros") apagam o valor persistido. */
export function salvarFiltroAprovacoes(uid: string, inicio: string, fim: string, storage?: Armazenamento) {
  try {
    const s = storage ?? globalThis.localStorage;
    if (!inicio && !fim) s.removeItem(chaveFiltro(uid));
    else s.setItem(chaveFiltro(uid), JSON.stringify({ inicio, fim }));
  } catch {
    // storage cheio/bloqueado: filtro segue funcionando, só não persiste
  }
}
