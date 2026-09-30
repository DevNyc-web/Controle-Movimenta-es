import { test } from "node:test";
import assert from "node:assert/strict";
import ExcelJS from "exceljs";
import { agruparPorFuncionario, totaisGerais, LABEL_FOLHA } from "../src/lib/relatorio.ts";
import { buildWorkbook } from "../src/lib/relatorio-excel.ts";

let n = 0;
const ft = (fid: string, nome: string, data: string, valor: number, folha = false): any => ({
  id: `id${++n}`, numero_ft: `FT-${String(n).padStart(3, "0")}`, funcionario_id: fid, data_ft: data, horas_trabalhadas: 12,
  valor_pago: valor, pagamento_em_folha: folha, status: "APROVADA", funcionario: { nome, re: fid, cargo: "Vigilante" },
});
// intercalado de propósito: JOÃO, MARIA, JOÃO, CARLOS, JOÃO, MARIA, JOÃO
const base = [
  ft("j", "JOÃO", "2026-09-01", 150), ft("m", "MARIA", "2026-09-02", 130), ft("j", "JOÃO", "2026-09-03", 150, true),
  ft("c", "CARLOS", "2026-09-04", 200), ft("j", "JOÃO", "2026-09-05", 200), ft("m", "MARIA", "2026-09-06", 130), ft("j", "JOÃO", "2026-09-07", 150),
];

test("1-2 funcionário com 4 FTs em um único grupo; grupos contíguos", () => {
  const g = agruparPorFuncionario(base);
  assert.equal(g.length, 3);
  assert.equal(g.find((x) => x.funcionarioId === "j")!.items.length, 4);
  assert.deepEqual(g.map((x) => x.nome), ["CARLOS", "JOÃO", "MARIA"]);
  const datas = g.find((x) => x.funcionarioId === "j")!.items.map((i) => i.data_ft);
  assert.deepEqual(datas, [...datas].sort());
});

test("3 mesmo nome, IDs diferentes => grupos separados", () => {
  const g = agruparPorFuncionario([ft("a", "JOSÉ", "2026-09-01", 100), ft("b", "JOSÉ", "2026-09-02", 100)]);
  assert.equal(g.length, 2);
});

test("4-5,10-12 subtotal individual e geral; folha não soma", () => {
  const g = agruparPorFuncionario(base);
  assert.equal(g.find((x) => x.funcionarioId === "j")!.valor, 150 + 200 + 150); // FT folha (150) fora
  assert.equal(g.find((x) => x.funcionarioId === "m")!.valor, 260);
  assert.equal(totaisGerais(base).valor, 500 + 260 + 200);
  assert.equal(totaisGerais(base).total, 7);
  assert.equal(totaisGerais(base).valor, g.reduce((s, x) => s + x.valor, 0));
});

test("7 FT normal continua com valor; 9 folha mostra label; 6 Excel agrupado", async () => {
  const wb = buildWorkbook(base, "2026-09-01", "2026-09-30", "Emitido");
  const buf = await wb.xlsx.writeBuffer();
  const re = new ExcelJS.Workbook();
  await re.xlsx.load(buf as ArrayBuffer);
  const ws = re.getWorksheet("Relatório")!;
  const r: any[][] = [];
  ws.eachRow({ includeEmpty: true }, (row) => r.push(row.values as any[]));
  const col = (row: any[], i: number) => row[i];
  const dataRows = r.filter((x) => /^\d\d\/\d\d\/\d{4}$/.test(String(col(x, 1))));
  assert.equal(dataRows.length, 7); // nenhuma movimentação perdida/duplicada
  // nomes consecutivos (col 2) formam blocos contíguos
  const seq = dataRows.map((x) => col(x, 2));
  assert.deepEqual(seq, ["CARLOS", "JOÃO", "JOÃO", "JOÃO", "JOÃO", "MARIA", "MARIA"]);
  assert.ok(dataRows.some((x) => col(x, 9) === LABEL_FOLHA));
  assert.ok(dataRows.some((x) => col(x, 9) === 200));
  const subs = r.filter((x) => String(col(x, 7)).startsWith("TOTAL ") && col(x, 7) !== "TOTAL GERAL");
  assert.deepEqual(subs.map((x) => [col(x, 7), col(x, 9)]), [["TOTAL CARLOS", 200], ["TOTAL JOÃO", 500], ["TOTAL MARIA", 260]]);
  assert.equal(col(r.find((x) => col(x, 7) === "TOTAL GERAL")!, 9), 960);
  assert.ok(ws.getRow(1).values && r.some((x) => String(col(x, 5)).includes("Funcionário faltante"))); // coluna preservada
});
