import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  avaliarRetroativa,
  formatarData,
  JUSTIFICATIVA_MAX,
  justificativaValida,
  mensagemRegra,
  STATUS_LABEL,
  statusDe,
} from "../src/lib/funcionario-status.ts";

const ler = (p: string) => readFileSync(p, "utf8");
const lista = ler("src/routes/_app.funcionarios.index.tsx");
const form = ler("src/components/FuncionarioForm.tsx");
const picker = ler("src/components/FuncionarioPicker.tsx");
const novo = ler("src/routes/_app.ft.novo.tsx");

test("três estados: férias não é inativo; status desconhecido não vira ativo", () => {
  assert.equal(STATUS_LABEL[statusDe("ativo")], "Ativo");
  assert.equal(STATUS_LABEL[statusDe("ferias")], "Férias");
  assert.equal(STATUS_LABEL[statusDe("inativo")], "Inativo");
  assert.equal(statusDe("qualquer"), "inativo");
  assert.equal(statusDe(null), "inativo");
});

test("formatarData não passa por Date e não desloca o dia", () => {
  assert.equal(formatarData("2026-11-05"), "05/11/2026");
  assert.equal(formatarData(null), "—");
});

test("justificativa: mesmos limites do banco, sem contar espaços", () => {
  assert.equal(justificativaValida("          "), false);
  assert.equal(justificativaValida("   curta   "), false);
  assert.equal(justificativaValida("  dez letras "), false, "nove letras: espaços não contam");
  assert.equal(justificativaValida("  dez letras a "), true);
  assert.equal(justificativaValida("\n".repeat(20)), false);
  assert.equal(justificativaValida("\u200b".repeat(20)), false);
  assert.equal(justificativaValida("\u00a0".repeat(20)), false);
  assert.equal(justificativaValida(".,;!?-.,;!?-"), false);
  assert.equal(justificativaValida("x".repeat(JUSTIFICATIVA_MAX)), true);
  assert.equal(justificativaValida("x".repeat(JUSTIFICATIVA_MAX + 1)), false);
});

const ativo = { nome: "A", status: "ativo", data_inativacao: null };
const ferias = { nome: "F", status: "ferias", data_inativacao: null };
const saiu = { nome: "S", status: "inativo", data_inativacao: "2026-11-05" };
const saiuAntes = { nome: "T", status: "inativo", data_inativacao: "2026-10-01" };

test("sem inativo não há exceção, nem para férias", () => {
  assert.deepEqual(avaliarRetroativa([ativo, ferias], "2026-11-05"), { inativos: [], bloqueio: null });
  assert.deepEqual(avaliarRetroativa([undefined, undefined], "2026-11-05"), { inativos: [], bloqueio: null });
});

test("data do serviço precisa ser estritamente anterior à inativação", () => {
  assert.equal(avaliarRetroativa([saiu], "2026-11-04").bloqueio, null);
  assert.match(avaliarRetroativa([saiu], "2026-11-05").bloqueio!, /anterior à inativação de S \(05\/11\/2026\)/);
  assert.ok(avaliarRetroativa([saiu], "2026-11-06").bloqueio);
});

test("com dois inativos, vale a inativação mais antiga; sem data, bloqueia", () => {
  assert.ok(avaliarRetroativa([saiu, saiuAntes], "2026-10-15").bloqueio?.includes("T"));
  assert.equal(avaliarRetroativa([saiu, saiuAntes], "2026-09-30").inativos.length, 2);
  assert.ok(avaliarRetroativa([{ ...saiu, data_inativacao: null }], "2026-01-01").bloqueio);
});

test("mensagemRegra tira o código técnico e preserva o resto", () => {
  assert.equal(mensagemRegra("FUNCIONARIO_INATIVO: X está inativo"), "X está inativo");
  assert.equal(mensagemRegra("RETROATIVA_DATA: a data"), "a data");
  assert.equal(mensagemRegra("EXCLUSAO_PROIBIDA: não"), "não");
  assert.equal(mensagemRegra("outro erro: qualquer"), "outro erro: qualquer");
});

test("interface não oferece exclusão física de funcionário", () => {
  for (const arquivo of [lista, form, picker]) assert.doesNotMatch(arquivo, /\.delete\(\)|Trash2|Excluir/);
  assert.match(lista, /confirm\(`Inativar/);
});

test("reativação exige motivo e não sai do formulário", () => {
  assert.match(lista, /update\(\{ status: "ativo", reativacao_motivo: motivo\.trim\(\) \}\)/);
  assert.match(lista, /if \(motivo === null\) return;/);
  assert.match(form, /if \(initial && form\.status === initial\.status\) delete payload\.status;/);
  assert.match(form, /disabled=\{initial\?\.status === "inativo"\}/);
});

test("picker mostra erro de carregamento, sem confundir com lista vazia", () => {
  assert.match(picker, /setErro\(!!error\)/);
  assert.match(picker, /role="alert"/);
  assert.match(picker, /open && !erro && filtered\.length === 0/);
});

test("servidor usa a regra do banco e bane conta desativada", () => {
  const server = ler("src/lib/admin.server.ts");
  const funcoes = ler("src/lib/admin.functions.ts");
  assert.match(server, /rpc\("has_role"/);
  assert.doesNotMatch(server, /roles\.includes/);
  assert.match(funcoes, /ban_duration: data\.ativo \? "none" : "876000h"/);
});

test("mensagens de regra novas perdem o código técnico", () => {
  assert.equal(mensagemRegra("FT_INATIVO_NA_DATA: não aprova"), "não aprova");
  assert.equal(mensagemRegra("REATIVACAO_MOTIVO: exige motivo"), "exige motivo");
});

test("anulação de período: só Gestor na tela, pela RPC, com justificativa e só em período encerrado", () => {
  const p = ler("src/components/PeriodosInatividade.tsx");
  assert.match(p, /if \(!isGestor \|\| periodos\.length === 0\) return null;/);
  assert.match(p, /rpc\("anular_inatividade"/);
  assert.match(p, /justificativaValida\(justificativa\)/);
  assert.match(p, /p\.fim && !p\.anulada_em && !inativo/);
  assert.doesNotMatch(p, /\.update\(|\.delete\(/);
  assert.equal(mensagemRegra("PERMISSAO: apenas o Gestor"), "apenas o Gestor");
  assert.equal(mensagemRegra("ANULACAO_ESTADO: já anulado"), "já anulado");
});

test("listagem e formulário usam status, com os três estados", () => {
  assert.doesNotMatch(lista, /status_ativo/);
  assert.match(form, /"ativo", "ferias", "inativo"/);
  assert.doesNotMatch(form, /status_ativo: form/, "status_ativo é calculado pelo banco");
  assert.doesNotMatch(form, /data_inativacao:/, "data de inativação não é enviada pelo cliente");
});

test("picker: padrão não busca inativos; só o Gestor pode ligar a inclusão", () => {
  assert.match(picker, /if \(!incluirInativos\) query = query\.neq\("status", "inativo"\)/);
  assert.match(picker, /incluirInativos = false/);
  assert.match(novo, /\{isGestor && \(\s*<label/);
  assert.match(novo, /incluirInativos=\{retroativa\}/);
  assert.doesNotMatch(novo, /setRetroativa\(true\)/);
});

test("FT nova só envia a justificativa; autoria é do banco", () => {
  assert.match(novo, /retroativa_justificativa: justificativa\.trim\(\)/);
  assert.doesNotMatch(novo, /retroativa_autorizada/);
});
