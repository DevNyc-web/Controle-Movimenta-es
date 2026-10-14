// Filtro de status do relatório (tabela/totais/Excel) e filtro por data_ft nas Aprovações.
import { test } from "node:test";
import assert from "node:assert/strict";
import ExcelJS from "exceljs";
import { filtrarRelatorio, totaisGerais, agruparPorFuncionario, STATUS_FILTRO } from "../src/lib/relatorio.ts";
import { buildWorkbook } from "../src/lib/relatorio-excel.ts";
import { carregarPendentes } from "../src/lib/aprovacoes.ts";

let n = 0;
const ft = (fid: string, nome: string, data: string, status: string, over: Record<string, unknown> = {}): any => ({
  id: `id${String(++n).padStart(5, "0")}`, numero_ft: `FT-${n}`, funcionario_id: fid, data_ft: data, horas_trabalhadas: 12,
  valor_pago: 100, pagamento_em_folha: false, status, posto_falta: "P1", funcionario: { nome, re: fid, cargo: "Vigilante" }, ...over,
});
const STATUS = ["PENDENTE", "APROVADA", "NEGADA", "CANCELADA", "CANCELAMENTO_SOLICITADO"];
const base = [
  ...STATUS.map((s, k) => ft("j", "JOÃO", `2026-10-0${k + 1}`, s)),
  ft("m", "MARIA", "2026-10-02", "APROVADA", { posto_falta: "P2", funcionario: { nome: "MARIA", re: "m", cargo: "Porteiro" } }),
  ft("m", "MARIA", "2026-10-03", "NEGADA", { pagamento_em_folha: true }),
];

test("opções de status cobrem o enum; NEGADA é exibida como Recusada", () => {
  assert.deepEqual(STATUS_FILTRO.slice(1).map((o) => o.value).sort(), [...STATUS].sort());
  assert.equal(STATUS_FILTRO.find((o) => o.value === "NEGADA")!.label, "Recusada");
  assert.equal(STATUS_FILTRO[0].value, ""); // padrão = todos
});

test("'Todos os status' preserva o comportamento atual (nada removido)", () => {
  assert.deepEqual(filtrarRelatorio(base, {}), base);
  assert.deepEqual(filtrarRelatorio(base, { status: "" }), base);
});

test("cada status retorna só as FTs daquele status", () => {
  for (const s of STATUS) {
    const r = filtrarRelatorio(base, { status: s });
    assert.ok(r.length > 0, s);
    assert.ok(r.every((i) => i.status === s), s);
    assert.equal(r.length, base.filter((i) => i.status === s).length, s);
  }
});

test("status combinado com nome, cargo e posto (AND)", () => {
  assert.equal(filtrarRelatorio(base, { status: "APROVADA" }).length, 2);
  assert.deepEqual(filtrarRelatorio(base, { status: "APROVADA", nome: "mar" }).map((i) => i.funcionario_id), ["m"]);
  assert.equal(filtrarRelatorio(base, { status: "APROVADA", cargo: "Vigilante" }).length, 1);
  assert.equal(filtrarRelatorio(base, { status: "APROVADA", posto: "P2" }).length, 1);
  assert.equal(filtrarRelatorio(base, { status: "PENDENTE", nome: "maria" }).length, 0);
});

test("totais coerentes com os registros filtrados (folha fora do valor)", () => {
  const neg = filtrarRelatorio(base, { status: "NEGADA" });
  const t = totaisGerais(neg);
  assert.equal(t.total, 2);
  assert.equal(t.NEGADA, 2);
  assert.equal(t.APROVADA, 0);
  assert.equal(t.horas, 24);
  assert.equal(t.valor, 100); // a NEGADA em folha não soma
  assert.equal(t.valor, agruparPorFuncionario(neg).reduce((s, g) => s + g.valor, 0));
});

async function ler(items: any[], status = "") {
  const wb = buildWorkbook(items, "2026-10-01", "2026-10-31", "Emitido", new Set(), status);
  const back = new ExcelJS.Workbook();
  await back.xlsx.load(Buffer.from(await wb.xlsx.writeBuffer()));
  const ws = back.getWorksheet("Relatório")!;
  const rows: any[][] = [];
  ws.eachRow((r) => rows.push((r.values as any[]).slice(1)));
  return { ws, rows };
}

test("Excel usa exatamente os itens filtrados e indica o status no subtítulo", async () => {
  const items = filtrarRelatorio(base, { status: "NEGADA" });
  const { ws, rows } = await ler(items, "NEGADA");
  assert.equal(ws.getCell("A2").value, "Relatório Gerencial — Período: 01/10/2026 a 31/10/2026 — Status: Recusada");
  const dados = rows.filter((r) => /^\d\d\/\d\d\/\d{4}$/.test(String(r[0])));
  assert.equal(dados.length, items.length);
  assert.ok(dados.every((r) => r[9] === "NEGADA"));
  const geral = rows.find((r) => r[6] === "TOTAL GERAL")!;
  assert.equal(geral[7], 24);
  assert.equal(geral[8], 100);
  assert.equal(geral[9], "2 reg.");
});

test("Excel com 'Todos' mantém o subtítulo atual", async () => {
  const { ws, rows } = await ler(base);
  assert.equal(ws.getCell("A2").value, "Relatório Gerencial — Período: 01/10/2026 a 31/10/2026");
  assert.equal(rows.find((r) => r[6] === "TOTAL GERAL")![9], `${base.length} reg.`);
});

/* ---- Aprovações: cliente falso que avalia a consulta sobre um "banco" em memória ------------------------------
   `visivel` simula a RLS (janela do supervisor): linhas fora dela nunca saem, com ou sem filtro. */
function fakeClient(db: any[], visivel: (r: any) => boolean = () => true, maxRows = 1000) {
  const log: any[] = [];
  const client = {
    log,
    from(tabela: string) {
      const conds: ((r: any) => boolean)[] = [];
      const call: any = { tabela, filtros: [] as string[], orders: [] as string[] };
      log.push(call);
      const b: any = {
        select: () => b,
        eq: (c: string, v: any) => (call.filtros.push(`${c}=${v}`), conds.push((r) => r[c] === v), b),
        gte: (c: string, v: any) => (call.filtros.push(`${c}>=${v}`), conds.push((r) => r[c] >= v), b),
        lte: (c: string, v: any) => (call.filtros.push(`${c}<=${v}`), conds.push((r) => r[c] <= v), b),
        order: (c: string) => (call.orders.push(c), b),
        range: async (from: number, to: number) => {
          const rows = db.filter(visivel).filter((r) => conds.every((f) => f(r))).sort((a, b) => (a.data_lancamento + a.id < b.data_lancamento + b.id ? -1 : 1));
          return { data: rows.slice(from, Math.min(to + 1, from + maxRows)), error: null };
        },
      };
      return b;
    },
  };
  return client;
}

const pend = (id: string, data_ft: string, data_lancamento: string, status = "PENDENTE") => ({ id, data_ft, data_lancamento, created_at: data_lancamento, status });

test("aprovações: sem filtro devolve todas as pendentes, sem filtro de data", async () => {
  const db = [pend("a", "2026-10-01", "2026-09-30"), pend("b", "2026-12-01", "2026-10-01"), pend("c", "2026-10-02", "2026-10-01", "APROVADA")];
  const c = fakeClient(db);
  assert.deepEqual((await carregarPendentes(c)).map((r) => r.id), ["a", "b"]);
  assert.deepEqual(c.log[0].filtros, ["status=PENDENTE"]);
  assert.equal(c.log[0].tabela, "ft");
});

test("aprovações: filtra por data_ft (data futura), não pela data de lançamento", async () => {
  // lançada em 14/10/2026 para serviço em 21/10/2026
  const db = [pend("x", "2026-10-21", "2026-10-14T10:00:00Z"), pend("y", "2026-10-14", "2026-10-01T10:00:00Z")];
  const c = fakeClient(db);
  assert.deepEqual((await carregarPendentes(c, "2026-10-21", "2026-10-21")).map((r) => r.id), ["x"]);
  assert.deepEqual((await carregarPendentes(c, "2026-10-14", "2026-10-14")).map((r) => r.id), ["y"]);
  assert.ok(c.log.every((l: any) => l.filtros.every((f: string) => /^(status|data_ft)/.test(f))), "nunca filtra created_at/updated_at/data_lancamento");
});

test("aprovações: limites do período são inclusivos; só início ou só fim", async () => {
  const db = ["2026-10-19", "2026-10-20", "2026-10-25", "2026-10-26"].map((d, k) => pend(`p${k}`, d, `2026-10-0${k + 1}`));
  const c = fakeClient(db);
  assert.deepEqual((await carregarPendentes(c, "2026-10-20", "2026-10-25")).map((r) => r.data_ft), ["2026-10-20", "2026-10-25"]);
  assert.deepEqual((await carregarPendentes(c, "2026-10-25")).map((r) => r.data_ft), ["2026-10-25", "2026-10-26"]);
  assert.deepEqual((await carregarPendentes(c, "", "2026-10-19")).map((r) => r.data_ft), ["2026-10-19"]);
  assert.deepEqual(await carregarPendentes(c, "2026-10-26", "2026-10-20"), []); // invertido: vazio, sem erro
});

test("aprovações: considera todos os registros elegíveis além da 1ª página", async () => {
  const db = Array.from({ length: 2500 }, (_, k) => pend(`r${String(k).padStart(5, "0")}`, k % 2 ? "2026-11-05" : "2026-10-05", "2026-10-01"));
  const r = await carregarPendentes(fakeClient(db, () => true, 1000), "2026-11-01", "2026-11-30");
  assert.equal(r.length, 1250);
  assert.equal(new Set(r.map((x) => x.id)).size, 1250);
});

test("aprovações: filtro nunca amplia a visibilidade (RLS/janela continua valendo)", async () => {
  const db = [pend("dentro", "2026-10-15", "2026-10-01"), pend("fora", "2026-12-25", "2026-10-01")];
  const janela = (r: any) => r.data_ft <= "2026-10-21"; // supervisor: hoje+7
  const c = fakeClient(db, janela);
  assert.deepEqual((await carregarPendentes(c, "2026-12-01", "2026-12-31")).map((r) => r.id), []);
  const todos = (await carregarPendentes(c)).map((r) => r.id);
  const filtrado = (await carregarPendentes(c, "2026-10-01", "2026-12-31")).map((r) => r.id);
  assert.deepEqual(todos, ["dentro"]);
  assert.ok(filtrado.every((id) => todos.includes(id)));
});
