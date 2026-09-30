import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const manifest = JSON.parse(readFileSync("public/manifest.webmanifest", "utf8"));

test("20 manifest válido", () => {
  for (const k of ["name", "short_name", "start_url", "display", "theme_color", "background_color"]) assert.ok(manifest[k], k);
  assert.equal(manifest.display, "standalone");
  const sizes = manifest.icons.map((i: any) => i.sizes);
  assert.ok(sizes.includes("192x192") && sizes.includes("512x512"));
});

test("21 ícones e metadata referenciados existem", () => {
  for (const i of manifest.icons) assert.ok(existsSync(join("public", i.src)), i.src);
  assert.ok(existsSync("public/apple-touch-icon.png") && existsSync("public/favicon-32.png"));
  const root = readFileSync("src/routes/__root.tsx", "utf8");
  for (const s of ["manifest.webmanifest", "apple-touch-icon", "theme-color", "apple-mobile-web-app-capable"]) assert.ok(root.includes(s), s);
});

test("23 sem service worker / cache", () => {
  assert.ok(!existsSync("public/sw.js") && !existsSync("public/service-worker.js"));
  const walk = (d: string): string[] => readdirSync(d).flatMap((f) => (statSync(join(d, f)).isDirectory() ? walk(join(d, f)) : [join(d, f)]));
  for (const f of walk("src").filter((x) => /\.tsx?$/.test(x))) {
    const t = readFileSync(f, "utf8");
    assert.ok(!/serviceWorker|caches\.open/.test(t), f);
  }
});
