// Empresa do funcionário (cadastro, telas, Excel) e "Lançado por" nos detalhes da FT.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import ExcelJS from "exceljs";
import { EMPRESAS, normalizarEmpresa } from "../src/lib/empresas.ts";
import { agruparPorFuncionario } from "../src/lib/relatorio.ts";
import { buildWorkbook } from "../src/lib/relatorio-excel.ts";
import { validarBackfillEmpresa } from "./validar-backfill-empresa.ts";

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

test("Excel: empresa vira bloco e continua na faixa do funcionário; 10 colunas + Observações e totais intactos", async () => {
  const items = [ft("a", "MC REMOTA LTDA", "2026-10-01"), ft("a", "MC REMOTA LTDA", "2026-10-02"), ft("c", null, "2026-10-03")];
  const wb = buildWorkbook(items, "2026-10-01", "2026-10-31", "Emitido em X");
  const back = new ExcelJS.Workbook();
  await back.xlsx.load(Buffer.from(await wb.xlsx.writeBuffer()));
  const ws = back.getWorksheet("Relatório")!;
  const col1 = (ws.getColumn(1).values as unknown[]).map(String);
  for (const v of ["MC REMOTA LTDA", "NOME a  —  RE 202  —  MC REMOTA LTDA", "SEM EMPRESA INFORMADA", "NOME c  —  RE 202"]) assert.ok(col1.includes(v), v);
  assert.ok(col1.indexOf("NOME a  —  RE 202  —  MC REMOTA LTDA") < col1.indexOf("SEM EMPRESA INFORMADA"));
  assert.equal((ws.getRow(4).values as unknown[]).slice(1).length, 11);
  assert.equal(ws.columnCount, 11); // 10 originais + Observações
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

test("backfill (fixture fictícia): IDs válidos e únicos, exceções fora, só preenche empresa vazia, nunca toca ft", () => {
  // O backfill real não é versionado (IDs de funcionários; repositório público). O mesmo validador roda nele localmente.
  const fx = src("tests/fixtures/backfill-empresa-ficticio.sql");
  const EXC = ["00000000-0000-4000-8000-0000000000e1", "00000000-0000-4000-8000-0000000000e2"]; // exceções fictícias
  assert.equal(validarBackfillEmpresa(fx, { total: 5, excecoes: EXC }).length, 5);

  // O validador precisa reprovar cada violação (senão não está validando nada)
  const reprova = (sql: string, total = 5) => assert.throws(() => validarBackfillEmpresa(sql, { total, excecoes: EXC }));
  reprova(fx, 6); // contagem diferente da esperada
  reprova(fx.replace("000000000002'", "000000000001'")); // ID repetido
  reprova(fx.replace("00000000-0000-4000-8000-000000000005", "nao-e-uuid-0000-4000-8000-000000000005")); // ID inválido
  reprova(fx.replace("00000000-0000-4000-8000-000000000005", EXC[0])); // exceção na lista
  reprova(fx.replace("'MC REMOTA LTDA'", "'EMPRESA INVENTADA'")); // empresa desconhecida
  reprova(fx.replace("   AND f.empresa IS NULL;", ";")); // sobrescreveria empresa preenchida
  reprova(fx.replace("COMMIT;", "UPDATE public.ft SET status = 'APROVADA';\nCOMMIT;")); // escrita em ft
  reprova(fx.replace("COMMIT;", "DELETE FROM public.funcionarios WHERE cpf IS NULL;\nCOMMIT;")); // apagaria cadastro
  reprova(fx.replace("SET empresa = b.empresa", "SET empresa = b.empresa, re = '1'")); // alteraria RE
  reprova(fx.replace("IF n <> 5 THEN RAISE EXCEPTION 'Backfill: esperado", "IF false THEN RAISE EXCEPTION 'Backfill: esperado")); // sem guarda de contagem
  reprova(fx.replace("já têm empresa diferente", "x")); // sem guarda de sobrescrita
  reprova(fx.replace(/^BEGIN;$/m, "")); // sem transação
});

test("backfill real fica fora do Git", () => {
  assert.match(src(".gitignore"), /^\/supabase\/backfill\/$/m);
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
