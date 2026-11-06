// Comparação da folha com o cadastro. Lógica pura: não grava nada e nunca propõe inativação.
// CPF válido é a única chave de vínculo automático; nome só confirma. Toda ação aqui é uma proposta para o Gestor decidir.
import { cpfDaCelula, mascararCpf, nomeNormalizado, type LinhaFolha } from "./importacao-funcionarios.ts";

export type TipoItem =
  | "CORRESPONDENTE" | "DIVERGENCIA_NOME" | "DIVERGENCIA_CPF" | "NOVO" | "INATIVO" | "AUSENTE" | "DUPLICADO" | "PENDENCIA";

/** Lista fechada: inativar não existe aqui, de propósito. */
export type Acao = "ATUALIZAR_NOME" | "PREENCHER_CPF" | "CORRIGIR_CPF" | "CADASTRAR" | "REATIVAR";

export const TIPO_LABEL: Record<TipoItem, string> = {
  CORRESPONDENTE: "Correspondência",
  DIVERGENCIA_NOME: "Divergência de nome",
  DIVERGENCIA_CPF: "Divergência de CPF",
  NOVO: "Novo",
  INATIVO: "Inativo encontrado",
  AUSENTE: "Ausente da folha",
  DUPLICADO: "Duplicidade",
  PENDENCIA: "Pendência",
};

export const ACAO_LABEL: Record<Acao, string> = {
  ATUALIZAR_NOME: "Atualizar nome",
  PREENCHER_CPF: "Preencher CPF",
  CORRIGIR_CPF: "Corrigir CPF",
  CADASTRAR: "Cadastrar novo funcionário",
  REATIVAR: "Reativar funcionário",
};

export interface FuncionarioBase {
  id: string;
  nome: string;
  cpf: string | null;
  re: string;
  cargo: string;
  empresa: string | null;
  status: string;
  data_admissao: string | null;
}

export interface DadosFolha { nome: string; cpf: string; re: string; cargo: string; empresa: string; admissao: string | null }

export interface ItemConferencia {
  tipo: TipoItem;
  funcionario_id: string | null;
  folha: DadosFolha | null;
  atual: Pick<FuncionarioBase, "nome" | "cpf" | "re" | "cargo" | "empresa" | "status" | "data_admissao"> | null;
  /** Ação sugerida; null = só revisão. */
  acao: Acao | null;
  /** Ações que o Gestor pode aprovar neste item. Vazia = nada será aplicado. */
  opcoes: Acao[];
  motivo: string;
  origens: string[];
}

/** Linha de conferencia_itens como chega à tela: sempre mascarada. */
export interface ItemTela extends Pick<ItemConferencia, "tipo" | "funcionario_id" | "folha" | "atual" | "motivo" | "origens" | "opcoes"> {
  id: string;
  ordem: number;
  decisao: string;
  acao: Acao | null;
  justificativa: string | null;
  resultado: string | null;
  resultado_detalhe: string | null;
}

export interface ResultadoConferencia { aplicados: number; conflitos: number }

export interface ConferenciaTela {
  id: string; status: string; arquivo_nome: string; criada_em: string;
  resumo: ResumoConferencia; resultado: ResultadoConferencia | null; motivo_descarte: string | null;
}

export interface ResumoConferencia {
  total_folha: number; correspondencias: number; novos: number; ausentes: number;
  divergencias: number; inativos: number; duplicidades: number; pendencias: number;
}

const LIGACAO = new Set(["DE", "DA", "DO", "DAS", "DOS", "E"]);
const partes = (n: string) => nomeNormalizado(n).split(" ").filter((p) => p && !LIGACAO.has(p));

/** Mesma pessoa provável: abreviações passam; nomes sem relação não. Serve para sinalizar dúvida de identidade. */
export function nomesParecidos(a: string, b: string) {
  const x = partes(a), y = partes(b);
  if (!x.length || !y.length || x[0] !== y[0]) return false;
  const casa = (p: string, lista: string[]) => lista.some((q) => q === p || (p.length === 1 && q.startsWith(p)) || (q.length === 1 && p.startsWith(q)));
  const [menor, maior] = x.length <= y.length ? [x, y] : [y, x];
  const comuns = menor.filter((p) => casa(p, maior)).length;
  return comuns >= Math.min(2, menor.length);
}

const dadosFolha = (l: LinhaFolha): DadosFolha => ({ nome: l.nome, cpf: l.cpf, re: l.re, cargo: l.cargo, empresa: l.empresa, admissao: l.admissao });
const atualDe = ({ nome, cpf, re, cargo, empresa, status, data_admissao }: FuncionarioBase): ItemConferencia["atual"] => ({ nome, cpf, re, cargo, empresa, status, data_admissao });

export function compararFolha(linhas: LinhaFolha[], funcionarios: FuncionarioBase[]) {
  // Só dígitos: cadastro antigo com pontuação ou sem zero à esquerda não pode virar falso "novo".
  const porCpf = new Map(funcionarios.filter((f) => f.cpf).map((f) => [cpfDaCelula(f.cpf), f]));
  const porNome = new Map<string, FuncionarioBase[]>();
  for (const f of funcionarios) {
    const k = nomeNormalizado(f.nome);
    porNome.set(k, [...(porNome.get(k) ?? []), f]);
  }
  const itens: ItemConferencia[] = [];
  const vistos = new Set<string>();
  const novo = (i: Omit<ItemConferencia, "opcoes"> & { opcoes?: Acao[] }) => itens.push({ opcoes: i.acao ? [i.acao] : [], ...i });

  const grupos = new Map<string, LinhaFolha[]>();
  for (const l of linhas) if (l.cpfValido) grupos.set(l.cpf, [...(grupos.get(l.cpf) ?? []), l]);

  for (const [cpf, ls] of grupos) {
    const f = porCpf.get(cpf);
    if (f) vistos.add(f.id);
    if (ls.length > 1) {
      const nomes = new Set(ls.map((l) => nomeNormalizado(l.nome)));
      novo({
        tipo: "DUPLICADO", funcionario_id: f?.id ?? null, folha: dadosFolha(ls[0]), atual: f ? atualDe(f) : null, acao: null,
        motivo: nomes.size > 1 ? "Mesmo CPF em linhas com nomes diferentes" : `Mesmo CPF em ${ls.length} linhas da folha`,
        origens: ls.map((l) => l.origem),
      });
      continue;
    }
    const l = ls[0];
    const base = { folha: dadosFolha(l), origens: [l.origem] };
    if (f) {
      const mesmoNome = nomeNormalizado(f.nome) === nomeNormalizado(l.nome);
      // Identidade primeiro: com nome sem relação não há ação, nem para funcionário inativo.
      if (!mesmoNome && !nomesParecidos(f.nome, l.nome)) {
        novo({ ...base, tipo: "PENDENCIA", funcionario_id: f.id, atual: atualDe(f), acao: null, motivo: "Mesmo CPF com nome sem relação: dúvida de identidade" });
      } else if (f.status === "inativo") {
        novo({ ...base, tipo: "INATIVO", funcionario_id: f.id, atual: atualDe(f), acao: "REATIVAR", motivo: "Funcionário inativo presente na folha" });
      } else if (mesmoNome) {
        novo({ ...base, tipo: "CORRESPONDENTE", funcionario_id: f.id, atual: atualDe(f), acao: null, motivo: f.status === "ferias" ? "Confere; segue de férias" : "Confere" });
      } else {
        novo({ ...base, tipo: "DIVERGENCIA_NOME", funcionario_id: f.id, atual: atualDe(f), acao: "ATUALIZAR_NOME", motivo: "Mesmo CPF com nome diferente" });
      }
      continue;
    }
    const candidatos = porNome.get(nomeNormalizado(l.nome)) ?? [];
    if (candidatos.length === 0) {
      novo({ ...base, tipo: "NOVO", funcionario_id: null, atual: null, acao: "CADASTRAR", motivo: "CPF sem cadastro no sistema" });
    } else if (candidatos.length > 1) {
      novo({ ...base, tipo: "PENDENCIA", funcionario_id: null, atual: null, acao: null, opcoes: ["CADASTRAR"], motivo: `${candidatos.length} cadastros com este nome e outro CPF` });
    } else {
      const c = candidatos[0];
      if (!c.cpf) {
        vistos.add(c.id);
        novo({ ...base, tipo: "PENDENCIA", funcionario_id: c.id, atual: atualDe(c), acao: "PREENCHER_CPF", motivo: "Cadastro com o mesmo nome e sem CPF: confirme se é a mesma pessoa" });
      } else if ((l.re && l.re === c.re) || (l.admissao && l.admissao === c.data_admissao)) {
        vistos.add(c.id);
        novo({ ...base, tipo: "DIVERGENCIA_CPF", funcionario_id: c.id, atual: atualDe(c), acao: "CORRIGIR_CPF", motivo: "Mesmo nome e RE ou admissão, com CPF diferente" });
      } else {
        novo({ ...base, tipo: "PENDENCIA", funcionario_id: c.id, atual: atualDe(c), acao: null, opcoes: ["CADASTRAR"], motivo: "Mesmo nome com outro CPF: possível homônimo" });
      }
    }
  }

  for (const l of linhas) {
    if (l.cpfValido) continue;
    const candidatos = porNome.get(nomeNormalizado(l.nome)) ?? [];
    const c = candidatos.length === 1 ? candidatos[0] : null;
    // Evita marcar como ausente quem aparece na folha com CPF ruim. Só evita a sinalização; não vincula nada.
    if (c) vistos.add(c.id);
    novo({
      tipo: "PENDENCIA", funcionario_id: c?.id ?? null, folha: dadosFolha(l), atual: c ? atualDe(c) : null, acao: null, origens: [l.origem],
      motivo: `${l.cpf ? "CPF inválido" : "CPF ausente"}${c ? "; cadastro com o mesmo nome sugerido, sem vínculo" : ""}`,
    });
  }

  // Duas linhas apontando para o mesmo cadastro: não dá para saber qual é a pessoa. Nada que altere esse cadastro é oferecido.
  const porFuncionario = new Map<string, number>();
  for (const i of itens) if (i.funcionario_id) porFuncionario.set(i.funcionario_id, (porFuncionario.get(i.funcionario_id) ?? 0) + 1);
  for (const i of itens) {
    if (!i.funcionario_id || (porFuncionario.get(i.funcionario_id) as number) < 2 || !i.opcoes.some((a) => a !== "CADASTRAR")) continue;
    i.tipo = "PENDENCIA";
    i.acao = null;
    i.opcoes = i.opcoes.filter((a) => a === "CADASTRAR");
    i.motivo = "Mais de uma linha da folha aponta para este cadastro: dúvida de identidade";
  }

  for (const f of funcionarios) {
    if (f.status === "inativo" || vistos.has(f.id)) continue;
    novo({ tipo: "AUSENTE", funcionario_id: f.id, folha: null, atual: atualDe(f), acao: null, origens: [], motivo: "Não encontrado na folha; a folha isolada não comprova desligamento" });
  }

  const conta = (...t: TipoItem[]) => itens.filter((i) => t.includes(i.tipo)).length;
  const resumo: ResumoConferencia = {
    total_folha: linhas.length, correspondencias: conta("CORRESPONDENTE"), novos: conta("NOVO"), ausentes: conta("AUSENTE"),
    divergencias: conta("DIVERGENCIA_NOME", "DIVERGENCIA_CPF"), inativos: conta("INATIVO"), duplicidades: conta("DUPLICADO"), pendencias: conta("PENDENCIA"),
  };
  return { itens, resumo };
}

/** O que o navegador recebe: nunca o CPF completo. */
export const paraExibir = <T extends Pick<ItemConferencia, "folha" | "atual">>(i: T): T => ({
  ...i,
  folha: i.folha && { ...i.folha, cpf: mascararCpf(i.folha.cpf) },
  atual: i.atual && { ...i.atual, cpf: i.atual.cpf && mascararCpf(i.atual.cpf) },
});

/** O que guardar: CPF completo só onde uma ação ainda precisa dele; o resto já nasce mascarado. */
export function paraGravar(i: ItemConferencia): ItemConferencia {
  const precisaFolha = i.opcoes.length > 0;
  const mantemAtual = i.tipo === "DIVERGENCIA_CPF";
  return {
    ...i,
    folha: i.folha && { ...i.folha, cpf: precisaFolha ? i.folha.cpf : mascararCpf(i.folha.cpf) },
    atual: i.atual && { ...i.atual, cpf: mantemAtual ? i.atual.cpf : i.atual.cpf && mascararCpf(i.atual.cpf) },
  };
}
