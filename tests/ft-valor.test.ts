// Correção manual de valor_pago / pagamento_em_folha nos detalhes da FT.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { parseValorCentavos, centavosDe, formatarCentavos, montarCorrecao, descreverCorrecao, valorNoRelatorio, VALOR_MAXIMO_CENTAVOS } from "../src/lib/ft-valor.ts";
import { totaisGerais, agruparPorFuncionario, LABEL_FOLHA } from "../src/lib/relatorio.ts";

test("aceita formatos monetários pt-BR comuns, em centavos exatos", () => {
  const casos: [string, number][] = [
    ["250", 25000], ["250,5", 25050], ["250,50", 25050], ["0,01", 1], ["0", 0], ["1.250,00", 125000],
    ["R$ 250,35", 25035], [" 99.999,99 ", 9999999], ["250.5", 25050], ["250.35", 25035], ["1.250", 125000],
  ];
  for (const [txt, c] of casos) assert.equal(parseValorCentavos(txt), c, txt);
});

test("rejeita valores inválidos", () => {
  for (const txt of ["", " ", "-10", "-0,01", "abc", "10,001", "10.001,5,5", "1,2,3", "12a", "1e3", "NaN", "Infinity", "100.000,00", "1.25.0", ",50", "250,", "12.34.56"])
    assert.equal(parseValorCentavos(txt), null, txt);
  assert.equal(parseValorCentavos(formatarCentavos(VALOR_MAXIMO_CENTAVOS + 1)), null);
});

test("sem erro de arredondamento: centavos / 100 volta exatamente ao decimal", () => {
  for (const c of [1, 10, 29, 57, 110, 25035, 1999, 9999999, 123456]) {
    const v = c / 100;
    assert.equal(centavosDe(v), c);
    assert.equal(JSON.parse(JSON.stringify({ v })).v, v); // o que vai no PATCH
    assert.equal(String(v), (c / 100).toFixed(2).replace(/\.?0+$/, "")); // nunca 2.5700000000000003
  }
  assert.equal(centavosDe("200.00"), 20000); // NUMERIC pode vir como string
  assert.equal(centavosDe(0.1 + 0.2), 30);
  assert.equal(formatarCentavos(125035), "1.250,35");
  assert.equal(formatarCentavos(5), "0,05");
});

test("PATCH contém só o que mudou; nada mudou = vazio", () => {
  const ft = { valor_pago: 200, pagamento_em_folha: false };
  assert.deepEqual(montarCorrecao(ft, 20000, false), {});
  assert.deepEqual(montarCorrecao(ft, 25050, false), { valor_pago: 250.5 });
  assert.deepEqual(montarCorrecao(ft, 20000, true), { pagamento_em_folha: true });
  assert.deepEqual(montarCorrecao(ft, 0, true), { valor_pago: 0, pagamento_em_folha: true });
  assert.deepEqual(montarCorrecao({ valor_pago: "150.00", pagamento_em_folha: true }, 15000, false), { pagamento_em_folha: false });
});

test("descrição do histórico: valor anterior/novo e folha", () => {
  const ft = { valor_pago: 200, pagamento_em_folha: false };
  assert.equal(descreverCorrecao(ft, { valor_pago: 250.5 }), "Valor: R$ 200,00 → R$ 250,50");
  assert.equal(descreverCorrecao(ft, { pagamento_em_folha: true }), "Pagamento em folha: Não → Sim");
  assert.equal(descreverCorrecao(ft, { valor_pago: 1250, pagamento_em_folha: true }), "Valor: R$ 200,00 → R$ 1.250,00 · Pagamento em folha: Não → Sim");
});

test("valor exibido = regra do relatório; correção salva entra nos totais; folha continua fora", () => {
  assert.equal(valorNoRelatorio({ valor_pago: 200, pagamento_em_folha: false }), "R$ 200.00");
  assert.equal(valorNoRelatorio({ valor_pago: 200, pagamento_em_folha: true }), LABEL_FOLHA);
  const base = (over: object) => ({ id: "a", funcionario_id: "j", data_ft: "2026-10-01", horas_trabalhadas: 12, status: "PENDENTE", valor_pago: 200, pagamento_em_folha: false, ...over });
  const linhas = [base({}), base({ id: "b", data_ft: "2026-10-02" })];
  assert.equal(totaisGerais(linhas).valor, 400);
  const corrigida = { ...linhas[0], ...montarCorrecao(linhas[0], 25035, false) }; // como a FT volta do banco após salvar
  assert.equal(totaisGerais([corrigida, linhas[1]]).valor, 450.35);
  const emFolha = { ...corrigida, ...montarCorrecao(corrigida, 25035, true) };
  assert.equal(emFolha.valor_pago, 250.35); // valor preservado, só sai do total
  assert.equal(totaisGerais([emFolha, linhas[1]]).valor, 200);
  assert.equal(agruparPorFuncionario([emFolha, linhas[1]])[0].valor, 200);
});

/* ---- Tela de detalhes (verificação estática da integração) ---- */
// Normaliza CRLF (checkout no Windows com core.autocrlf=true): as asserções abaixo comparam trechos com "\n" literal.
const tela = readFileSync("src/routes/_app.ft.$id.tsx", "utf8").replace(/\r\n/g, "\n");

test("aprovação/negação não mexe em valor nem folha (não sobrescreve correção)", () => {
  const change = tela.slice(tela.indexOf("async function changeStatus"), tela.indexOf("async function salvarCorrecao"));
  assert.ok(change.length > 0);
  assert.ok(!/valor_pago|pagamento_em_folha/.test(change));
  assert.ok(tela.includes('onClick={() => changeStatus("APROVADA")} disabled={pendenteDeSalvar}'), "aprovar bloqueado com alteração não salva");
  assert.ok(tela.includes('onClick={() => changeStatus("NEGADA")} disabled={pendenteDeSalvar}'));
});

test("salvar usa trava otimista, só gestor em FT pendente, e registra histórico", () => {
  const salvar = tela.slice(tela.indexOf("async function salvarCorrecao"), tela.indexOf("async function solicitarCancelamento"));
  assert.ok(salvar.includes('.update(patch).eq("id", id).eq("status", "PENDENTE").eq("updated_at", ft.updated_at).select("id").maybeSingle()'));
  assert.ok(salvar.includes("setConflito(true)"));
  assert.ok(salvar.includes('from("ft_historico").insert('));
  assert.ok(salvar.includes("descreverCorrecao(ft, patch)"));
  assert.ok(tela.includes("{isPending && isGestor && (\n          <div className=\"space-y-4\">"), "editor só para gestor e FT pendente");
});
