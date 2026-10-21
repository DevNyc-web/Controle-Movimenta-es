// Empresas do grupo, com o nome exatamente como vem nas planilhas de cadastro (Relação Cadastral / consolidado).
export const EMPRESAS = [
  "M C ALPHA SEGURANCA ELETRONICA LTDA ME",
  "M C SERVICOS GERAIS LTDA",
  "MC FACILIT SERVICOS E COMERCIO SOCIEDADE",
  "MC REMOTA LTDA",
  "MC SEGURANCA E VIGILANCIA SS LTDA",
  "MC SERVICOS E PORTARIA EIRELI",
  "MC SERVICOS PATRIMONIAIS EIRELI",
  "MC SOLUCOES E SERVICOS LTDA",
] as const;

const chave = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().replace(/[^A-Z0-9]/g, "");
const PORCHAVE = new Map(EMPRESAS.map((e) => [chave(e), e]));

/** Nome canônico da empresa ou null quando não for uma empresa conhecida (ex.: nome da aba, "Nome", célula vazia).
 *  Ignora acentos, caixa, espaços e pontuação ("MC SERVICOS PATRIMONIAIS EIRELI " = "MC SERVICOS PATRIMONIAIS EIRELI"). */
export function normalizarEmpresa(raw: unknown): string | null {
  if (raw == null) return null;
  return PORCHAVE.get(chave(String(raw))) ?? null;
}
