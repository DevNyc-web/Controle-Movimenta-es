import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  FILTROS_VAZIOS, LIMITE_CSV, LOTE_CSV, TAMANHO_PAGINA, coletarTodas, contemTexto, juntarPaginas, paramsPagina, periodoInvalido, proximoCursor,
  type Cursor,
} from "../src/lib/auditoria.ts";

type R = { id: string; created_at: string };

// Servidor falso com a MESMA regra de auditoria_pagina: created_at DESC, id DESC; cursor (created_at, id) exclusivo.
// created_at com microssegundos (texto da API) e muitos empates no mesmo instante.
function servidor(n: number, empatados: number) {
  const dados: R[] = Array.from({ length: n }, (_, i) => ({
    id: `00000000-0000-4000-8000-${String((i * 7919) % 1000003).padStart(12, "0")}`,
    created_at: i < empatados ? "2026-06-01T12:00:00.123456+00:00" : `2026-01-01T00:${String(Math.floor(i / 60) % 60).padStart(2, "0")}:${String(i % 60).padStart(2, "0")}.${String(i).padStart(6, "0")}+00:00`,
  }));
  const ordenados = [...dados].sort((a, b) => (a.created_at === b.created_at ? (a.id < b.id ? 1 : -1) : a.created_at < b.created_at ? 1 : -1));
  const chamadas: { cursor: Cursor; tamanho: number }[] = [];
  const buscar = async (cursor: Cursor, tamanho: number) => {
    chamadas.push({ cursor, tamanho });
    const restantes = cursor ? ordenados.filter((r) => r.created_at < cursor.em || (r.created_at === cursor.em && r.id < cursor.id)) : ordenados;
    return restantes.slice(0, tamanho);
  };
  return { dados, ordenados, buscar, chamadas };
}

test("paramsPagina: filtros vazios viram null; cursor e tamanho repassados", () => {
  assert.deepEqual(paramsPagina(FILTROS_VAZIOS, null, 100), {
    _de: null, _ate: null, _user_id: null, _role: null, _action: null, _entity_type: null, _antes_em: null, _antes_id: null, _tamanho: 100,
  });
  const p = paramsPagina({ de: "2026-03-01", ate: " 2026-03-31 ", userId: "u1", role: "gestor", action: "UPDATE", entityType: "ft" },
    { em: "2026-03-10T03:00:00.000001+00:00", id: "x" }, 500);
  assert.deepEqual(p, { _de: "2026-03-01", _ate: "2026-03-31", _user_id: "u1", _role: "gestor", _action: "UPDATE", _entity_type: "ft",
    _antes_em: "2026-03-10T03:00:00.000001+00:00", _antes_id: "x", _tamanho: 500 });
});

test("periodoInvalido só quando início > fim", () => {
  assert.equal(periodoInvalido({ ...FILTROS_VAZIOS, de: "2026-03-10", ate: "2026-03-09" }), true);
  assert.equal(periodoInvalido({ ...FILTROS_VAZIOS, de: "2026-03-10", ate: "2026-03-10" }), false);
  assert.equal(periodoInvalido({ ...FILTROS_VAZIOS, de: "2026-03-10" }), false);
});

test("proximoCursor: fim quando a página vem incompleta; mantém created_at como texto (microssegundos)", () => {
  assert.equal(proximoCursor([{ id: "a", created_at: "t" }], 2), null);
  assert.equal(proximoCursor([], 100), null);
  assert.deepEqual(proximoCursor([{ id: "a", created_at: "t1" }, { id: "b", created_at: "2026-06-01T12:00:00.123456+00:00" }], 2),
    { em: "2026-06-01T12:00:00.123456+00:00", id: "b" });
});

test("juntarPaginas não repete registros", () => {
  assert.deepEqual(juntarPaginas([{ id: "a" }, { id: "b" }], [{ id: "b" }, { id: "c" }]).map((x) => x.id), ["a", "b", "c"]);
});

test("percorrer páginas de 100 (tela): todos os registros uma vez, na ordem, apesar de 1250 empates", async () => {
  const s = servidor(2600, 1250);
  let lidos: R[] = []; let cursor: Cursor = null; let paginas = 0;
  do {
    const p = await s.buscar(cursor, TAMANHO_PAGINA);
    lidos = juntarPaginas(lidos, p); cursor = proximoCursor(p, TAMANHO_PAGINA); paginas++;
  } while (cursor);
  assert.equal(lidos.length, 2600);
  assert.equal(new Set(lidos.map((r) => r.id)).size, 2600);
  assert.deepEqual(lidos.map((r) => r.id), s.ordenados.map((r) => r.id));
  assert.equal(paginas, 27); // 26 cheias + 1 vazia que confirma o fim
});

test("CSV: coleta todas as páginas em lotes de 500 abaixo do limite", async () => {
  const s = servidor(2600, 1250);
  const progresso: number[] = [];
  const r = await coletarTodas((c) => s.buscar(c, LOTE_CSV), { progresso: (n) => progresso.push(n) });
  assert.equal(r.excedeu, false);
  if (!r.excedeu) assert.deepEqual(r.linhas.map((x) => x.id), s.ordenados.map((x) => x.id));
  assert.ok(s.chamadas.every((c) => c.tamanho === LOTE_CSV && c.tamanho < 1000));
  assert.deepEqual(progresso, [500, 1000, 1500, 2000, 2500, 2600]);
});

test("CSV: passou do limite → excedeu, SEM linhas (nunca um CSV silenciosamente incompleto)", async () => {
  const s = servidor(1201, 300);
  const r = await coletarTodas((c) => s.buscar(c, 100), { lote: 100, limite: 1200 });
  assert.equal(r.excedeu, true);
  assert.ok(!("linhas" in r));
});

test("CSV: exatamente no limite não é excesso", async () => {
  const s = servidor(1200, 300);
  const r = await coletarTodas((c) => s.buscar(c, 100), { lote: 100, limite: 1200 });
  assert.equal(r.excedeu, false);
  if (!r.excedeu) assert.equal(r.linhas.length, 1200);
});

test("CSV: erro no meio → rejeita (nenhum arquivo parcial)", async () => {
  let n = 0;
  await assert.rejects(coletarTodas(async () => { if (++n === 3) throw new Error("rede"); return Array.from({ length: 10 }, (_, i) => ({ id: `${n}-${i}`, created_at: "t" })); }, { lote: 10 }));
});

test("limite do CSV é 20.000 e o lote cabe na API", () => {
  assert.equal(LIMITE_CSV, 20000);
  assert.ok(LOTE_CSV <= 500 && TAMANHO_PAGINA === 100);
});

test("pesquisa local: só texto já carregado, sem diferenciar maiúsculas", () => {
  assert.equal(contemTexto(["Criou usuário", null], "  usuário "), true);
  assert.equal(contemTexto(["***.001.013-**"], "61300101334"), false); // CPF mascarado não é encontrado pelo número
  assert.equal(contemTexto(["x"], ""), true);
});

test("tela: filtros no servidor reiniciam o cursor; pesquisa local explicada; CSV excedido não gera arquivo", () => {
  const s = readFileSync("src/routes/_app.auditoria.tsx", "utf8");
  assert.doesNotMatch(s, /auditoria_listar|from\("audit_logs"\)/);
  assert.match(s, /setLogs\(\[\]\); setCursor\(null\);/);
  assert.match(s, /\}, \[isGestor, filtros, invalido\]\);/);
  assert.match(s, /buscarPagina\(filtros, null, TAMANHO_PAGINA\)/);
  assert.match(s, /A pesquisa de texto vale só para os/);
  const csv = s.slice(s.indexOf("async function exportCsv"), s.indexOf("return (", s.indexOf("async function exportCsv")));
  assert.ok(csv.indexOf("if (r.excedeu)") > 0 && csv.indexOf("if (r.excedeu)") < csv.indexOf("new Blob"), "excesso verificado antes de gerar o arquivo");
  assert.match(csv, /if \(r\.excedeu\) \{\s*toast\.error\(`[^`]*Nenhum arquivo foi gerado[^`]*`[^;]*;\s*return;/);
  assert.match(s, /n !== consulta\.current/); // resposta de filtro antigo é descartada
});
