import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { trocaDeConta } from "../src/lib/auth-sessao.ts";

test("P4-F4: renovação/recuperação da mesma conta (volta à aba, TOKEN_REFRESHED) não desmonta a tela", () => {
  assert.equal(trocaDeConta("u1", "u1"), false);
});

test("P4-F4: troca real de conta continua carregando (primeira carga, entrada, saída, outro usuário)", () => {
  assert.equal(trocaDeConta(undefined, null), true); // primeira carga sem sessão
  assert.equal(trocaDeConta(undefined, "u1"), true); // primeira carga com sessão
  assert.equal(trocaDeConta(null, "u1"), true); // entrou
  assert.equal(trocaDeConta("u1", null), true); // saiu (ou perfil desativado → signOut)
  assert.equal(trocaDeConta("u1", "u2"), true); // outro usuário
  assert.equal(trocaDeConta(null, null), false); // continua sem sessão
});

test("P4-F4: AuthProvider só põe loading=true (que faz o AppLayout desmontar a tela) quando a conta muda", () => {
  const src = readFileSync("src/lib/auth.tsx", "utf8");
  const ev = src.slice(src.indexOf("onAuthStateChange("), src.indexOf("supabase.auth.getSession()"));
  assert.match(ev, /if \(trocaDeConta\(contaAplicada\.current, sess\?\.user\?\.id \?\? null\)\) setLoading\(true\);/);
  assert.equal(ev.match(/setLoading\(true\)/g)?.length, 1, "setLoading(true) incondicional no evento de autenticação");
  assert.match(src, /contaAplicada\.current = sess\?\.user\?\.id \?\? null;/);
  // o layout continua escondendo tudo enquanto carrega (só na troca de conta)
  assert.match(readFileSync("src/components/AppLayout.tsx", "utf8"), /if \(loading\) return null;/);
});
