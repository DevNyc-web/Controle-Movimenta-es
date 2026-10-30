// Cancelamento: qualquer supervisor SOLICITA (não só quem lançou); aprovar/rejeitar segue só com gestor/admin.
// A regra efetiva (RLS, trigger, RPCs) é provada em supabase/tests/supervisor_window.sql; aqui, a UI e a migration.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { descreverSolicitacao, escolherSolicitacao } from "../src/lib/cancelamento.ts";

const src = (p: string) => readFileSync(p, "utf8").replace(/\r\n/g, "\n"); // LF ou CRLF (autocrlf no Windows)
const det = src("src/routes/_app.ft.$id.tsx");
const apr = src("src/routes/_app.aprovacoes.tsx");
const mig = src("supabase/migrations/20261030120000_cancelamento_qualquer_supervisor.sql");

test("detalhe da FT: botão de solicitar não depende de quem lançou", () => {
  assert.match(
    det,
    /\{isSupervisor && isPending && \(\n\s*<button\n\s*onClick=\{\(\) => setShowCancelModal\(true\)\}/,
  );
  assert.doesNotMatch(det, /lancado_por === user\?\.id/);
});

test("detalhe da FT: solicitante gravado é o usuário logado; cancelamento direto continua só para gestor", () => {
  assert.match(
    det,
    /from\("ft_cancelamento_solicitacoes"\)\.insert\(\{\n\s*ft_id: id,\n\s*solicitado_por: user!\.id,/,
  );
  assert.match(det, /\{isGestor && !isCanceled && \(/);
});

test("Aprovações: mostra solicitante e lançador separados, cada um pelo seu campo", () => {
  assert.match(apr, /ft:ft\(numero_ft, data_ft, lancado_por, funcionario:/);
  assert.match(apr, /solicitante_nome: profileMap\[s\.solicitado_por\]/);
  assert.match(apr, /\.flatMap\(\(s\) => \[s\.solicitado_por, s\.ft\?\.lancado_por\]\)/);
  assert.match(apr, /lancador_nome: \(s\.ft\?\.lancado_por && profileMap\[s\.ft\.lancado_por\]\)/);
  assert.match(apr, /Solicitado por: \{s\.solicitante_nome\}/);
  assert.match(apr, /Lançado por: \{s\.lancador_nome\}/);
  assert.doesNotMatch(apr, /supervisor_nome/);
  // decisão continua pelas RPCs com checagem de gestor/admin
  assert.match(apr, /acao === "aprovar" \? "aprovar_cancelamento" : "rejeitar_cancelamento"/);
});

test("migration: só a policy de INSERT muda; mantém solicitante = auth.uid(), role supervisor e PENDENTE", () => {
  const ativo = mig
    .split("\n")
    .filter((l) => !l.trimStart().startsWith("--"))
    .join("\n");
  assert.match(
    ativo,
    /DROP POLICY IF EXISTS "Supervisor solicita cancelamento" ON public\.ft_cancelamento_solicitacoes;/,
  );
  assert.match(ativo, /FOR INSERT TO authenticated/);
  assert.match(ativo, /solicitado_por = auth\.uid\(\)/);
  assert.match(ativo, /public\.has_role\(auth\.uid\(\), 'supervisor'::public\.app_role\)/);
  assert.match(ativo, /f\.status = 'PENDENTE'::public\.ft_status/);
  assert.doesNotMatch(ativo, /lancado_por/);
  assert.doesNotMatch(ativo, /\b(UPDATE|DELETE|INSERT INTO|GRANT|ALTER|FUNCTION|TRIGGER)\b/); // sem dados, grants ou RPCs
  assert.match(mig, /-- ROLLBACK manual[\s\S]*f\.lancado_por = auth\.uid\(\)/); // rollback documentado
});

// ---- Detalhe da FT: "Cancelamento solicitado por" ----

const sol = (id: string, status: string, created_at: string) => ({
  id,
  solicitado_por: `u-${id}`,
  status,
  created_at,
});

test("escolherSolicitacao: pendente tem prioridade; sem pendente, a mais recente; nenhuma = null", () => {
  const rej = sol("a", "REJEITADO", "2026-10-01T10:00:00Z");
  const pend = sol("b", "PENDENTE", "2026-09-01T10:00:00Z"); // mais antiga, mas pendente
  const apr = sol("c", "APROVADO", "2026-10-05T10:00:00Z");
  assert.equal(escolherSolicitacao([rej, apr, pend])?.id, "b");
  assert.equal(escolherSolicitacao([rej, apr])?.id, "c");
  assert.equal(escolherSolicitacao([apr, rej])?.id, "c"); // independe da ordem recebida
  assert.equal(escolherSolicitacao([]), null);
  // o solicitante exibido é o da solicitação escolhida, nunca de outra
  assert.equal(escolherSolicitacao([rej, pend])?.solicitado_por, "u-b");
});

test("descreverSolicitacao: nome, situação, data e qual solicitação está sendo exibida", () => {
  assert.equal(
    descreverSolicitacao({ nome: "Ana", status: "PENDENTE", data: "30/10/2026 09:00", total: 1 }),
    "Ana — pendente, pedido em 30/10/2026 09:00",
  );
  assert.equal(
    descreverSolicitacao({ nome: "Ana", status: "PENDENTE", data: "30/10/2026 09:00", total: 3 }),
    "Ana — pendente, pedido em 30/10/2026 09:00 (atual de 3 solicitações)",
  );
  assert.equal(
    descreverSolicitacao({ nome: "Bia", status: "REJEITADO", data: "01/10/2026 10:00", total: 2 }),
    "Bia — rejeitada, pedido em 01/10/2026 10:00 (mais recente de 2 solicitações)",
  );
  assert.equal(
    descreverSolicitacao({ nome: null, status: "APROVADO", data: "x", total: 1 }),
    "Não identificado — aprovada, pedido em x",
  );
});

test("server fn: solicitação lida pela RLS do usuário; nome só de solicitado_por, nunca de lancado_por", () => {
  const fn = src("src/lib/ft.functions.ts");
  const corpo = fn.slice(fn.indexOf("export const getSolicitacaoCancelamentoFt"));
  assert.match(
    corpo,
    /context\.supabase\n\s*\.from\("ft_cancelamento_solicitacoes"\)\n\s*\.select\("id, solicitado_por, status, created_at"\)\n\s*\.eq\("ft_id", data\.ftId\)/,
  );
  assert.match(
    corpo,
    /supabaseAdmin\n\s*\.from\("profiles"\)\n\s*\.select\("nome"\)\n\s*\.eq\("id", s\.solicitado_por\)/,
  );
  // service role: uma única chamada, só depois da leitura autorizada (erro aborta; sem solicitação, retorna antes)
  const ordem = [
    "context.supabase",
    "if (error) throw error;",
    "const lista = sols ?? [];",
    "const s = escolherSolicitacao(lista);",
    "if (!s) return null;",
    "supabaseAdmin",
  ].map((t) => corpo.indexOf(t));
  assert.ok(!ordem.includes(-1), `trecho ausente: ${ordem}`);
  assert.deepEqual(
    ordem,
    [...ordem].sort((a, b) => a - b),
    "leitura RLS -> erro -> escolha -> service role",
  );
  assert.equal(corpo.split("supabaseAdmin").length - 1, 1);
  // o ID consultado vem só da solicitação autorizada (s), nunca do input do cliente
  assert.equal(corpo.split("data.ftId").length - 1, 1);
  assert.doesNotMatch(corpo, /lancado_por|\.update\(|\.insert\(|\.delete\(/);
  assert.match(corpo, /requireSupabaseAuth/);
});

test("detalhe da FT: campos separados e resposta de outra FT descartada", () => {
  assert.match(det, /<Info label="Lançado por" value=\{lancador/);
  assert.match(
    det,
    /label="Cancelamento solicitado por"\n\s*value=\{descreverSolicitacao\(\{\n\s*\.\.\.solicitacao,\n\s*data: format\(new Date\(solicitacao\.createdAt\), "dd\/MM\/yyyy HH:mm"\),\n\s*\}\)\}/,
  );
  assert.match(
    det,
    /\{solicitacao === "erro" && \(\n\s*<Info label="Cancelamento solicitado por" value="Não foi possível carregar" \/>\n\s*\)\}/,
  );
  assert.match(det, /\.then\(\(r\) => \{\n\s*if \(vivo\) setSolicitacao\(r\);\n\s*\}\)/);
  assert.match(det, /\}, \[id, recarga, buscarSolicitacao\]\);/);
});

test("detalhe da FT: uma consulta da solicitação na abertura; rebusca só após ações da tela", () => {
  assert.equal(det.split("buscarSolicitacao({").length - 1, 1, "uma única chamada (no efeito)");
  const load = det.slice(
    det.indexOf("async function load()"),
    det.indexOf("async function changeStatus"),
  );
  assert.doesNotMatch(
    load,
    /setRecarga|buscarSolicitacao/,
    "load() não dispara a busca (evita 2 consultas na abertura)",
  );
  const acao = (nome: string) =>
    det.slice(det.indexOf(`async function ${nome}`)).split("\n  }\n")[0];
  assert.match(acao("changeStatus"), /load\(\);\n\s*setRecarga\(\(n\) => n \+ 1\);/);
  assert.match(acao("solicitarCancelamento"), /load\(\);\n\s*setRecarga\(\(n\) => n \+ 1\);/);
});
