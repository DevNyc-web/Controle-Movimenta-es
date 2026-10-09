import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { ESCALAS, ESCALAS_HORAS } from "../src/lib/escalas.ts";
import { MOTIVOS } from "../src/lib/motivos.ts";
import { POSTOS_FALTA } from "../src/lib/postos.ts";

test("escalas antigas intactas e novas com horas integrais", () => {
  for (const [e, h] of Object.entries({ "06x18": 12, "18x06": 12, "07x19": 12, "19x07": 12, "08x18": 10 })) assert.equal(ESCALAS_HORAS[e], h);
  assert.equal(ESCALAS_HORAS["Horário das 06h às 16h"], 10);
  assert.equal(ESCALAS_HORAS["Horário das 08h às 16h"], 8);
  assert.equal(ESCALAS_HORAS["Horário das 22h às 06h"], 8); // atravessa a meia-noite: 24-22 + 6
  assert.equal(ESCALAS.at(-1), "Outros");
  assert.equal(new Set(ESCALAS).size, ESCALAS.length);
});

test("motivos: SDF adicionado, todos os existentes (inclusive Treinamento) preservados", () => {
  for (const m of ["Falta", "Atestado", "Remanejamento", "Reciclagem", "Falta de efetivo", "Treinamento", "SDF"]) assert.ok(MOTIVOS.includes(m), m);
});

test("postos P252–P258 exatos, sem duplicidade, e idênticos ao CHECK da migration", () => {
  const novos = ["P252 L2 EMPREENDIMENTOS E PARTICIPACOES LTDA AREA 1 OBRA SR MURILO", "P253 TREND LOFT NOVA MOGILAR", "P254 OK BRAZIL TRANSPORTE E LOGISTICA LTDA",
    "P255 NGN SPLENDOR", "P256 SP&G ENGENHARIA LTDA (DENTRO DA COCA COLA)", "P257 CONDOMINIO SPAZIO SUBLIME", "P258 COND. VILA CERES"];
  for (const n of novos) assert.ok(POSTOS_FALTA.includes(n), n);
  assert.equal(new Set(POSTOS_FALTA).size, POSTOS_FALTA.length);
  const sql = readFileSync(new URL("../supabase/migrations/20261009120100_add_postos_p252_p258.sql", import.meta.url), "utf8");
  const doBanco = [...sql.matchAll(/^\s+'(.+?)',?$/gm)].map((m) => m[1]);
  assert.deepEqual(doBanco, [...POSTOS_FALTA]);
});
