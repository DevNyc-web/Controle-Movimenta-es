// Excel agrupado por EMPRESA > FUNCIONÁRIO: ordem, subtotais, sem empresa, nomes/REs repetidos, filtros e impressão.
import { test } from "node:test";
import assert from "node:assert/strict";
import ExcelJS from "exceljs";
import { agruparPorEmpresa, filtrarRelatorio, totaisGerais, SEM_EMPRESA, LABEL_FOLHA } from "../src/lib/relatorio.ts";
import { buildWorkbook } from "../src/lib/relatorio-excel.ts";

let n = 0;
// valor_pago único por FT (100 + n): permite conferir no Excel que cada FT aparece exatamente uma vez.
const ft = (fid: string, nome: string, re: string, empresa: string | null | undefined, status = "APROVADA", over: Record<string, unknown> = {}): any => {
  n++;
  return {
    id: `id${n}`, numero_ft: `FT-${String(n).padStart(3, "0")}`, funcionario_id: fid, data_ft: `2026-10-${String((n % 28) + 1).padStart(2, "0")}`,
    horas_trabalhadas: 12, valor_pago: 100 + n, pagamento_em_folha: false, status, posto_falta: n % 2 ? "P1" : "P2",
    funcionario: { nome, re, cargo: "Vigilante", empresa }, ...over,
  };
};
const REM = "MC REMOTA LTDA", SERV = "MC SERVICOS PATRIMONIAIS EIRELI", ALFA = "ALFA SEGURANCA LTDA";
const base = [
  ft("z1", "ZECA", "10", SERV), ft("a1", "ANA", "11", REM, "PENDENTE"), ft("z1", "ZECA", "10", SERV, "NEGADA"),
  ft("j1", "JOSÉ", "202", REM), ft("j2", "JOSÉ", "202", REM, "CANCELADA"), // mesmo nome e RE, IDs diferentes, mesma empresa
  ft("j3", "JOSÉ", "202", SERV), // mesmo nome e RE em outra empresa
  ft("b1", "BRUNO", "12", ALFA, "CANCELAMENTO_SOLICITADO"), ft("a1", "ANA", "11", REM, "APROVADA", { pagamento_em_folha: true }),
  ft("s1", "SEM CADASTRO", "13", null), ft("s2", "VAZIA", "14", "   "), ft("s3", "UNDEF", "15", undefined), ft("s4", "ÁLVARO", "16", ""),
];

async function ler(wb: ExcelJS.Workbook) {
  const back = new ExcelJS.Workbook();
  await back.xlsx.load(Buffer.from(await wb.xlsx.writeBuffer()));
  return back.getWorksheet("Relatório")!;
}
const linhas = (ws: ExcelJS.Worksheet) => ws.getRows(1, ws.rowCount)!;
const ehData = (r: ExcelJS.Row) => /^\d\d\/\d\d\/\d{4}$/.test(String(r.getCell(1).value ?? ""));

test("empresas em ordem alfabética, SEM EMPRESA por último; funcionários em ordem alfabética dentro de cada empresa", () => {
  const b = agruparPorEmpresa(base);
  assert.deepEqual(b.map((x) => x.empresa), [ALFA, REM, SERV, null]);
  assert.deepEqual(b.map((x) => x.grupos.map((g) => g.funcionarioId)), [["b1"], ["a1", "j1", "j2"], ["j3", "z1"], ["s4", "s1", "s3", "s2"]]);
});

test("sem empresa: null, vazio, só espaços e undefined vão para o mesmo bloco", () => {
  const sem = agruparPorEmpresa(base).find((x) => x.empresa === null)!;
  assert.deepEqual(sem.grupos.map((g) => g.nome).sort(), ["SEM CADASTRO", "UNDEF", "VAZIA", "ÁLVARO"].sort());
});

test("nomes/REs repetidos: um grupo por funcionario_id, nenhuma FT duplicada nem omitida", () => {
  const b = agruparPorEmpresa(base);
  const ids = b.flatMap((x) => x.grupos.flatMap((g) => g.items.map((i) => i.id)));
  assert.equal(ids.length, base.length);
  assert.deepEqual([...ids].sort(), base.map((i) => i.id).sort());
  const jose = b.flatMap((x) => x.grupos).filter((g) => g.nome === "JOSÉ");
  assert.deepEqual(jose.map((g) => [g.funcionarioId, g.empresa, g.items.length]), [["j1", REM, 1], ["j2", REM, 1], ["j3", SERV, 1]]);
});

test("subtotais das empresas somam o total geral (folha fora do valor) e batem com a soma dos funcionários", () => {
  const b = agruparPorEmpresa(base), t = totaisGerais(base);
  for (const k of ["total", "horas", "valor", "APROVADA", "PENDENTE", "NEGADA", "CANCELADA", "CANCELAMENTO_SOLICITADO"])
    assert.equal(b.reduce((s, x) => s + (x.totais[k] ?? 0), 0), t[k], k);
  for (const x of b) {
    assert.equal(x.totais.valor, x.grupos.reduce((s, g) => s + g.valor, 0));
    assert.equal(x.totais.horas, x.grupos.reduce((s, g) => s + g.horas, 0));
  }
  const rem = b.find((x) => x.empresa === REM)!.totais;
  assert.equal(rem.valor, 102 + 104 + 105); // FT em folha (108) não soma
  assert.deepEqual([rem.total, rem.APROVADA, rem.PENDENTE, rem.CANCELADA], [4, 2, 1, 1]);
});

test("Excel: blocos, subtotais e contagem por status por empresa; cada FT uma vez; total geral = soma dos blocos", async () => {
  const ws = await ler(buildWorkbook(base, "2026-10-01", "2026-10-31", "E"));
  const r = linhas(ws);
  const c1 = r.map((x) => String(x.getCell(1).value ?? ""));
  const pos = (s: string) => c1.indexOf(s);
  assert.ok(pos(ALFA) > 3 && pos(ALFA) < pos(REM) && pos(REM) < pos(SERV) && pos(SERV) < pos(SEM_EMPRESA));
  assert.equal(c1.filter((v) => v === REM).length, 1); // um bloco por empresa
  // título da empresa colado no 1º funcionário
  assert.equal(c1[pos(REM) + 1], `ANA  —  RE 11  —  ${REM}`);
  assert.equal(c1[pos(SEM_EMPRESA) + 1], "ÁLVARO  —  RE 16");

  const dados = r.filter(ehData);
  assert.equal(dados.length, base.length);
  assert.deepEqual(dados.map((x) => x.getCell(9).value).filter((v) => v !== LABEL_FOLHA).sort(), base.filter((i) => !i.pagamento_em_folha).map((i) => i.valor_pago).sort());
  assert.equal(dados.filter((x) => x.getCell(9).value === LABEL_FOLHA).length, 1);

  const subs = r.filter((x) => String(x.getCell(7).value ?? "").startsWith("SUBTOTAL "));
  const b = agruparPorEmpresa(base);
  assert.deepEqual(subs.map((x) => [x.getCell(7).value, x.getCell(8).value, x.getCell(9).value, x.getCell(10).value]),
    b.map((x) => [`SUBTOTAL ${x.empresa ?? SEM_EMPRESA}`, x.totais.horas, x.totais.valor, `${x.totais.total} reg.`]));
  const geral = r.find((x) => x.getCell(7).value === "TOTAL GERAL")!;
  assert.equal(geral.getCell(8).value, subs.reduce((s, x) => s + Number(x.getCell(8).value), 0));
  assert.equal(geral.getCell(9).value, subs.reduce((s, x) => s + Number(x.getCell(9).value), 0));
  assert.equal(geral.getCell(10).value, `${base.length} reg.`);

  // linha de status logo após o subtotal da empresa
  const st = (emp: string) => String(r[r.indexOf(subs.find((x) => x.getCell(7).value === `SUBTOTAL ${emp}`)!) + 1].getCell(1).value);
  assert.equal(st(REM), "Movimentações: 4   |   Aprovadas: 2   |   Pendentes: 1   |   Negadas: 0   |   Canceladas: 1");
  assert.equal(st(ALFA), "Movimentações: 1   |   Aprovadas: 0   |   Pendentes: 0   |   Negadas: 0   |   Canceladas: 0   |   Canc. solicitado: 1");

  // resumo do topo continua geral
  assert.match(String(ws.getCell("A3").value), new RegExp(`^Total: ${base.length} `));
  assert.equal(ws.columnCount, 11);
  assert.deepEqual((ws.getRow(4).values as unknown[]).slice(1), ["Data", "Colaborador", "RE", "Cargo", "Funcionário faltante", "Posto da falta", "Escala", "Horas Trab.", "Valor (R$)", "Status", "Observações"]);
});

test("impressão: sem quebras forçadas entre empresas; A4 retrato, 1 página de largura, altura automática, cabeçalho repetido", async () => {
  const wb = buildWorkbook(base, "2026-10-01", "2026-10-31", "E");
  const ws = wb.getWorksheet("Relatório")!;
  assert.equal(((ws as any).rowBreaks ?? []).length, 0); // o ExcelJS só grava <rowBreaks> a partir desta lista
  const ps = ws.pageSetup;
  assert.deepEqual([ps.paperSize, ps.orientation, ps.fitToPage, ps.fitToWidth, ps.fitToHeight, ps.printTitlesRow], [9, "portrait", true, 1, 0, "4:4"]);
});

test("título da empresa pode cair no fim da página: toda faixa de funcionário repete a empresa (SEM EMPRESA = faixa sem sufixo)", async () => {
  const ws = await ler(buildWorkbook(base, "2026-10-01", "2026-10-31", "E"));
  const faixas = linhas(ws).map((x) => String(x.getCell(1).value ?? "")).filter((v) => /—\s+RE /.test(v));
  assert.equal(faixas.length, agruparPorEmpresa(base).reduce((s, x) => s + x.grupos.length, 0));
  for (const b of agruparPorEmpresa(base)) for (const g of b.grupos)
    assert.ok(faixas.includes(`${g.nome}  —  RE ${g.re}${b.empresa ? `  —  ${b.empresa}` : ""}`), `${g.funcionarioId}`);
  assert.ok(faixas.includes("ÁLVARO  —  RE 16"));
});

test("filtros (status/funcionário/posto) aplicados antes do agrupamento: blocos só com o filtrado", async () => {
  for (const f of [{ status: "APROVADA" }, { nome: "josé" }, { posto: "P2" }]) {
    const items = filtrarRelatorio(base, f);
    const b = agruparPorEmpresa(items);
    assert.equal(b.reduce((s, x) => s + x.totais.total, 0), items.length, JSON.stringify(f));
    const ws = await ler(buildWorkbook(items, "2026-10-01", "2026-10-31", "E", new Set(), f.status ?? ""));
    assert.equal(linhas(ws).filter(ehData).length, items.length);
  }
  assert.deepEqual(agruparPorEmpresa(filtrarRelatorio(base, { nome: "josé" })).map((x) => x.empresa), [REM, SERV]); // empresa sem FT some
});

test("vazio: sem blocos, sem quebras", async () => {
  assert.deepEqual(agruparPorEmpresa([]), []);
  const wb = buildWorkbook([], "2026-10-01", "2026-10-31", "E");
  assert.equal(((wb.getWorksheet("Relatório") as any).rowBreaks ?? []).length, 0);
});
