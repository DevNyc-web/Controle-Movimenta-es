// Empresa do funcionário (cadastro, telas, Excel) e "Lançado por" nos detalhes da FT.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import ExcelJS from "exceljs";
import { EMPRESAS, normalizarEmpresa } from "../src/lib/empresas.ts";
import { agruparPorFuncionario } from "../src/lib/relatorio.ts";
import { buildWorkbook } from "../src/lib/relatorio-excel.ts";

const src = (p: string) => readFileSync(p, "utf8").replace(/\r\n/g, "\n"); // LF ou CRLF (autocrlf no Windows)

test("normalizarEmpresa: só empresas conhecidas, tolerante a espaço/acento/caixa", () => {
  assert.equal(normalizarEmpresa("MC SERVICOS PATRIMONIAIS EIRELI "), "MC SERVICOS PATRIMONIAIS EIRELI");
  assert.equal(normalizarEmpresa("mc  soluções e serviços ltda"), "MC SOLUCOES E SERVICOS LTDA");
  assert.equal(normalizarEmpresa("MC REMOTA LTDA"), "MC REMOTA LTDA");
  for (const lixo of ["", "Nome", "Empregados", "Funcionarios", "MC REMOTA", null, undefined]) assert.equal(normalizarEmpresa(lixo), null, String(lixo));
  assert.equal(new Set(EMPRESAS).size, 8);
  for (const e of EMPRESAS) assert.equal(normalizarEmpresa(e), e);
});

const ft = (fid: string, empresa: string | null | undefined, data: string): any => ({
  id: `${fid}-${data}`, numero_ft: `FT-${fid}-${data}`, funcionario_id: fid, data_ft: data, horas_trabalhadas: 12, valor_pago: 200,
  pagamento_em_folha: false, status: "APROVADA", funcionario: { nome: `NOME ${fid}`, re: "202", cargo: "Vigilante", empresa },
});

test("grupo do relatório carrega a empresa; mesmo RE em empresas diferentes = grupos separados", () => {
  const g = agruparPorFuncionario([ft("a", "MC REMOTA LTDA", "2026-10-01"), ft("b", "MC SERVICOS E PORTARIA EIRELI", "2026-10-02"), ft("c", undefined, "2026-10-03")]);
  assert.deepEqual(g.map((x) => [x.funcionarioId, x.re, x.empresa]), [["a", "202", "MC REMOTA LTDA"], ["b", "202", "MC SERVICOS E PORTARIA EIRELI"], ["c", "202", null]]);
});

test("Excel: empresa só na faixa do funcionário; 10 colunas e totais intactos; sem empresa = faixa antiga", async () => {
  const items = [ft("a", "MC REMOTA LTDA", "2026-10-01"), ft("a", "MC REMOTA LTDA", "2026-10-02"), ft("c", null, "2026-10-03")];
  const wb = buildWorkbook(items, "2026-10-01", "2026-10-31", "Emitido em X");
  const back = new ExcelJS.Workbook();
  await back.xlsx.load(Buffer.from(await wb.xlsx.writeBuffer()));
  const ws = back.getWorksheet("Relatório")!;
  const col1 = (ws.getColumn(1).values as unknown[]).map(String);
  assert.ok(col1.includes("NOME a  —  RE 202  —  MC REMOTA LTDA"));
  assert.ok(col1.includes("NOME c  —  RE 202"));
  assert.equal((ws.getRow(4).values as unknown[]).slice(1).length, 10);
  assert.equal(ws.columnCount, 10);
  const total = ws.getRows(1, ws.rowCount)!.find((r) => r.getCell(7).value === "TOTAL GERAL")!;
  assert.deepEqual([total.getCell(8).value, total.getCell(9).value, total.getCell(10).value], [36, 600, "3 reg."]);
});

test("telas buscam e exibem empresa", () => {
  const casos: [string, RegExp[]][] = [
    ["src/routes/_app.ft.index.tsx", [/fkey\(nome, cargo, re, empresa\)/, /funcionario\.empresa/]],
    ["src/routes/_app.ft.$id.tsx", [/label="Empresa"/, /faltante_id_fkey\(nome, re, empresa\)/]],
    ["src/lib/aprovacoes.ts", [/fkey\(nome, cargo, re, empresa\)/]],
    ["src/routes/_app.aprovacoes.tsx", [/fkey\(nome, re, empresa\)\)/, /f\.funcionario\?\.empresa/, /s\.ft\.funcionario\.empresa/]],
    ["src/routes/_app.historico.tsx", [/fkey\(nome, re, empresa\)/, /f\.funcionario\.empresa/]],
    ["src/routes/_app.index.tsx", [/fkey\(nome, cargo, empresa\)/, /r\.funcionario\?\.empresa/]],
    ["src/routes/_app.relatorios.tsx", [/cargo, empresa\)/, /g\.empresa/]],
    ["src/components/FuncionarioPicker.tsx", [/select\("id, nome, re, empresa"\)/, /f\.empresa/, /selected\.empresa/]],
    ["src/routes/_app.funcionarios.index.tsx", [/<Th>Empresa<\/Th>/, /f\.empresa/]],
    ["src/components/FuncionarioForm.tsx", [/label="Empresa"/, /empresa: form\.empresa \|\| null/]],
  ];
  for (const [arq, res] of casos) for (const re of res) assert.match(src(arq), re, `${arq}: ${re}`);
});

test("importador grava só empresa reconhecida e nunca o rótulo de origem", () => {
  const imp = src("src/routes/_app.funcionarios.importar.tsx");
  assert.match(imp, /empresa: normalizarEmpresa\(empresa\)/);
  assert.match(imp, /\(\{ cargo_original, empresa_origem, \.\.\.rest \}\) => rest/); // empresa_origem segue fora do insert
  assert.match(imp, /\.insert\(chunk/); // continua insert (sem upsert que sobrescreveria cadastros)
});

test("migration de empresa é só aditiva", () => {
  const sql = src("supabase/migrations/20261021120000_funcionarios_empresa.sql").replace(/--.*$/gm, "").trim();
  assert.equal(sql, "ALTER TABLE public.funcionarios ADD COLUMN IF NOT EXISTS empresa TEXT;");
});

test("backfill: 788 IDs válidos e únicos, exceções fora, só preenche empresa vazia, nunca toca ft", () => {
  const bf = src("supabase/backfill/funcionarios_empresa.sql");
  const codigo = bf.replace(/--.*$/gm, "");
  const ids = [...codigo.matchAll(/'([^']{36})'/g)].map((m) => m[1]);
  assert.equal(ids.length, 788);
  assert.equal(new Set(ids).size, 788);
  for (const id of ids) assert.match(id, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
  // As 9 exceções (sem CPF, duplicado sem CPF e fictícios) não podem estar na lista
  for (const exc of [
    "f964e15d-c9fb-4075-a965-1502802c685c", "4167b450-1f15-415c-a2bd-3a7764e480e3", "10de6d0f-1d51-4ad8-b608-67c167a50c91",
    "ab1239ab-e174-4290-80ab-7bec0b9160a4", "7e520769-afd4-4462-9085-f7e5158dc848", "80c77973-22f4-440d-9d1f-fc70b53f6f50",
    "ba45b13c-52f5-40e2-97ba-16b16a8a0216", "1c27af0b-5c99-49a8-bec1-1c4816c7720c", "b0dfac58-6833-4cc4-91af-d49e94102b9b",
  ]) assert.ok(!ids.includes(exc), exc);
  // Só as 8 empresas conhecidas
  for (const [, e] of codigo.matchAll(/\]::uuid\[\]\), '([^']+)'/g)) assert.ok((EMPRESAS as readonly string[]).includes(e), e);
  // Escreve apenas funcionarios.empresa, só onde está vazia; nenhuma escrita em ft/histórico/vínculos
  assert.deepEqual([...codigo.matchAll(/\b(UPDATE|DELETE|INSERT INTO|ALTER|DROP|TRUNCATE)\s+([\w.]+)/gi)].map((m) => `${m[1].toUpperCase()} ${m[2]}`),
    ["INSERT INTO _empresa_backfill", "UPDATE public.funcionarios"]);
  assert.match(codigo, /SET empresa = b\.empresa\s+FROM _empresa_backfill b\s+WHERE f\.id = b\.id\s+AND f\.empresa IS NULL;/);
  assert.doesNotMatch(codigo, /public\.ft\b|ft_historico|valor_pago|pagamento_em_folha|funcionario_id|\bre\s*=/);
  for (const guarda of ["IF n <> 788", "não existem mais", "sem CPF", "já têm empresa diferente"]) assert.ok(codigo.includes(guarda), guarda);
  // Documentação coerente: 560 + 128 + 100 = 788; transferências 126 + 1 + 1 = 128
  assert.match(bf, /788 atualizados \/ 9 permanecem NULL \(797 no total\)/);
  assert.match(bf, /560 pelo consolidado/);
  assert.match(bf, /128 transferidos: .*\(126 para MC REMOTA \+ 1 PATRIMONIAIS→PORTARIA/);
  assert.match(bf, /1 PORTARIA→FACILIT/);
  assert.match(bf, /100 só na Relação de maio/);
});

test("Lançado por: usa lancado_por via RLS do usuário e nunca o aprovador", () => {
  const fn = src("src/lib/ft.functions.ts");
  assert.match(fn, /context\.supabase\.from\("ft"\)\.select\("lancado_por"\)\.eq\("id", data\.ftId\)/); // visibilidade = RLS do usuário
  assert.match(fn, /supabaseAdmin\.from\("profiles"\)\.select\("nome"\)\.eq\("id", ft\.lancado_por\)/); // só o nome
  assert.match(fn, /requireSupabaseAuth/);
  assert.doesNotMatch(fn, /aprovado_por|alterado_por|\.update\(|\.insert\(|\.delete\(/);
  assert.ok(fn.indexOf('from("ft")') < fn.indexOf("supabaseAdmin.from"), "FT lida (RLS) antes da service role");

  const det = src("src/routes/_app.ft.$id.tsx");
  assert.match(det, /label="Lançado por" value=\{lancador === undefined \? "Carregando\.\.\." : lancador \?\? "Não identificado"\}/);
  assert.match(det, /label="Data do lançamento" value=\{format\(new Date\(ft\.created_at\), "dd\/MM\/yyyy HH:mm"\)\}/);
  assert.match(det, /\.catch\(\(\) => \{ if \(vivo\) setLancador\(null\); \}\)/);
});
