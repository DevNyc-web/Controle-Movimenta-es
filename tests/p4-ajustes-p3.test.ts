import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";

const ler = (p: string) => readFileSync(p, "utf8");

test("F3: nenhuma rota de _app redireciona por sessão no beforeLoad (no SSR não há sessão → F5 caía no Dashboard)", () => {
  const rotas = readdirSync("src/routes").filter((f) => f.startsWith("_app.") && f.endsWith(".tsx"));
  assert.ok(rotas.length > 10);
  for (const f of rotas) {
    const src = ler(`src/routes/${f}`);
    const i = src.indexOf("beforeLoad");
    if (i >= 0) assert.doesNotMatch(src.slice(i, i + 300), /getSession|redirect\(\{ to: "\/login"/, f);
  }
  // a sessão continua exigida pelo guarda do layout e o acesso pelo perfil de Gestor
  assert.match(ler("src/routes/_app.tsx"), /getSession\(\)[\s\S]*window\.location\.replace\("\/login"\)/);
  for (const f of ["_app.usuarios.tsx", "_app.auditoria.tsx"]) assert.match(ler(`src/routes/${f}`), /if \(!isGestor\)/, f);
});

test("F2: aviso de primeira importação só depois de a lista de empresas carregar", () => {
  const src = ler("src/routes/_app.conferencia.index.tsx");
  assert.match(src, /useState<Set<string> \| null>\(null\)/);
  assert.match(src, /const primeira = !!empresa && validadas !== null && !validadas\.has\(empresa\);/);
  assert.match(src, /if \(!error\) setValidadas\(/);
});

test("build Node do P3: cloudflare desligado, srvx fixo e servidor sem segredos", () => {
  assert.match(ler("vite.config.ts"), /^export default defineConfig\(\{ cloudflare: false \}\);/m);
  const pkg = JSON.parse(ler("package.json"));
  assert.equal(pkg.dependencies.srvx, "0.11.15");
  const srv = ler("servidor-producao.mjs");
  assert.match(srv, /if \(!arq\.startsWith\(DIR\)\) return null;/); // não serve nada fora de dist/client
  assert.match(srv, /"public, max-age=31536000, immutable"/);
  for (const f of ["servidor-producao.mjs", "scripts/iniciar-folha.ps1", "scripts/parar-folha.ps1"])
    assert.doesNotMatch(ler(f), /eyJ[\w-]{10,}|sb_secret_|postgres(ql)?:\/\/|\.supabase\.co/, f);
});
