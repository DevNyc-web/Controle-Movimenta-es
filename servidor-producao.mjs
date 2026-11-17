// Servidor de produção do Folha Certa (opção A: build Node + srvx). Aprovado no ensaio P3.
// Por que não "srvx serve --static": o srvx/static comprime em Brotli (nível máximo) a CADA requisição (~1,4 s de CPU no JS
// principal) e não envia Cache-Control. Aqui cada arquivo é comprimido uma vez e fica em memória; /assets/* (nome com hash)
// recebe cache longo. O resto vai para o handler do TanStack Start.
// Uso: node --env-file=<config> servidor-producao.mjs   (HOST e PORT pelo ambiente; padrão 127.0.0.1:8080)
import { serve } from "srvx";
import { readFile, stat } from "node:fs/promises";
import { extname, join, resolve, sep } from "node:path";
import { brotliCompress, gzip, constants } from "node:zlib";
import { promisify } from "node:util";
import app from "./dist/server/server.js";

for (const v of ["SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "SUPABASE_SERVICE_ROLE_KEY"])
  if (!process.env[v]) { console.error(`configuração ausente: ${v} (use node --env-file=<arquivo>)`); process.exit(78); }

const DIR = resolve(import.meta.dirname, "dist/client") + sep;
const TIPOS = { ".js": "text/javascript", ".css": "text/css", ".html": "text/html; charset=utf-8", ".json": "application/json",
  ".webmanifest": "application/manifest+json", ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".svg": "image/svg+xml",
  ".ico": "image/vnd.microsoft.icon", ".webp": "image/webp", ".woff": "font/woff", ".woff2": "font/woff2", ".txt": "text/plain" };
const COMPRIMIR = new Set([".js", ".css", ".html", ".json", ".webmanifest", ".svg", ".txt"]);
const br = promisify(brotliCompress), gz = promisify(gzip);
const cache = new Map(); // caminho -> Promise<{ tipo, cru, br?, gz? } | null>   (dist/client ~5 MB: cabe em memória)

function carrega(arq) {
  if (!cache.has(arq)) cache.set(arq, (async () => {
    const s = await stat(arq).catch(() => null); if (!s?.isFile()) return null;
    const ext = extname(arq), cru = await readFile(arq), e = { tipo: TIPOS[ext] ?? "application/octet-stream", cru };
    if (COMPRIMIR.has(ext) && cru.length > 1024) {
      e.br = await br(cru, { params: { [constants.BROTLI_PARAM_QUALITY]: 11, [constants.BROTLI_PARAM_SIZE_HINT]: cru.length } });
      e.gz = await gz(cru, { level: 9 });
    }
    return e;
  })());
  return cache.get(arq);
}

async function estatico(req) {
  if (req.method !== "GET" && req.method !== "HEAD") return null;
  let caminho; try { caminho = decodeURIComponent(new URL(req.url).pathname); } catch { return null; }
  if (caminho === "/" || caminho.endsWith("/")) return null;            // páginas são renderizadas pelo app
  const arq = resolve(DIR, "." + caminho);
  if (!arq.startsWith(DIR)) return null;                                // fora de dist/client
  const e = await carrega(arq); if (!e) { if (cache.get(arq)) cache.delete(arq); return null; }
  const aceita = req.headers.get("accept-encoding") ?? "";
  const [corpo, cod] = e.br && /\bbr\b/.test(aceita) ? [e.br, "br"] : e.gz && /\bgzip\b/.test(aceita) ? [e.gz, "gzip"] : [e.cru, null];
  const h = { "content-type": e.tipo, "content-length": String(corpo.length), "x-content-type-options": "nosniff",
    "cache-control": caminho.startsWith("/assets/") ? "public, max-age=31536000, immutable" : "no-cache" };
  if (e.br) h.vary = "Accept-Encoding"; if (cod) h["content-encoding"] = cod;
  return new Response(req.method === "HEAD" ? null : corpo, { headers: h });
}

const server = serve({
  hostname: process.env.HOST ?? "127.0.0.1",
  port: Number(process.env.PORT ?? 8080),
  gracefulShutdown: true,
  async fetch(req) {
    try { return (await estatico(req)) ?? (await app.fetch(req)); }
    catch (err) { console.error(new Date().toISOString(), "erro:", req.method, new URL(req.url).pathname, err?.stack ?? err); return new Response("Erro interno", { status: 500 }); }
  },
});
await server.ready();
console.log(new Date().toISOString(), `Folha Certa no ar: ${server.url} (pid ${process.pid}, node ${process.version})`);

// pré-aquece a compressão dos arquivos em segundo plano (o primeiro usuário após reiniciar não espera)
const { readdir } = await import("node:fs/promises");
(async () => { const t = Date.now(); let n = 0;
  for (const f of await readdir(DIR, { recursive: true })) { await carrega(join(DIR, f)).catch(() => null); n++; }
  console.log(new Date().toISOString(), `compressão pronta: ${n} itens em ${Date.now() - t} ms`); })();
