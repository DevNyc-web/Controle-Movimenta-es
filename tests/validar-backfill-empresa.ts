// Validação estrutural do backfill de funcionarios.empresa. O arquivo real (IDs de funcionários) NÃO é versionado
// (repositório público): os testes usam tests/fixtures/backfill-empresa-ficticio.sql; o real é conferido localmente:
//   node tests/validar-backfill-empresa.ts <backfill.sql> <total> [excecoes.txt]
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { EMPRESAS } from "../src/lib/empresas.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** Lança AssertionError se o SQL fugir do contrato. Devolve os pares id→empresa (para conferência/checksum). */
export function validarBackfillEmpresa(sql: string, { total, excecoes = [] }: { total: number; excecoes?: string[] }) {
  const codigo = sql.replace(/\r\n/g, "\n").replace(/--.*$/gm, "");
  const pares = [...codigo.matchAll(/unnest\(ARRAY\[([\s\S]*?)\]::uuid\[\]\), '([^']+)'/g)].flatMap(([, corpo, empresa]) =>
    [...corpo.matchAll(/'([^']*)'/g)].map(([, id]) => ({ id, empresa })),
  );
  const ids = pares.map((p) => p.id);
  assert.equal(ids.length, total, "quantidade de IDs");
  assert.equal(new Set(ids).size, total, "IDs repetidos");
  for (const id of ids) assert.match(id, UUID);
  for (const exc of excecoes) assert.ok(!ids.includes(exc), `exceção na lista: ${exc}`);
  for (const { empresa } of pares) assert.ok((EMPRESAS as readonly string[]).includes(empresa), `empresa desconhecida: ${empresa}`);
  // Única escrita real: funcionarios.empresa, só onde está vazia; nada em ft/histórico/financeiro/vínculos/RE
  assert.deepEqual(
    [...codigo.matchAll(/\b(UPDATE|DELETE|INSERT INTO|ALTER|DROP|TRUNCATE)\s+([\w.]+)/gi)].map((m) => `${m[1].toUpperCase()} ${m[2]}`),
    ["INSERT INTO _empresa_backfill", "UPDATE public.funcionarios"],
  );
  assert.match(codigo, /SET empresa = b\.empresa\s+FROM _empresa_backfill b\s+WHERE f\.id = b\.id\s+AND f\.empresa IS NULL;/);
  assert.doesNotMatch(codigo, /public\.ft\b|ft_historico|valor_pago|pagamento_em_folha|funcionario_id|\bre\s*=/);
  assert.match(codigo, /^BEGIN;$/m);
  assert.match(codigo, /^COMMIT;$/m);
  assert.match(codigo, new RegExp(`INTO n FROM _empresa_backfill;\\s+IF n <> ${total} THEN RAISE EXCEPTION`), "guarda de contagem");
  assert.match(codigo, new RegExp(`JOIN public\\.funcionarios f USING \\(id\\);\\s+IF n <> ${total} THEN RAISE EXCEPTION`), "guarda de ID ausente");
  for (const guarda of ["não existem mais", "sem CPF", "já têm empresa diferente"]) assert.ok(codigo.includes(guarda), guarda);
  return pares;
}

if (import.meta.main) {
  const [arq, total, exc] = process.argv.slice(2);
  const excecoes = exc ? readFileSync(exc, "utf8").split(/\s+/).filter(Boolean) : [];
  const pares = validarBackfillEmpresa(readFileSync(arq, "utf8"), { total: Number(total), excecoes });
  const porEmpresa = Object.fromEntries(EMPRESAS.map((e) => [e, pares.filter((p) => p.empresa === e).length]));
  const { createHash } = await import("node:crypto");
  const md5 = createHash("md5").update(pares.map((p) => `${p.id}:${p.empresa}`).sort().join("|")).digest("hex");
  console.log(JSON.stringify({ ok: true, ids: pares.length, excecoesVerificadas: excecoes.length, porEmpresa, md5 }, null, 2));
}
