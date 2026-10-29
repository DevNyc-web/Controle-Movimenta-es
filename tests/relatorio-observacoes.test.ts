// Coluna K "Observações" (ft.observacao): cada FT na própria linha, mesmo com empresas/funcionários diferentes.
import { test } from "node:test";
import assert from "node:assert/strict";
import ExcelJS from "exceljs";
import { buildWorkbook, textoObservacao } from "../src/lib/relatorio-excel.ts";

let n = 0;
// valor_pago único por FT (100 + n): identifica no Excel de qual FT é cada linha.
const ft = (fid: string, nome: string, empresa: string | null, observacao: unknown, over: Record<string, unknown> = {}): any => {
  n++;
  return {
    id: `id${n}`, numero_ft: `FT-${n}`, funcionario_id: fid, data_ft: `2026-10-${String(n).padStart(2, "0")}`, horas_trabalhadas: 12,
    valor_pago: 100 + n, pagamento_em_folha: false, status: "APROVADA", posto_falta: "P1", escala_servico: "12x36",
    funcionario: { nome, re: `RE-${fid}`, cargo: "Vigilante", empresa }, observacao, ...over,
  };
};
const REM = "MC REMOTA LTDA", SERV = "MC SERVICOS PATRIMONIAIS EIRELI";
const LONGA = "Cobertura estendida por solicitação do cliente; supervisor ciente e de acordo. ".repeat(30).trim();
const base = [
  ft("z1", "ZECA", SERV, "obs ZECA 1"),
  ft("a1", "ANA", REM, null),
  ft("z1", "ZECA", SERV, LONGA),
  ft("j1", "JOSÉ", REM, "obs JOSÉ (REM)"),
  ft("j2", "JOSÉ", SERV, "obs JOSÉ (SERV)"), // mesmo nome, outro funcionário em outra empresa
  ft("a1", "ANA", REM, ""),
  ft("s1", "SEM EMPRESA", null, "obs sem empresa"),
  ft("f1", "FÓRMULA", REM, '=HYPERLINK("http://x","clique")'),
  ft("f1", "FÓRMULA", REM, "+5511999999999"),
  ft("f1", "FÓRMULA", REM, "-1+2"),
  ft("f1", "FÓRMULA", REM, "@SOMA(A1)", { pagamento_em_folha: true }),
];

async function ler(wb: ExcelJS.Workbook) {
  const back = new ExcelJS.Workbook();
  await back.xlsx.load(Buffer.from(await wb.xlsx.writeBuffer()));
  return back.getWorksheet("Relatório")!;
}
const linhas = (ws: ExcelJS.Worksheet) => ws.getRows(1, ws.rowCount)!;
const ehData = (r: ExcelJS.Row) => /^\d\d\/\d\d\/\d{4}$/.test(String(r.getCell(1).value ?? ""));

test("cada observação fica na linha da própria FT, em empresas e funcionários diferentes; vazia sem observação", async () => {
  const ws = await ler(buildWorkbook(base, "2026-10-01", "2026-10-31", "E"));
  const dados = linhas(ws).filter(ehData);
  assert.equal(dados.length, base.length);
  for (const r of dados) {
    // a FT da linha: pelo valor único (ou, na FT em folha, pela data)
    const f = base.find((x) => x.valor_pago === r.getCell(9).value || `${x.data_ft.slice(8, 10)}/10/2026` === r.getCell(1).value)!;
    assert.equal(r.getCell(2).value, f.funcionario.nome);
    assert.equal(r.getCell(11).value, f.observacao || null, `FT ${f.numero_ft}`);
  }
  // as duas FTs de JOSÉ ficam em blocos de empresa diferentes, cada uma com a sua observação
  const empresaDaLinha = (alvo: ExcelJS.Row) => {
    let emp = "";
    for (const r of linhas(ws)) {
      if (r.getCell(1).fill && (r.getCell(1).fill as any).fgColor?.argb === "FF3D3022" && r.number > 4 && !ehData(r)) emp = String(r.getCell(1).value);
      if (r.number === alvo.number) return emp;
    }
  };
  const jose = dados.filter((r) => r.getCell(2).value === "JOSÉ");
  assert.deepEqual(jose.map((r) => [empresaDaLinha(r), r.getCell(11).value]), [[REM, "obs JOSÉ (REM)"], [SERV, "obs JOSÉ (SERV)"]]);
});

test("texto longo inteiro com quebra de linha; '=', '+', '-', '@' ficam como texto, nunca fórmula", async () => {
  const ws = await ler(buildWorkbook(base, "2026-10-01", "2026-10-31", "E"));
  const obs = (v: string) => linhas(ws).find((r) => r.getCell(11).value === v)!.getCell(11);
  const longa = obs(LONGA);
  assert.equal(longa.alignment?.wrapText, true);
  assert.equal(longa.row.height, undefined); // altura automática: não corta o texto
  for (const v of ['=HYPERLINK("http://x","clique")', "+5511999999999", "-1+2", "@SOMA(A1)"]) {
    const c = obs(v);
    assert.equal(c.type, ExcelJS.ValueType.String, v);
    assert.equal(c.formula, undefined, v);
    assert.equal(c.numFmt, "@", v);
  }
  assert.equal(ws.getColumn(11).width, 30);
});

test("títulos, faixas, subtotais e total geral vão até a coluna K; valores das 10 colunas intactos", async () => {
  const ws = await ler(buildWorkbook(base, "2026-10-01", "2026-10-31", "E"));
  for (const ref of ["K1", "K2", "K3"]) assert.ok(ws.getCell(ref).isMerged, ref);
  assert.equal(ws.getCell("K1").master.address, "F1");
  const rs = linhas(ws);
  for (const r of rs.filter((r) => /^(TOTAL|SUBTOTAL) /.test(String(r.getCell(7).value ?? "")))) {
    assert.equal(r.getCell(11).value, null);
    assert.deepEqual(r.getCell(11).fill, r.getCell(10).fill, `linha ${r.number} col K sem a cor da faixa`);
  }
  for (const r of rs.filter((r) => /—\s+RE |^Movimentações:/.test(String(r.getCell(1).value ?? "")))) assert.equal(r.getCell(11).master.address, `A${r.number}`);
  const geral = rs.find((r) => r.getCell(7).value === "TOTAL GERAL")!;
  assert.equal(geral.getCell(9).value, base.filter((f) => !f.pagamento_em_folha).reduce((s, f) => s + f.valor_pago, 0));
  assert.equal(geral.getCell(10).value, `${base.length} reg.`);
  const ps = ws.pageSetup;
  assert.deepEqual([ps.orientation, ps.paperSize, ps.fitToWidth, ps.fitToHeight], ["portrait", 9, 1, 0]);
});

test("textoObservacao: vazio/espaços/não-texto => null; remove controles inválidos em XML; limite de 32.767 do Excel", () => {
  assert.equal(textoObservacao(null), null);
  assert.equal(textoObservacao(undefined), null);
  assert.equal(textoObservacao("   "), null);
  assert.equal(textoObservacao(42), null);
  assert.equal(textoObservacao("  linha 1\nlinha 2\t "), "  linha 1\nlinha 2\t "); // texto preservado como gravado
  assert.equal(textoObservacao("a\u0000b\u0007c"), "abc");
  const enorme = textoObservacao("x".repeat(40000))!;
  assert.equal(enorme.length, 32767);
  assert.ok(enorme.endsWith(" [truncado]"));
  assert.equal(textoObservacao("y".repeat(32767)), "y".repeat(32767));
});
