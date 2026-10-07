import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { MOTIVOS } from "../src/lib/motivos.ts";

const layout = readFileSync("src/components/AppLayout.tsx", "utf8");
const novo = readFileSync("src/routes/_app.ft.novo.tsx", "utf8");

test("Treinamento existe e motivos antigos foram preservados", () => {
  for (const m of ["Falta", "Atestado", "Remanejamento", "Reciclagem", "Falta de efetivo", "Treinamento"]) assert.ok(MOTIVOS.includes(m), m);
  assert.equal(new Set(MOTIVOS).size, MOTIVOS.length);
});

test("select usa MOTIVOS e envia form.motivo sem transformar", () => {
  assert.ok(novo.includes("MOTIVOS.map((m) => <option key={m}>{m}</option>)"));
  assert.ok(novo.includes("motivo: form.motivo,"));
  assert.ok(novo.includes('from "@/lib/motivos"'));
});

test("sidebar: nav rolável separada do rodapé Sair", () => {
  assert.match(layout, /h-dvh overflow-hidden/);
  assert.match(layout, /<nav className="[^"]*min-h-0 overflow-y-auto/);
  const nav = layout.indexOf("<nav"), fimNav = layout.indexOf("</nav>"), sair = layout.indexOf("onClick={onSignOut}");
  assert.ok(fimNav > nav && sair > fimNav, "Sair fora do <nav>");
  assert.match(layout.slice(fimNav, sair), /shrink-0/);
});

test("logout segue o fluxo existente", () => {
  assert.match(layout, /await signOut\(\);\s*navigate\(\{ to: "\/login" \}\);/);
});
