import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { compararFolha, nomesParecidos, paraExibir, paraGravar, type FuncionarioBase } from "../src/lib/conferencia.ts";
import type { LinhaFolha } from "../src/lib/importacao-funcionarios.ts";

const A = "11144477735", B = "52998224725", C = "39053344705", D = "71428793860";
const linha = (nome: string, cpf: string, extra: Partial<LinhaFolha> = {}): LinhaFolha => ({
  origem: "Folha:2", nome, cpf, cpfValido: /^\d{11}$/.test(cpf) && cpf !== "11111111111", re: "", cargo: "", empresa: "", admissao: null, ...extra,
});
const func = (id: string, nome: string, cpf: string | null, extra: Partial<FuncionarioBase> = {}): FuncionarioBase => ({
  id, nome, cpf, re: `R-${id}`, cargo: "Porteiro", empresa: null, status: "ativo", data_admissao: null, ...extra,
});
const um = (l: LinhaFolha[], f: FuncionarioBase[]) => compararFolha(l, f).itens[0];

test("nomes parecidos: abreviação sim, pessoa diferente não", () => {
  assert.equal(nomesParecidos("MARIA DA SILVA SOUZA", "Maria S. Souza"), true);
  assert.equal(nomesParecidos("JOAO PEREIRA", "JOÃO PEREIRA NETO"), true);
  assert.equal(nomesParecidos("MARIA SILVA", "CARLOS SILVA"), false);
  assert.equal(nomesParecidos("MARIA SILVA", "MARIA COSTA"), false);
});

test("1 CPF e nome iguais: correspondência, ignorando acento e caixa", () => {
  const i = um([linha("José da Silva", A)], [func("1", "JOSE DA SILVA", A)]);
  assert.equal(i.tipo, "CORRESPONDENTE");
  assert.deepEqual(i.opcoes, []);
});

test("2 CPF igual e nome parecido: propõe atualizar nome", () => {
  const i = um([linha("JOSE DA SILVA NETO", A)], [func("1", "JOSE DA SILVA", A)]);
  assert.equal(i.tipo, "DIVERGENCIA_NOME");
  assert.equal(i.acao, "ATUALIZAR_NOME");
});

test("2b CPF igual e nome sem relação: dúvida de identidade, sem ação", () => {
  const i = um([linha("CARLOS PEREIRA", A)], [func("1", "ANA SOUZA", A)]);
  assert.equal(i.tipo, "PENDENCIA");
  assert.deepEqual(i.opcoes, []);
  assert.match(i.motivo, /identidade/);
});

test("3 CPF novo, mesmo nome e mesmo RE: divergência de CPF", () => {
  const i = um([linha("ANA SOUZA", B, { re: "R-1" })], [func("1", "ANA SOUZA", A)]);
  assert.equal(i.tipo, "DIVERGENCIA_CPF");
  assert.equal(i.acao, "CORRIGIR_CPF");
  assert.equal(i.funcionario_id, "1");
});

test("3b CPF novo, mesmo nome e nada que confirme: homônimo, nunca vincula", () => {
  const i = um([linha("ANA SOUZA", B)], [func("1", "ANA SOUZA", A)]);
  assert.equal(i.tipo, "PENDENCIA");
  assert.equal(i.acao, null);
  assert.deepEqual(i.opcoes, ["CADASTRAR"]);
});

test("4 cadastro sem CPF e mesmo nome: pendência para preencher", () => {
  const i = um([linha("ANA SOUZA", B)], [func("1", "ANA SOUZA", null)]);
  assert.equal(i.tipo, "PENDENCIA");
  assert.equal(i.acao, "PREENCHER_CPF");
});

test("5 CPF e nome desconhecidos: novo", () => {
  const i = um([linha("NOVA PESSOA", C)], []);
  assert.equal(i.tipo, "NOVO");
  assert.equal(i.acao, "CADASTRAR");
});

test("6 CPF ausente ou inválido nunca vincula, mesmo com nome único", () => {
  for (const cpf of ["", "123", "11111111111"]) {
    const { itens } = compararFolha([linha("ANA SOUZA", cpf)], [func("1", "ANA SOUZA", A)]);
    assert.equal(itens.length, 1, "não pode virar ausente também");
    assert.equal(itens[0].tipo, "PENDENCIA");
    assert.deepEqual(itens[0].opcoes, []);
  }
});

test("7 CPF repetido com mesmo nome: uma duplicidade, sem ação", () => {
  const { itens, resumo } = compararFolha([linha("ANA SOUZA", A), linha("ANA SOUZA", A, { origem: "Folha:3" })], [func("1", "ANA SOUZA", A)]);
  assert.equal(itens.length, 1);
  assert.equal(itens[0].tipo, "DUPLICADO");
  assert.deepEqual(itens[0].origens, ["Folha:2", "Folha:3"]);
  assert.deepEqual(itens[0].opcoes, []);
  assert.equal(resumo.total_folha, 2);
});

test("8 CPF repetido com nomes diferentes é sinalizado", () => {
  const i = um([linha("ANA SOUZA", A), linha("CARLOS LIMA", A)], []);
  assert.equal(i.tipo, "DUPLICADO");
  assert.match(i.motivo, /nomes diferentes/);
});

test("9 inativo presente: propõe reativação", () => {
  const i = um([linha("ANA SOUZA", A)], [func("1", "ANA SOUZA", A, { status: "inativo" })]);
  assert.equal(i.tipo, "INATIVO");
  assert.equal(i.acao, "REATIVAR");
});

test("10 férias presente: confere e não muda", () => {
  const i = um([linha("ANA SOUZA", A)], [func("1", "ANA SOUZA", A, { status: "ferias" })]);
  assert.equal(i.tipo, "CORRESPONDENTE");
  assert.deepEqual(i.opcoes, []);
});

test("11 ativo e férias fora da folha: ausente, sem nenhuma ação", () => {
  const { itens } = compararFolha([], [func("1", "ANA", A), func("2", "BIA", B, { status: "ferias" })]);
  assert.deepEqual(itens.map((i) => i.tipo), ["AUSENTE", "AUSENTE"]);
  for (const i of itens) { assert.equal(i.acao, null); assert.deepEqual(i.opcoes, []); }
});

test("inativo fora da folha não gera item", () => {
  assert.equal(compararFolha([], [func("1", "ANA", A, { status: "inativo" })]).itens.length, 0);
});

test("dois cadastros com o nome: nunca escolhe um", () => {
  const i = um([linha("ANA SOUZA", C)], [func("1", "ANA SOUZA", A), func("2", "ANA SOUZA", B)]);
  assert.equal(i.tipo, "PENDENCIA");
  assert.equal(i.funcionario_id, null);
});

test("RE repetido não vincula: mesma matrícula com outro CPF e outro nome é novo", () => {
  const { itens } = compararFolha([linha("CARLOS LIMA", D, { re: "R-1" })], [func("1", "ANA SOUZA", A)]);
  assert.deepEqual(itens.map((i) => i.tipo).sort(), ["AUSENTE", "NOVO"]);
});

test("resumo soma cada grupo", () => {
  const { resumo } = compararFolha(
    [linha("ANA SOUZA", A), linha("BRUNO LIMA NETO", B), linha("NOVA PESSOA", D), linha("SEM CPF", "")],
    [func("1", "ANA SOUZA", A), func("2", "BRUNO LIMA", B), func("3", "FORA DA FOLHA", C)],
  );
  assert.deepEqual(resumo, { total_folha: 4, correspondencias: 1, novos: 1, ausentes: 1, divergencias: 1, inativos: 0, duplicidades: 0, pendencias: 1 });
});

test("nenhuma classificação oferece inativar", () => {
  const src = readFileSync("src/lib/conferencia.ts", "utf8");
  assert.doesNotMatch(src, /"INATIVAR"/);
  const { itens } = compararFolha([linha("X Y", A)], [func("1", "ANA", B), func("2", "BIA", C, { status: "inativo" })]);
  for (const i of itens) assert.ok(!(i.opcoes as string[]).includes("INATIVAR"));
});

test("o que é gravado: CPF completo só onde a ação precisa", () => {
  const { itens } = compararFolha(
    [linha("ANA SOUZA", A), linha("NOVA PESSOA", D), linha("CARLA NUNES", B, { re: "R-3" })],
    [func("1", "ANA SOUZA", A), func("2", "FORA", "45317828791"), func("3", "CARLA NUNES", C)],
  );
  const g = itens.map(paraGravar);
  const por = (t: string) => g.find((i) => i.tipo === t)!;
  assert.equal(por("CORRESPONDENTE").folha!.cpf, "***.444.777-**");
  assert.equal(por("CORRESPONDENTE").atual!.cpf, "***.444.777-**");
  assert.equal(por("AUSENTE").atual!.cpf, "***.178.287-**");
  assert.equal(por("NOVO").folha!.cpf, D);
  assert.equal(por("DIVERGENCIA_CPF").atual!.cpf, C, "precisa do atual para comparar");
});

test("cadastro com pontuação ou sem zero à esquerda casa com a folha", () => {
  const i = um([linha("JOSE SILVA", A)], [func("1", "JOSE SILVA", "111.444.777-35")]);
  assert.equal(i.tipo, "CORRESPONDENTE");
  const z = um([linha("ANA COSTA", "01234567890")], [func("2", "ANA COSTA", "1234567890")]);
  assert.equal(z.tipo, "CORRESPONDENTE");
});

test("paraExibir nunca entrega CPF completo, nem com pontuação", () => {
  const i = compararFolha([linha("JOSE SILVA NETO", B)], [func("1", "JOSE SILVA", "529.982.247-25", { re: "1" })]).itens[0];
  const e = paraExibir(i);
  assert.equal(e.folha?.cpf, "***.982.247-**");
  assert.equal(e.atual?.cpf, "***.982.247-**");
  assert.equal(paraExibir(e).folha?.cpf, "***.982.247-**");
});

const pessoa = (l: LinhaFolha[], f: FuncionarioBase[]) => compararFolha(l, f).itens.map((i) => [i.tipo, i.opcoes.join()]);

test("inativo com mesmo CPF e nome sem relação não oferece reativação", () => {
  const i = um([linha("CARLOS PEREIRA", A)], [func("1", "MARIA SOUZA", A, { status: "inativo" })]);
  assert.equal(i.tipo, "PENDENCIA");
  assert.deepEqual(i.opcoes, []);
});

test("CPF do cadastro presente em outra linha bloqueia a correção", () => {
  const l = [linha("PEDRO LIMA", A), linha("JOSE SILVA", B, { re: "R-1" })];
  assert.deepEqual(pessoa(l, [func("1", "JOSE SILVA", A)]), [["PENDENCIA", ""], ["PENDENCIA", ""]]);
});

test("duas linhas para o mesmo cadastro não oferecem alteração", () => {
  assert.deepEqual(pessoa([linha("ANA COSTA", A), linha("ANA COSTA", B)], [func("1", "ANA COSTA", null)]), [["PENDENCIA", ""], ["PENDENCIA", ""]]);
  assert.deepEqual(pessoa([linha("JOSE SILVA", B, { re: "R-1" }), linha("JOSE SILVA", C, { re: "R-1" })], [func("1", "JOSE SILVA", A)]), [["PENDENCIA", ""], ["PENDENCIA", ""]]);
  const ruim = linha("JOSE SILVA", "123", { cpfValido: false });
  assert.deepEqual(pessoa([ruim, linha("JOSE SILVA", B, { re: "R-1" })], [func("1", "JOSE SILVA", A)]), [["PENDENCIA", ""], ["PENDENCIA", ""]]);
});

test("homônimo continua podendo ser cadastrado, sem tocar no cadastro existente", () => {
  const { itens } = compararFolha([linha("JOSE SILVA", B)], [func("1", "JOSE SILVA", A)]);
  assert.deepEqual(itens.map((i) => [i.tipo, i.opcoes.join()]), [["PENDENCIA", "CADASTRAR"], ["AUSENTE", ""]]);
});

test("item bloqueado não retém CPF completo", () => {
  const { itens } = compararFolha([linha("JOSE SILVA", B, { re: "R-1" }), linha("JOSE SILVA", C, { re: "R-1" })], [func("1", "JOSE SILVA", A)]);
  for (const i of itens.map(paraGravar)) assert.ok(i.folha?.cpf.startsWith("***") && i.atual?.cpf?.startsWith("***"), JSON.stringify(i));
});

test("duas pessoas com o nome de um cadastro seguem podendo ser cadastradas", () => {
  assert.deepEqual(pessoa([linha("JOSE SILVA", B), linha("JOSE SILVA", C)], [func("1", "JOSE SILVA", A)]).slice(0, 2), [["PENDENCIA", "CADASTRAR"], ["PENDENCIA", "CADASTRAR"]]);
});
