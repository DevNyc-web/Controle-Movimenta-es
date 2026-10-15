// Excel compacto x Excel original (cópia congelada em tests/fixtures): mesmos registros, valores, formatos e totais.
import { test } from "node:test";
import assert from "node:assert/strict";
import ExcelJS from "exceljs";
import { buildWorkbook } from "../src/lib/relatorio-excel.ts";
import { buildWorkbook as buildOriginal } from "./fixtures/relatorio-excel-original.ts";
import { mesesExcedidos, filtrarRelatorio, totaisGerais } from "../src/lib/relatorio.ts";

let n = 0;
const ft = (fid: string, nome: string, data: string, status: string, over: Record<string, unknown> = {}): any => ({
  id: `id${String(++n).padStart(5, "0")}`, numero_ft: `FT-${n}`, funcionario_id: fid, data_ft: data, horas_trabalhadas: 12,
  valor_pago: 200, pagamento_em_folha: false, status, posto_falta: "P1", escala_servico: "12x36",
  funcionario: { nome, re: `RE-${fid}`, cargo: "Vigilante" }, funcionario_faltante: { nome: "FALTANTE X", re: "9" }, ...over,
});
const STATUS = ["PENDENTE", "APROVADA", "NEGADA", "CANCELADA", "CANCELAMENTO_SOLICITADO"];
const base = [
  ...Array.from({ length: 6 }, (_, k) => ft("j", "JOÃO DA SILVA PEREIRA DOS SANTOS", `2026-10-${String(k + 1).padStart(2, "0")}`, STATUS[k % 5], { valor_pago: 200.35 })),
  ft("j", "JOÃO DA SILVA PEREIRA DOS SANTOS", "2026-09-30", "APROVADA", { pagamento_em_folha: true, valor_pago: 999 }),
  ft("m", "MARIA", "2026-10-02", "APROVADA", { valor_pago: "150.00", funcionario: { nome: "MARIA", re: "RE-m", cargo: "Porteiro" }, funcionario_faltante: null, escala_servico: null, tipo_folga: "FOLGA" }),
  ft("m", "MARIA", "2026-10-03", "NEGADA", { pagamento_em_folha: true, horas_trabalhadas: "6.5" }),
  ft("a", "ANA", "2026-10-09", "PENDENTE", { valor_pago: 0.1, posto_falta: null }),
  ...Array.from({ length: 40 }, (_, k) => ft(`f${k}`, `FUNC ${String(k).padStart(2, "0")}`, `2026-10-${String((k % 28) + 1).padStart(2, "0")}`, STATUS[k % 5], { valor_pago: 130 + k / 100 })),
];

async function ler(wb: ExcelJS.Workbook) {
  const back = new ExcelJS.Workbook();
  await back.xlsx.load(Buffer.from(await wb.xlsx.writeBuffer()));
  return back.getWorksheet("Relatório")!;
}
const ehData = (r: ExcelJS.Row) => /^\d\d\/\d\d\/\d{4}$/.test(String(r.getCell(1).value ?? ""));
const ehTotal = (r: ExcelJS.Row) => String(r.getCell(7).value ?? "").startsWith("TOTAL ");
const cel = (r: ExcelJS.Row, c: number) => { const x = r.getCell(c); return [x.value, x.numFmt ?? null, (x.font?.color as any)?.argb ?? null]; };

/** Tudo o que tem significado: linhas de FT (10 colunas, valor/formato/cor), cabeçalhos de grupo, subtotais e total. */
function conteudo(ws: ExcelJS.Worksheet) {
  const dados: unknown[] = [], grupos: unknown[] = [], totais: unknown[] = [];
  ws.eachRow((r) => {
    if (ehData(r)) dados.push(Array.from({ length: 10 }, (_, k) => cel(r, k + 1)));
    else if (/—\s+RE /.test(String(r.getCell(1).value ?? ""))) grupos.push(cel(r, 1));
    else if (ehTotal(r)) totais.push([7, 8, 9, 10].map((c) => cel(r, c)));
  });
  return { dados, grupos, totais };
}

for (const [nome, items, status] of [["todos", base, ""], ["só NEGADA", filtrarRelatorio(base, { status: "NEGADA" }), "NEGADA"], ["vazio", [], ""]] as const) {
  test(`mesmos registros, valores, formatos, cores e totais do original (${nome})`, async () => {
    const exc = mesesExcedidos(base);
    const novo = await ler(buildWorkbook([...items], "2026-09-01", "2026-10-31", "Emitido em X", exc, status));
    const orig = await ler(buildOriginal([...items], "2026-09-01", "2026-10-31", "Emitido em X", exc, status));
    const a = conteudo(novo), b = conteudo(orig);
    assert.equal(a.dados.length, items.length);
    assert.deepEqual(a, b);
    assert.equal(novo.getCell("A2").value, orig.getCell("A2").value); // período + status
    assert.equal(novo.getCell("A3").value, orig.getCell("A5").value); // resumo com valor total
    assert.equal(novo.getCell("G1").value, orig.getCell("A3").value); // emitido em
    const cab = (ws: ExcelJS.Worksheet, r: number) => (ws.getRow(r).values as unknown[]).slice(1);
    assert.deepEqual(cab(novo, 4), cab(orig, 6)); // mesmas colunas
  });
}

test("total geral do Excel = totaisGerais (folha fora do valor)", async () => {
  const ws = await ler(buildWorkbook(base, "2026-09-01", "2026-10-31", "E"));
  let geral: ExcelJS.Row | undefined;
  ws.eachRow((r) => { if (r.getCell(7).value === "TOTAL GERAL") geral = r; });
  const t = totaisGerais(base);
  assert.equal(geral!.getCell(8).value, t.horas);
  assert.equal(geral!.getCell(9).value, t.valor);
  assert.equal(geral!.getCell(10).value, `${base.length} reg.`);
});

test("mais compacto sem cortar: sem linhas em branco, nada encolhe, FT com quebra de linha e altura automática, retrato", async () => {
  const novo = await ler(buildWorkbook(base, "2026-09-01", "2026-10-31", "E"));
  const orig = await ler(buildOriginal(base, "2026-09-01", "2026-10-31", "E"));
  const altura = (ws: ExcelJS.Worksheet) => { let h = 0; for (let i = 1; i <= ws.rowCount; i++) h += ws.getRow(i).height ?? 15; return h; };
  const largura = (ws: ExcelJS.Worksheet) => Array.from({ length: 10 }, (_, k) => ws.getColumn(k + 1).width ?? 9).reduce((s, w) => s + w, 0);
  assert.ok(novo.rowCount < orig.rowCount, `${novo.rowCount} < ${orig.rowCount}`);
  assert.ok(altura(novo) < altura(orig) * 0.7, `${altura(novo)} < 70% de ${altura(orig)}`);
  assert.ok(largura(novo) < largura(orig) * 0.75);
  for (let i = 1; i <= novo.rowCount; i++) {
    const r = novo.getRow(i);
    assert.ok(r.cellCount > 0 && (r.values as unknown[]).some((v) => v !== null && v !== undefined && v !== ""), `linha ${i} em branco`);
    assert.ok((r.height ?? 15) <= 28, `linha ${i} alta`);
    r.eachCell((c) => assert.ok(!c.alignment?.shrinkToFit, `texto encolhido na linha ${i}`));
    if (ehData(r)) {
      assert.equal(r.height, undefined, `linha de FT ${i} com altura fixa (cortaria texto quebrado)`);
      for (let c = 1; c <= 10; c++) assert.equal(r.getCell(c).alignment?.wrapText, true, `linha ${i} col ${c} sem quebra`);
    }
  }
  const ps = novo.pageSetup;
  assert.equal(ps.orientation, "portrait");
  assert.equal(ps.paperSize, 9);
  assert.equal(ps.fitToPage, true);
  assert.equal(ps.fitToWidth, 1);
  assert.equal(ps.fitToHeight, 0);
  assert.equal(ps.printTitlesRow, "4:4");
});

test("colunas curtas cabem em 1 linha (tamanhos máximos reais): data, RE, cargo, horas, valor, status", async () => {
  const ws = await ler(buildWorkbook(base, "2026-09-01", "2026-10-31", "E"));
  // largura Excel = nº de caracteres da fonte padrão (Calibri 11); texto 9-10 pt ocupa <= ~0,9 por caractere.
  const cabe = (txt: string, col: number) => txt.length * 0.9 <= (ws.getColumn(col).width ?? 9);
  for (const [txt, col] of [["15/10/2026", 1], ["1234567", 3], ["Recepcionista", 4], ["12.0 h", 8], ["R$ 99.999,99", 9], ["APROVADA", 10], ["PENDENTE", 10], ["NEGADA", 10], ["CANCELADA", 10]] as const)
    assert.ok(cabe(txt, col), `${txt} na coluna ${col}`);
});
