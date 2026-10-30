export type SolicitacaoCancelamento = {
  id: string;
  solicitado_por: string;
  status: string;
  created_at: string;
};

/** Qual solicitação de cancelamento exibir no detalhe da FT: a PENDENTE (no máximo uma, garantido por
 *  uq_ft_cancelamento_pendente); sem pendente, a mais recente. null = FT sem solicitações. */
export function escolherSolicitacao<T extends SolicitacaoCancelamento>(sols: T[]): T | null {
  const pendente = sols.find((s) => s.status === "PENDENTE");
  if (pendente) return pendente;
  return (
    [...sols].sort(
      (a, b) => b.created_at.localeCompare(a.created_at) || b.id.localeCompare(a.id),
    )[0] ?? null
  );
}

const SITUACAO: Record<string, string> = {
  PENDENTE: "pendente",
  APROVADO: "aprovada",
  REJEITADO: "rejeitada",
};

/** Texto do campo "Cancelamento solicitado por": nome de quem pediu (solicitado_por), situação e data do pedido. */
export function descreverSolicitacao(s: {
  nome: string | null;
  status: string;
  data: string;
  total: number;
}): string {
  const base = `${s.nome ?? "Não identificado"} — ${SITUACAO[s.status] ?? s.status.toLowerCase()}, pedido em ${s.data}`;
  return s.total > 1
    ? `${base} (${s.status === "PENDENTE" ? "atual" : "mais recente"} de ${s.total} solicitações)`
    : base;
}
