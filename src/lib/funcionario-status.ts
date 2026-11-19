// Estados do funcionário e regras de tela da FT retroativa. Lógica pura, testável.
// O banco é quem decide (tg_ft_validar_funcionarios); isto só antecipa a mensagem para o usuário.

/** Colunas legíveis de funcionarios. CPF fica de fora: nenhum perfil lê a coluna; o Gestor usa funcionario_cpf(). */
export const COLUNAS_FUNCIONARIO =
  "id, nome, re, cargo, setor, empresa, turno, status, status_ativo, supervisor, usa_banco_horas, banco_horas, data_admissao, data_inativacao, inativado_por, created_at, updated_at";

export type StatusFuncionario = "ativo" | "ferias" | "inativo";

export const STATUS_LABEL: Record<StatusFuncionario, string> = { ativo: "Ativo", ferias: "Férias", inativo: "Inativo" };

export const STATUS_BADGE: Record<StatusFuncionario, string> = {
  ativo: "bg-emerald-50 text-emerald-700",
  ferias: "bg-amber-50 text-amber-700",
  inativo: "bg-stone-100 text-stone-600",
};

/** Usa `status`, nunca `status_ativo`: férias não é inativo. Valor desconhecido não é tratado como ativo. */
export const statusDe = (s: string | null | undefined): StatusFuncionario =>
  s === "ativo" || s === "ferias" ? s : "inativo";

/** "2026-11-05" -> "05/11/2026", sem passar por Date (evita deslocar o dia pelo fuso). */
export function formatarData(iso: string | null | undefined) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso ?? "");
  return m ? `${m[3]}/${m[2]}/${m[1]}` : "—";
}

export const JUSTIFICATIVA_MIN = 10;
export const JUSTIFICATIVA_MAX = 1000;

/** Mesma regra de texto_justificativa_valido no banco: espaços, pontuação e invisíveis não contam. */
export function justificativaValida(txt: string) {
  const t = txt.trim();
  return t.length <= JUSTIFICATIVA_MAX && (t.match(/[A-Za-z0-9]/g)?.length ?? 0) >= JUSTIFICATIVA_MIN;
}

export interface VinculoFt {
  nome: string;
  status: string;
  data_inativacao?: string | null;
}

/** Vínculos inativos da FT e, se houver, o motivo pelo qual a data do serviço impede a exceção. */
export function avaliarRetroativa<T extends VinculoFt>(vinculos: (T | undefined)[], dataFt: string) {
  const inativos = vinculos.filter((v): v is T => v?.status === "inativo");
  const impedido = inativos.find((v) => !v.data_inativacao || dataFt >= v.data_inativacao);
  return {
    inativos,
    bloqueio: impedido
      ? `A data do serviço deve ser anterior à inativação de ${impedido.nome} (${formatarData(impedido.data_inativacao)}).`
      : null,
  };
}

/** Tira o código técnico do início das mensagens de regra do banco (ex.: "FUNCIONARIO_INATIVO: ..."). */
export const mensagemRegra = (msg: string) => msg.replace(/^(FUNCIONARIO_INATIVO|RETROATIVA_[A-Z]+|REATIVACAO_MOTIVO|CADASTRO_INATIVO|EXCLUSAO_PROIBIDA|PERMISSAO(?:_FERIAS)?|ANULACAO_[A-Z]+|FT_[A-Z_]+|CONFERENCIA_[A-Z]+|CPF_[A-Z]+): /, "");
