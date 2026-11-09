import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { compararOficial, compararPagamentos, exigeJustificativa, type FuncionarioBase } from "../src/lib/conferencia.ts";
import { cpfValido, type LinhaFolha } from "../src/lib/importacao-funcionarios.ts";

// CPFs sintéticos com dígito válido
const [A, B, C, D, E, F] = ["61300101334", "61300202602", "61300303980", "61300405201", "61300506580", "61300607858"];
const REMOTA = "MC REMOTA LTDA", GERAIS = "M C SERVICOS GERAIS LTDA";
const L = (nome: string, cpf: string, re: string, cargo = "PORTEIRO", x: Partial<LinhaFolha> = {}): LinhaFolha =>
  ({ origem: `Relacao:${re}`, nome, cpf, cpfValido: cpfValido(cpf), re, cargo, empresa: "", admissao: null, ...x });
const Fu = (id: string, nome: string, cpf: string | null, re: string, x: Partial<FuncionarioBase> = {}): FuncionarioBase =>
  ({ id, nome, cpf, re, cargo: "Porteiro", empresa: REMOTA, status: "ativo", data_admissao: null, ...x });
const posterior = { empresa: REMOTA, primeira: false }, primeira = { empresa: REMOTA, primeira: true };
const resumo = (l: LinhaFolha[], f: FuncionarioBase[], ctx = posterior) => compararOficial(l, f, ctx).itens.map((i) => [i.tipo, i.funcionario_id ?? "-", i.opcoes.join()]);

test("CPF, empresa e RE batem: correspondência sem ação", () => {
  assert.deepEqual(resumo([L("ANA COSTA", A, "1")], [Fu("1", "ANA COSTA", A, "1")]), [["CORRESPONDENTE", "1", ""]]);
});

test("mesmo cadastro: nome, cargo e reativação viram itens separados", () => {
  const r = resumo([L("ANA COSTA LIMA", A, "1", "VIGILANTE")], [Fu("1", "ANA COSTA", A, "1", { status: "inativo" })]);
  assert.deepEqual(r, [["INATIVO", "1", "REATIVAR"], ["DIVERGENCIA_NOME", "1", "ATUALIZAR_NOME"], ["DIVERGENCIA_CARGO", "1", "ATUALIZAR_CARGO"]]);
});

test("cargo não reconhecido: pendência, cargo atual intacto; sinônimo conhecido é mapeado", () => {
  assert.deepEqual(resumo([L("ANA COSTA", A, "1", "GERENTE DE RH")], [Fu("1", "ANA COSTA", A, "1")]), [["PENDENCIA", "1", ""]]);
  assert.deepEqual(resumo([L("ANA COSTA", A, "1", "AUX SERV GERAIS")], [Fu("1", "ANA COSTA", A, "1", { cargo: "ASG" })]), [["CORRESPONDENTE", "1", ""]]);
  const novo = compararOficial([L("BIA NOVA", B, "9", "AUX ADMINISTRATIVO")], [], primeira).itens[0];
  assert.equal(novo.tipo, "NOVO");
  assert.equal(novo.folha?.cargo_sistema, null);
});

test("nome sem relação com o mesmo CPF: pendência sem ação", () => {
  assert.deepEqual(resumo([L("CARLOS PEREIRA", A, "1")], [Fu("1", "MARIA SOUZA", A, "1", { status: "inativo" })]), [["PENDENCIA", "1", ""]]);
});

test("cadastro sem empresa: pendência de identificação, nunca atribui empresa", () => {
  assert.deepEqual(resumo([L("ANA COSTA", A, "1")], [Fu("1", "ANA COSTA", A, "1", { empresa: null })]), [["PENDENCIA", "1", ""]]);
});

test("RE diferente para o mesmo CPF: correção assistida só com RE livre na empresa", () => {
  assert.deepEqual(resumo([L("ANA COSTA", A, "2")], [Fu("1", "ANA COSTA", A, "1")]), [["DIVERGENCIA_RE", "1", "CORRIGIR_RE"]]);
  const ocupado = resumo([L("ANA COSTA", A, "2")], [Fu("1", "ANA COSTA", A, "1"), Fu("2", "OUTRA PESSOA", B, "2")]);
  assert.deepEqual(ocupado[0], ["DIVERGENCIA_RE", "1", ""]);
});

test("empresa diferente para o mesmo CPF: correção assistida, RE da planilha precisa estar livre", () => {
  assert.deepEqual(resumo([L("ANA COSTA", A, "7")], [Fu("1", "ANA COSTA", A, "1", { empresa: GERAIS })]), [["DIVERGENCIA_EMPRESA", "1", "CORRIGIR_EMPRESA"]]);
  assert.deepEqual(resumo([L("ANA COSTA", A, "7")], [Fu("1", "ANA COSTA", A, "1", { empresa: GERAIS }), Fu("2", "DONO DO SETE", B, "7")])[0], ["DIVERGENCIA_EMPRESA", "1", ""]);
});

test("RE repetido na empresa: identidade ambígua, nenhuma ação", () => {
  const r = resumo([L("ANA COSTA", A, "5")], [Fu("1", "ANA COSTA", null, "5"), Fu("2", "ANA COSTA", null, "5")]);
  assert.deepEqual(r[0], ["PENDENCIA", "-", ""]);
  assert.ok(!r.some(([t]) => t === "AUSENTE"), "os dois do RE ambíguo não viram ausentes");
});

test("RE da mesma empresa: preencher CPF ou corrigir CPF só com nome compatível", () => {
  assert.deepEqual(resumo([L("ANA COSTA", A, "5")], [Fu("1", "ANA COSTA", null, "5")]), [["PENDENCIA", "1", "PREENCHER_CPF"]]);
  assert.deepEqual(resumo([L("ANA COSTA", A, "5")], [Fu("1", "ANA COSTA", B, "5")]), [["DIVERGENCIA_CPF", "1", "CORRIGIR_CPF"]]);
  assert.deepEqual(resumo([L("ANA COSTA", A, "5")], [Fu("1", "PEDRO LIMA", B, "5")]), [["PENDENCIA", "1", ""]]);
});

test("RE de OUTRA empresa não identifica ninguém", () => {
  const r = resumo([L("ANA COSTA", A, "5")], [Fu("1", "ANA COSTA", B, "5", { empresa: GERAIS })]);
  assert.deepEqual(r, [["PENDENCIA", "-", "CADASTRAR"]], "homônimo: cadastro só com justificativa");
});

test("nunca associa só pelo nome; CPF novo sem homônimo vira cadastro", () => {
  assert.deepEqual(resumo([L("BIA NOVA", C, "9")], [Fu("1", "ANA COSTA", A, "1")]).find(([t]) => t !== "AUSENTE"), ["NOVO", "-", "CADASTRAR"]);
});

test("duplicidades no arquivo: CPF ou RE repetido não têm ação", () => {
  const r = resumo([L("ANA COSTA", A, "1"), L("ANA COSTA", A, "2"), L("BIA", B, "3"), L("CAIO", C, "3")], [Fu("1", "ANA COSTA", A, "1")]);
  assert.deepEqual(r.map(([t, , o]) => [t, o]), [["DUPLICADO", ""], ["DUPLICADO", ""], ["DUPLICADO", ""], ["DUPLICADO", ""]]);
});

test("duas linhas para o mesmo cadastro bloqueiam as ações nele", () => {
  const r = resumo([L("ANA COSTA", A, "8"), L("ANA COSTA", D, "1")], [Fu("1", "ANA COSTA", A, "1")]);
  assert.ok(r.every(([, , o]) => o === "" || o === "CADASTRAR"), JSON.stringify(r));
});

test("CPF inválido: pendência, mas não deixa o funcionário do RE aparecer como ausente", () => {
  const r = resumo([L("ANA COSTA", "12345678900", "1")], [Fu("1", "ANA COSTA", A, "1")]);
  assert.deepEqual(r, [["PENDENCIA", "-", ""]]);
});

test("primeira importação: ausente só sinalizado", () => {
  assert.deepEqual(resumo([], [Fu("1", "ANA COSTA", A, "1")], primeira), [["AUSENTE", "1", ""]]);
});

test("importação posterior: ausente pode ser proposto para inativação", () => {
  assert.deepEqual(resumo([], [Fu("1", "ANA COSTA", A, "1")]), [["AUSENTE", "1", "INATIVAR"]]);
});

test("ausentes: só da empresa da planilha, nunca freelancer, nunca quem já é inativo", () => {
  const { itens, resumo: z } = compararOficial([], [
    Fu("1", "OUTRA EMPRESA", A, "1", { empresa: GERAIS }), Fu("2", "FREELA", B, "2", { cargo: "Freelancer" }),
    Fu("3", "JA INATIVO", C, "3", { status: "inativo" }), Fu("4", "SEM EMPRESA", D, "4", { empresa: null }), Fu("5", "FERIAS", E, "5", { status: "ferias" })], posterior);
  assert.deepEqual(itens.map((i) => [i.tipo, i.funcionario_id, i.opcoes.join()]), [["AUSENTE", "5", "INATIVAR"]]);
  assert.equal(z.nao_avaliados, 1);
});

test("INATIVAR só existe em item AUSENTE", () => {
  const { itens } = compararOficial([L("ANA COSTA LIMA", A, "1"), L("BIA", F, "9")], [Fu("1", "ANA COSTA", A, "1", { status: "inativo" }), Fu("2", "X Y", B, "2")], posterior);
  for (const i of itens) if (i.opcoes.includes("INATIVAR")) assert.equal(i.tipo, "AUSENTE");
});

test("Itaú: somente leitura, nenhum item com ação, sem ausentes, CNPJ identificado", () => {
  const { itens, resumo: z } = compararPagamentos(
    [L("ANA COSTA", A, ""), L("PESSOA PAGA", C, ""), L("INATIVO PAGO", B, ""), L("EMPRESA X", "12.345.678/0001-95", "")],
    [Fu("1", "ANA COSTA", A, "1"), Fu("2", "INATIVO PAGO", B, "2", { status: "inativo" }), Fu("3", "NAO PAGO", D, "3")]);
  assert.ok(itens.every((i) => i.opcoes.length === 0 && i.acao === null));
  assert.ok(!itens.some((i) => i.tipo === "AUSENTE"));
  assert.equal(z.ausentes, 0);
  assert.equal(itens.find((i) => i.folha?.nome === "PESSOA PAGA")?.motivo, "Pagamento sem funcionário identificado");
  assert.equal(itens.find((i) => i.folha?.nome === "INATIVO PAGO")?.motivo, "Pagamento a funcionário inativo");
  assert.equal(itens.find((i) => i.folha?.nome === "EMPRESA X")?.motivo, "Pagamento a CNPJ");
});

test("trocar cargo de ou para Freelancer exige justificativa; outras trocas de cargo não", () => {
  assert.equal(exigeJustificativa("ATUALIZAR_CARGO", "DIVERGENCIA_CARGO", ["Freelancer", "Vigilante"]), true);
  assert.equal(exigeJustificativa("ATUALIZAR_CARGO", "DIVERGENCIA_CARGO", ["Porteiro", "Freelancer"]), true);
  assert.equal(exigeJustificativa("ATUALIZAR_CARGO", "DIVERGENCIA_CARGO", ["Porteiro", "Vigilante"]), false);
  assert.equal(exigeJustificativa("INATIVAR", "AUSENTE"), true);
});

test("Auditoria lê pela função com CPF mascarado, nunca direto da tabela", () => {
  const s = readFileSync("src/routes/_app.auditoria.tsx", "utf8");
  assert.match(s, /rpc\("auditoria_listar"/);
  assert.doesNotMatch(s, /from\("audit_logs"\)/);
});
