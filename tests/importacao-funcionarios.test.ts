import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import ExcelJS from "exceljs";
import {
  abasDoWorkbook, cargoReconhecido, celulaTexto, cpfDaCelula, cpfValido, detectarColunas, deteccaoConfiavel, extrairLinhas, mascararCpf, nomeNormalizado,
} from "../src/lib/importacao-funcionarios.ts";

// CPFs sintéticos com dígitos verificadores válidos.
const A = "11144477735", B = "52998224725", C = "39053344705";

test("CPF: dígitos verificadores, repetidos e tamanho", () => {
  assert.equal(cpfValido(A), true);
  assert.equal(cpfValido("11144477736"), false);
  assert.equal(cpfValido("11111111111"), false);
  assert.equal(cpfValido("123"), false);
});

test("CPF: célula numérica recompõe zeros; texto com máscara; lixo vira vazio", () => {
  assert.equal(cpfDaCelula(1234567890), "01234567890");
  assert.equal(cpfDaCelula("529.982.247-25"), B);
  assert.equal(cpfDaCelula("NAO INFORMADO"), "");
  assert.equal(cpfDaCelula(null), "");
  assert.equal(cpfDaCelula({ formula: "A1", result: 52998224725 }), B);
});

test("máscara nunca mostra o CPF inteiro", () => {
  assert.equal(mascararCpf(A), "***.444.777-**");
  assert.equal(mascararCpf(""), "—");
  assert.equal(mascararCpf("123"), "***");
});

test("nome normalizado ignora acentos, caixa e espaços", () => {
  assert.equal(nomeNormalizado("  José   d'Ávila "), "JOSE D AVILA");
});

test("cargo desconhecido não vira Freelancer", () => {
  assert.equal(cargoReconhecido("Vigilante Patrimonial"), "Vigilante");
  assert.equal(cargoReconhecido("Auxiliar de Limpeza"), "ASG");
  assert.equal(cargoReconhecido("Freelancer"), "Freelancer");
  assert.equal(cargoReconhecido("Analista Financeiro"), null);
  assert.equal(cargoReconhecido(""), null);
});

test("célula: rich text, fórmula, data e vazio", () => {
  assert.equal(celulaTexto({ richText: [{ text: "AB" }, { text: "C" }] }), "ABC");
  assert.equal(celulaTexto({ formula: "1+1", result: 2 }), "2");
  assert.equal(celulaTexto(new Date("2026-01-02T00:00:00Z")), "2026-01-02");
  assert.equal(celulaTexto(null), "");
});

test("detecta cabeçalho deslocado e sinônimos de folha", () => {
  const m = [["FOLHA DE PAGAMENTO"], ["Competência 10/2026"], [], ["Matrícula", "Colaborador", "C.P.F.", "Função", "Salário Base"], ["10", "ANA SILVA", A, "Porteiro", 2000]];
  const d = detectarColunas(m);
  assert.equal(d.linhaCabecalho, 3);
  assert.deepEqual(d.colunas, { cpf: 2, nome: 1, re: 0, cargo: 3 });
  assert.equal(deteccaoConfiavel(d), true);
});

test("células mescladas repetem o rótulo e não são ambiguidade", () => {
  const d = detectarColunas([["Código", "Nome", "Nome", "Nome", "CPF", "CPF"]]);
  assert.equal(d.colunas.nome, 1);
  assert.deepEqual(d.ambiguos, {});
  assert.equal(deteccaoConfiavel(d), true);
});

test("nome da mãe não é confundido com nome do funcionário", () => {
  const d = detectarColunas([["Nome da mãe", "Nome", "CPF"]]);
  assert.equal(d.colunas.nome, 1);
});

test("duas colunas de nome diferentes exigem mapeamento", () => {
  const d = detectarColunas([["Funcionário", "Colaborador", "CPF"]]);
  assert.ok(d.ambiguos.nome);
  assert.equal(deteccaoConfiavel(d), false);
});

test("sem CPF não é confiável; sem nome não acha cabeçalho", () => {
  assert.equal(deteccaoConfiavel(detectarColunas([["Nome", "Cargo"]])), false);
  assert.equal(detectarColunas([["CPF", "Salário"]]).linhaCabecalho, -1);
});

test("extrai funcionários e explica cada linha ignorada", () => {
  const m = [
    ["Nome", "CPF", "Cargo"],
    ["ANA SILVA", A, "Porteiro"],
    ["Nome", "CPF", "Cargo"],
    ["Departamento: Operações", "", ""],
    ["M C SERVICOS GERAIS LTDA", "", ""],
    ["BRUNO COSTA", "529.982.247-25", "ASG"],
    [],
    ["TOTAL GERAL", "", 4000],
    ["Total de empregados: 2", "", ""],
    ["", "", "Assinatura"],
  ];
  const r = extrairLinhas(m, 0, { nome: 0, cpf: 1, cargo: 2 }, "Folha");
  assert.deepEqual(r.linhas.map((l) => l.nome), ["ANA SILVA", "BRUNO COSTA"]);
  assert.equal(r.totalImpresso, 2);
  assert.deepEqual(r.ignoradas.map((i) => i.motivo), ["cabeçalho repetido", "título de seção", "título de seção", "total ou rodapé", "total da planilha", "sem nome e sem CPF"]);
  assert.equal(r.linhas[1].origem, "Folha:6");
});

test("funcionário sem CPF ou com CPF inválido continua na lista, para revisão", () => {
  const r = extrairLinhas([["Nome", "CPF"], ["ANA SILVA", ""], ["BRUNO COSTA", "111.111.111-11"], ["", C]], 0, { nome: 0, cpf: 1 });
  assert.equal(r.linhas.length, 3);
  assert.deepEqual(r.linhas.map((l) => l.cpfValido), [false, false, true]);
});

test("admissão: data do Excel e texto brasileiro", () => {
  const r = extrairLinhas([["Nome", "CPF", "Admissão"], ["ANA SILVA", A, new Date("2024-03-05T00:00:00Z")], ["BRUNO COSTA", B, "06/04/2023"]], 0, { nome: 0, cpf: 1, admissao: 2 });
  assert.deepEqual(r.linhas.map((l) => l.admissao), ["2024-03-05", "2023-04-06"]);
});

test("layout real da Relação Cadastral (fictício): sem linhas falsas", async () => {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet("Empregados");
  ws.addRow(["MC REMOTA LTDA", "Página:", "1/2"]);
  ws.addRow(["RELAÇÃO CADATRAL", "Emissão:", new Date("2026-05-20T10:00:00Z")]);
  ws.addRow([]); ws.addRow([]);
  ws.addRow(["Código", "Nome", "Cargo", "CPF", "Admissão"]);
  ws.addRow(["10", "ANA SILVA", "PORTEIRO", A, "01/02/2020"]);
  ws.addRow(["MC REMOTA LTDA", "Página:", "2/2"]);
  ws.addRow(["RELAÇÃO CADATRAL", "Emissão:", new Date("2026-05-20T10:00:00Z")]);
  ws.addRow(["Código", "Nome", "Cargo", "CPF", "Admissão"]);
  ws.addRow(["11", "BRUNO COSTA", "VIGILANTE", B, "03/04/2021"]);
  ws.addRow(["Total de empregados:", 2]);
  const [aba] = abasDoWorkbook(wb as never);
  const d = detectarColunas(aba.matriz);
  const r = extrairLinhas(aba.matriz, d.linhaCabecalho, d.colunas, aba.nome);
  assert.deepEqual(r.linhas.map((l) => l.nome), ["ANA SILVA", "BRUNO COSTA"]);
  assert.equal(r.totalImpresso, 2);
});

test("importador antigo usa o leitor compartilhado e não adivinha cargo", () => {
  const imp = readFileSync("src/routes/_app.funcionarios.importar.tsx", "utf8");
  assert.match(imp, /from "@\/lib\/importacao-funcionarios"/);
  assert.doesNotMatch(imp, /return "Freelancer"/);
  assert.doesNotMatch(imp, /function mapCargo/);
  assert.match(imp, /cargoReconhecido/);
});

test("data de admissão impossível não vira data", () => {
  const m = [["Nome", "CPF", "Admissão"], ["ANA", "52998224725", "31/02/2024"], ["BIA", "11144477735", "29/02/2024"]];
  const { linhas } = extrairLinhas(m, 0, { nome: 0, cpf: 1, admissao: 2 });
  assert.equal(linhas[0].admissao, null);
  assert.equal(linhas[1].admissao, "2024-02-29");
});
