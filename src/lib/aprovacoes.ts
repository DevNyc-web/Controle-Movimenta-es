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
