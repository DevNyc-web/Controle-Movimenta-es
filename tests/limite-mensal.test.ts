// Limite mensal: SINALIZAÇÃO (>4 no mês por funcionario_id + mês de data_ft), nunca bloqueio.
// Contagem: CANCELADA e NEGADA não contam; PENDENTE, APROVADA, CANCELAMENTO_SOLICITADO e folha contam.
import { test } from "node:test";
import assert from "node:assert/strict";
import ExcelJS from "exceljs";
import { agruparPorFuncionario, totaisGerais, LABEL_FOLHA, mesesExcedidos, mesesInteiros, lerTodas, linhaExcedeu, grupoExcedeu, chaveMes } from "../src/lib/relatorio.ts";
import { buildWorkbook } from "../src/lib/relatorio-excel.ts";

let n = 0;
const ftm = (fid: string, nome: string, data: string, over: { status?: string; folha?: boolean; valor?: number } = {}): any => ({
  id: `id${++n}`, numero_ft: `FT-${String(n).padStart(4, "0")}`, funcionario_id: fid, data_ft: data, horas_trabalhadas: 12,
  valor_pago: over.valor ?? 100, pagamento_em_folha: over.folha ?? false, status: over.status ?? "APROVADA",
  funcionario: { nome, re: fid, cargo: "Vigilante" },
});
const dias = (fid: string, nome: string, mes: string, qtd: number, over = {}) =>
  Array.from({ length: qtd }, (_, k) => ftm(fid, nome, `${mes}-${String(k + 1).padStart(2, "0")}`, over));

test("1 e 4 FTs = normal; 5, 6 e 7 = excedido", () => {
  assert.equal(mesesExcedidos(dias("j", "JOÃO", "2026-10", 1)).size, 0);
  assert.equal(mesesExcedidos(dias("j", "JOÃO", "2026-10", 4)).size, 0); // exatamente 4
  for (const q of [5, 6, 7]) assert.deepEqual([...mesesExcedidos(dias("j", "JOÃO", "2026-10", q))], [chaveMes("j", "2026-10-01")]);
});

test("mesmo nome com IDs diferentes: contagens independentes", () => {
  const exc = mesesExcedidos([...dias("a", "JOÃO", "2026-10", 5), ...dias("b", "JOÃO", "2026-10", 1)]);
  assert.ok(exc.has("a|2026-10"));
  assert.ok(!exc.has("b|2026-10"));
  assert.equal(mesesExcedidos([...dias("a", "JOÃO", "2026-10", 3), ...dias("b", "JOÃO", "2026-10", 3)]).size, 0); // 3+3 nunca vira 6
});

test("mês a mês: 4+4 = normal; 4 em setembro + 5 em outubro = só outubro", () => {
  assert.equal(mesesExcedidos([...dias("j", "JOÃO", "2026-09", 4), ...dias("j", "JOÃO", "2026-10", 4)]).size, 0);
  assert.deepEqual([...mesesExcedidos([...dias("j", "JOÃO", "2026-09", 4), ...dias("j", "JOÃO", "2026-10", 5)])], ["j|2026-10"]);
});

test("CANCELADA e NEGADA não contam; CANCELAMENTO_SOLICITADO conta; pagamento em folha conta para a quantidade", () => {
  const quatro = dias("j", "JOÃO", "2026-10", 4);
  assert.equal(mesesExcedidos([...quatro, ftm("j", "JOÃO", "2026-10-20", { status: "CANCELADA" })]).size, 0);
  assert.equal(mesesExcedidos([...quatro, ftm("j", "JOÃO", "2026-10-20", { status: "NEGADA" })]).size, 0);
  assert.equal(mesesExcedidos([...quatro, ftm("j", "JOÃO", "2026-10-20", { status: "CANCELAMENTO_SOLICITADO" })]).size, 1);
  assert.equal(mesesExcedidos([...quatro, ftm("j", "JOÃO", "2026-10-20", { status: "PENDENTE" })]).size, 1);
  assert.equal(mesesExcedidos([...quatro, ftm("j", "JOÃO", "2026-10-20", { folha: true })]).size, 1);
  // 5 FTs com uma cancelada = 4 válidas = normal
  assert.equal(mesesExcedidos([...quatro, ...dias("j", "JOÃO", "2026-10", 1, { status: "CANCELADA" }).map((x) => ({ ...x, data_ft: "2026-10-28" }))]).size, 0);
});

test("o mês vem da string de data_ft (sem fuso): virada de mês e de ano", () => {
  const out = ["2026-10-27", "2026-10-28", "2026-10-29", "2026-10-30", "2026-10-31"].map((d) => ftm("j", "JOÃO", d));
  const nov = ftm("j", "JOÃO", "2026-11-01");
  assert.deepEqual([...mesesExcedidos([...out, nov])], ["j|2026-10"]); // 5 em outubro; 1 em novembro
  const dez = ["2026-12-30", "2026-12-31"].map((d) => ftm("j", "JOÃO", d));
  const jan = ["2027-01-01", "2027-01-02", "2027-01-03"].map((d) => ftm("j", "JOÃO", d));
  assert.equal(mesesExcedidos([...dez, ...jan]).size, 0); // 5 no total, mas 2 + 3 em meses diferentes
});

test("meses inteiros do período (independe do recorte e do fuso)", () => {
  assert.deepEqual(mesesInteiros("2026-10-15", "2026-10-31"), { inicio: "2026-10-01", fim: "2026-10-31" });
  assert.deepEqual(mesesInteiros("2026-09-15", "2026-10-10"), { inicio: "2026-09-01", fim: "2026-10-31" });
  assert.deepEqual(mesesInteiros("2028-02-10", "2028-02-11"), { inicio: "2028-02-01", fim: "2028-02-29" }); // bissexto
  assert.deepEqual(mesesInteiros("2026-02-10", "2026-02-11"), { inicio: "2026-02-01", fim: "2026-02-28" });
  assert.deepEqual(mesesInteiros("2026-12-05", "2026-12-06"), { inicio: "2026-12-01", fim: "2026-12-31" });
  assert.deepEqual(mesesInteiros("2026-11-30", "2026-11-30"), { inicio: "2026-11-01", fim: "2026-11-30" });
});

test("a contagem usa o mês inteiro, não só as linhas exibidas", () => {
  const mes = dias("j", "JOÃO", "2026-10", 5); // 01..05
  const exibidas = mes.filter((x) => x.data_ft >= "2026-10-05"); // relatório 05..31, ou filtro de posto, mostra 1 linha
  assert.equal(exibidas.length, 1);
  assert.ok(linhaExcedeu(exibidas[0], mesesExcedidos(mes))); // contagem independente: continua excedido
  assert.equal(mesesExcedidos(exibidas).size, 0); // contar só o exibido subestimaria (é o que NÃO fazemos)
});

test("cabeçalho vermelho se algum mês excedeu; linhas só no mês excedido", () => {
  const rows = [...dias("j", "JOÃO", "2026-09", 4), ...dias("j", "JOÃO", "2026-10", 5), ...dias("m", "MARIA", "2026-10", 3)];
  const exc = mesesExcedidos(rows);
  const g = agruparPorFuncionario(rows);
  assert.equal(grupoExcedeu(g.find((x) => x.funcionarioId === "j")!, exc), true);
  assert.equal(grupoExcedeu(g.find((x) => x.funcionarioId === "m")!, exc), false);
  assert.deepEqual(g.find((x) => x.funcionarioId === "j")!.items.map((i) => linhaExcedeu(i, exc)), [false, false, false, false, true, true, true, true, true]);
});

async function planilha(rows: any[], exc: ReadonlySet<string>) {
  const wb = buildWorkbook(rows, "2026-09-01", "2026-10-31", "Emitido", exc);
  const re = new ExcelJS.Workbook();
  await re.xlsx.load((await wb.xlsx.writeBuffer()) as ArrayBuffer);
  return re.getWorksheet("Relatório")!;
}
const cor = (c: ExcelJS.Cell) => (c.font?.color as any)?.argb as string | undefined;
const VERMELHO = "FFC00000";

test("Excel: cabeçalho e linhas do mês excedido em vermelho; o resto intacto", async () => {
  const rows = [...dias("j", "JOÃO", "2026-09", 4), ...dias("j", "JOÃO", "2026-10", 5), ...dias("m", "MARIA", "2026-10", 3)];
  const ws = await planilha(rows, mesesExcedidos(rows));
  const cab: Record<string, string | undefined> = {};
  const linhas: [string, string, string | undefined][] = [];
  ws.eachRow((row) => {
    const a = String(row.getCell(1).value ?? "");
    if (/—\s+RE /.test(a)) cab[a.split(" ")[0]] = cor(row.getCell(1));
    if (/^\d\d\/\d\d\/\d{4}$/.test(a)) linhas.push([String(row.getCell(2).value), a.slice(3), cor(row.getCell(2))]);
  });
  assert.equal(cab["JOÃO"], VERMELHO);
  assert.notEqual(cab["MARIA"], VERMELHO);
  assert.deepEqual(linhas.filter((l) => l[0] === "JOÃO" && l[2] === VERMELHO).map((l) => l[1]), Array(5).fill("10/2026"));
  assert.ok(linhas.filter((l) => l[1] === "09/2026").every((l) => l[2] !== VERMELHO));
  assert.ok(linhas.filter((l) => l[0] === "MARIA").every((l) => l[2] !== VERMELHO));
});

test("Excel: 4 em setembro + 4 em outubro e exatamente 4 não ficam vermelhos", async () => {
  const rows = [...dias("j", "JOÃO", "2026-09", 4), ...dias("j", "JOÃO", "2026-10", 4)];
  const ws = await planilha(rows, mesesExcedidos(rows));
  let vermelhos = 0;
  ws.eachRow((row) => row.eachCell((c) => { if (cor(c) === VERMELHO) vermelhos++; }));
  assert.equal(vermelhos, 0);
});

test("sinalizar não altera valores, subtotais, total geral nem a regra financeira da folha (só a cor)", async () => {
  const rows = [...dias("j", "JOÃO", "2026-10", 5), ftm("j", "JOÃO", "2026-10-20", { folha: true, valor: 150 }), ...dias("m", "MARIA", "2026-10", 2)];
  const valores = async (exc: ReadonlySet<string>) => {
    const ws = await planilha(rows, exc);
    const out: unknown[][] = [];
    ws.eachRow({ includeEmpty: true }, (r) => out.push((r.values as unknown[]).map((v) => (typeof v === "object" && v !== null ? JSON.stringify(v) : v))));
    return out;
  };
  assert.deepEqual(await valores(mesesExcedidos(rows)), await valores(new Set())); // mesmas células e números
  const j = agruparPorFuncionario(rows).find((x) => x.funcionarioId === "j")!;
  assert.equal(j.valor, 500); // 5 x 100; a FT em folha (150) continua fora do valor...
  assert.equal(j.items.length, 6); // ...mas conta na quantidade
  assert.equal(totaisGerais(rows).valor, 700);
  const ws = await planilha(rows, mesesExcedidos(rows));
  let folha = 0;
  ws.eachRow((r) => { if (r.getCell(9).value === LABEL_FOLHA) folha++; });
  assert.equal(folha, 1);
  const sub = new Map<string, unknown>();
  ws.eachRow((r) => { const l = String(r.getCell(7).value ?? ""); if (l.startsWith("TOTAL ")) sub.set(l, r.getCell(9).value); });
  assert.deepEqual([...sub], [["TOTAL JOÃO", 500], ["TOTAL MARIA", 200], ["TOTAL GERAL", 700]]);
});

test("paginação: lê tudo, sem repetir nem pular, mesmo se o servidor limitar a resposta abaixo do tamanho pedido", async () => {
  const dados = Array.from({ length: 2500 }, (_, k) => k);
  const servidor = (cap: number) => async (from: number, to: number) => dados.slice(from, Math.min(to + 1, from + cap));
  for (const cap of [1000, 500, 999, 2500]) { // 500/999 = max_rows do PostgREST menor que a página pedida
    const lidas = await lerTodas(servidor(cap), 1000);
    assert.deepEqual(lidas, dados, `cap ${cap}`);
  }
  assert.deepEqual(await lerTodas(servidor(1000), 1000), dados);
  const exato = dados.slice(0, 2000); // múltiplo exato da página: termina na página vazia
  assert.deepEqual(await lerTodas(async (f, t) => exato.slice(f, t + 1), 1000), exato);
  assert.deepEqual(await lerTodas(async () => [], 1000), []);
});
