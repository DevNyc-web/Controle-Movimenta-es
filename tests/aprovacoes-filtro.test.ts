// Persistência do filtro de data_ft da tela de Aprovações (localStorage, isolado por usuário).
import { test } from "node:test";
import assert from "node:assert/strict";
import { lerFiltroAprovacoes, salvarFiltroAprovacoes } from "../src/lib/aprovacoes.ts";

const fakeStorage = () => {
  const m = new Map<string, string>();
  return {
    m,
    getItem: (k: string) => m.get(k) ?? null,
    setItem: (k: string, v: string) => void m.set(k, v),
    removeItem: (k: string) => void m.delete(k),
  };
};
const VAZIO = { inicio: "", fim: "" };

test("sem filtro salvo = sem filtro (lista completa)", () => {
  assert.deepEqual(lerFiltroAprovacoes("u1", fakeStorage()), VAZIO);
});

test("salva e restaura o período", () => {
  const s = fakeStorage();
  salvarFiltroAprovacoes("u1", "2026-10-01", "2026-10-15", s);
  assert.deepEqual(lerFiltroAprovacoes("u1", s), { inicio: "2026-10-01", fim: "2026-10-15" });
});

test("datas parciais: preserva só a data preenchida", () => {
  const s = fakeStorage();
  salvarFiltroAprovacoes("u1", "2026-10-01", "", s);
  assert.deepEqual(lerFiltroAprovacoes("u1", s), { inicio: "2026-10-01", fim: "" });
  salvarFiltroAprovacoes("u1", "", "2026-10-15", s);
  assert.deepEqual(lerFiltroAprovacoes("u1", s), { inicio: "", fim: "2026-10-15" });
});

test("Limpar filtros apaga o valor persistido", () => {
  const s = fakeStorage();
  salvarFiltroAprovacoes("u1", "2026-10-01", "2026-10-15", s);
  salvarFiltroAprovacoes("u1", "", "", s);
  assert.equal(s.m.size, 0);
  assert.deepEqual(lerFiltroAprovacoes("u1", s), VAZIO);
});

test("isolado por usuário no mesmo navegador", () => {
  const s = fakeStorage();
  salvarFiltroAprovacoes("u1", "2026-10-01", "2026-10-15", s);
  salvarFiltroAprovacoes("u2", "2026-09-01", "", s);
  assert.deepEqual(lerFiltroAprovacoes("u1", s), { inicio: "2026-10-01", fim: "2026-10-15" });
  assert.deepEqual(lerFiltroAprovacoes("u2", s), { inicio: "2026-09-01", fim: "" });
  assert.deepEqual(lerFiltroAprovacoes("u3", s), VAZIO);
  salvarFiltroAprovacoes("u1", "", "", s); // limpar de um não afeta o outro
  assert.deepEqual(lerFiltroAprovacoes("u2", s), { inicio: "2026-09-01", fim: "" });
});

test("guarda só as datas (nada das FTs)", () => {
  const s = fakeStorage();
  salvarFiltroAprovacoes("u1", "2026-10-01", "2026-10-15", s);
  assert.deepEqual([...s.m.values()].map((v) => JSON.parse(v)), [{ inicio: "2026-10-01", fim: "2026-10-15" }]);
});

test("dados corrompidos/inválidos viram filtro vazio, sem lançar", () => {
  const s = fakeStorage();
  const k = () => [...s.m.keys()][0];
  salvarFiltroAprovacoes("u1", "2026-10-01", "", s);
  for (const lixo of ["{não é json", "null", "42", '"2026-10-01"', "[]", '{"inicio":123,"fim":{}}', '{"inicio":"ontem","fim":"2026-99-99"}', '{"inicio":"2026-10-01T00:00","fim":"<script>"}']) {
    s.m.set(k(), lixo);
    assert.deepEqual(lerFiltroAprovacoes("u1", s), VAZIO, lixo);
  }
  s.m.set(k(), '{"inicio":"lixo","fim":"2026-10-15"}'); // campo válido sobrevive ao inválido
  assert.deepEqual(lerFiltroAprovacoes("u1", s), { inicio: "", fim: "2026-10-15" });
});

test("storage indisponível (modo privado/bloqueado) não quebra a tela", () => {
  const quebrado = { getItem() { throw new Error("SecurityError"); }, setItem() { throw new Error("QuotaExceeded"); }, removeItem() { throw new Error("x"); } };
  assert.deepEqual(lerFiltroAprovacoes("u1", quebrado), VAZIO);
  assert.doesNotThrow(() => salvarFiltroAprovacoes("u1", "2026-10-01", "", quebrado));
  assert.doesNotThrow(() => salvarFiltroAprovacoes("u1", "", "", quebrado));
  assert.deepEqual(lerFiltroAprovacoes("u1"), VAZIO); // node: sem localStorage global
});
