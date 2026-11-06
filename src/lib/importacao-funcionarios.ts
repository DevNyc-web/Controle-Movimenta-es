// Leitura de planilhas de funcionários, sem React nem Supabase. Compartilhada pelo importador e pela Conferência.
// Layout não é presumido: colunas são reconhecidas por sinônimos e, sem confiança, o usuário mapeia.
// Toda linha que não vira funcionário fica contada em `ignoradas`, com o motivo.

export type Campo = "cpf" | "nome" | "re" | "cargo" | "empresa" | "admissao";
export type Colunas = Partial<Record<Campo, number>>;
export type Matriz = unknown[][];

export const LIMITE_BYTES = 10 * 1024 * 1024;
export const LIMITE_LINHAS = 20000;

export const CARGOS = ["Vigilante", "Porteiro", "ASG", "Recepcionista", "Manutencista", "Freelancer"] as const;

const semAcento = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "");
const rotulo = (s: string) => semAcento(s).toLowerCase().replace(/[.:_º°]/g, "").replace(/\s+/g, " ").trim();

/** Maiúsculas, sem acento, só letras e espaços simples: "  José  d'Ávila " -> "JOSE D AVILA". */
export const nomeNormalizado = (s: string) => semAcento(s).toUpperCase().replace(/[^A-Z ]/g, " ").replace(/\s+/g, " ").trim();

/** Texto de uma célula do ExcelJS: rich text, fórmula, hyperlink, data ou valor simples. */
export function celulaTexto(v: unknown): string {
  if (v == null) return "";
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  if (typeof v === "object") {
    const o = v as { richText?: { text: string }[]; result?: unknown; text?: unknown; error?: unknown };
    if (o.richText) return o.richText.map((t) => t.text).join("").trim();
    if (o.error) return "";
    if (o.result !== undefined) return celulaTexto(o.result);
    if (o.text !== undefined) return celulaTexto(o.text);
    return "";
  }
  return String(v).trim();
}

/** Só dígitos. Número do Excel perde zeros à esquerda: eles são recompostos para 11 dígitos. */
export function cpfDaCelula(v: unknown): string {
  const bruto = typeof v === "object" && v !== null && !(v instanceof Date) ? (v as { result?: unknown }).result ?? celulaTexto(v) : v;
  if (typeof bruto === "number") return Number.isFinite(bruto) ? String(Math.trunc(Math.abs(bruto))).padStart(11, "0") : "";
  const t = celulaTexto(bruto);
  if (!/^[\d.\-\s/]+$/.test(t)) return "";
  const d = t.replace(/\D/g, "");
  return d.length >= 9 && d.length < 11 ? d.padStart(11, "0") : d;
}

export function cpfValido(d: string) {
  if (!/^\d{11}$/.test(d) || /^(\d)\1{10}$/.test(d)) return false;
  for (const n of [9, 10]) {
    let s = 0;
    for (let i = 0; i < n; i++) s += Number(d[i]) * (n + 1 - i);
    if (((s * 10) % 11) % 10 !== Number(d[n])) return false;
  }
  return true;
}

/** "123.456.789-09" -> "***.456.789-**". Já mascarado passa direto; o que não for CPF completo não é exibido. */
export function mascararCpf(v: string | null | undefined) {
  if (!v) return "—";
  if (v.startsWith("***")) return v;
  const d = v.replace(/\D/g, "");
  return d.length === 11 ? `***.${d.slice(3, 6)}.${d.slice(6, 9)}-**` : "***";
}

/** Cargo do sistema ou null quando não é reconhecido. Nunca adivinha Freelancer. */
export function cargoReconhecido(raw: string): (typeof CARGOS)[number] | null {
  const c = semAcento(raw || "").toUpperCase();
  if (c.includes("VIGILANTE")) return "Vigilante";
  if (["LIMPEZA", "ZELADOR", "ASG", "SERVICOS GERAIS", "AUX. SERVICOS", "AUXILIAR DE SERVICOS"].some((k) => c.includes(k))) return "ASG";
  if (["PORTARIA", "PORTEIRO", "VIGIA", "CONTROLADOR", "ACESSO", "MONITORAMENTO", "BOMBEIRO", "INSPETOR", "VISTORIA"].some((k) => c.includes(k))) return "Porteiro";
  if (c.includes("RECEPCION")) return "Recepcionista";
  if (["MANUTEN", "INSTALADOR", "TECNICO"].some((k) => c.includes(k))) return "Manutencista";
  if (c.includes("FREELANCER")) return "Freelancer";
  return null;
}

const SINONIMOS: Record<Campo, { exatos: string[]; contem?: RegExp; exceto?: RegExp }> = {
  cpf: {
    exatos: ["cpf", "cpf do funcionario", "cpf funcionario", "cpf do colaborador", "cpf colaborador", "cpf do empregado", "numero do cpf", "n cpf", "no cpf"],
    contem: /\bcpf\b/, exceto: /responsavel|mae|pai|conjuge/,
  },
  nome: {
    exatos: ["nome", "nome completo", "funcionario", "nome do funcionario", "colaborador", "nome do colaborador", "empregado", "nome do empregado", "trabalhador", "nome do trabalhador"],
    contem: /\bnome\b/, exceto: /mae|pai|social|fantasia|empresa|filial|cargo|banco|usuario|conjuge/,
  },
  re: { exatos: ["re", "matricula", "codigo", "cod", "chapa", "registro", "codigo do funcionario", "codigo funcionario", "cod funcionario"] },
  cargo: { exatos: ["cargo", "funcao", "cargo/funcao", "cargo atual", "ocupacao", "descricao do cargo"], contem: /\b(cargo|funcao)\b/, exceto: /codigo|cod\b/ },
  empresa: { exatos: ["empresa", "filial", "razao social", "nome da empresa", "estabelecimento"], contem: /\b(empresa|filial)\b/, exceto: /cnpj|codigo|cod\b/ },
  admissao: { exatos: ["admissao", "data de admissao", "data admissao", "dt admissao", "dt de admissao"], contem: /\badmissao\b/ },
};
const CAMPOS = Object.keys(SINONIMOS) as Campo[];

function campoDoRotulo(l: string): { campo: Campo; forte: boolean } | null {
  for (const c of CAMPOS) if (SINONIMOS[c].exatos.includes(l)) return { campo: c, forte: true };
  for (const c of CAMPOS) {
    const s = SINONIMOS[c];
    if (s.contem?.test(l) && !s.exceto?.test(l)) return { campo: c, forte: false };
  }
  return null;
}

export interface Deteccao {
  linhaCabecalho: number; // índice na matriz; -1 = não achou
  colunas: Colunas;
  /** Campos com mais de uma coluna possível, com rótulos diferentes. */
  ambiguos: Partial<Record<Campo, number[]>>;
  rotulos: string[];
}

/** Procura o cabeçalho nas primeiras linhas: a que reconhece mais campos, exigindo nome. */
export function detectarColunas(m: Matriz): Deteccao {
  let melhor: Deteccao = { linhaCabecalho: -1, colunas: {}, ambiguos: {}, rotulos: [] };
  let pontos = 1;
  for (let i = 0; i < Math.min(30, m.length); i++) {
    const rotulos = (m[i] ?? []).map((c) => celulaTexto(c));
    const achados: Partial<Record<Campo, { i: number; rotulo: string; forte: boolean }[]>> = {};
    rotulos.forEach((r, col) => {
      const l = rotulo(r);
      if (!l || l.length > 40) return;
      const a = campoDoRotulo(l);
      if (a) (achados[a.campo] ??= []).push({ i: col, rotulo: l, forte: a.forte });
    });
    if (!achados.nome) continue;
    const colunas: Colunas = {};
    const ambiguos: Deteccao["ambiguos"] = {};
    for (const c of CAMPOS) {
      const lista = achados[c];
      if (!lista) continue;
      const fortes = lista.filter((x) => x.forte);
      const base = fortes.length ? fortes : lista;
      colunas[c] = base[0].i;
      // Mesmo rótulo repetido é célula mesclada, não ambiguidade.
      const distintos = [...new Map(base.map((x) => [x.rotulo, x.i])).values()];
      if (distintos.length > 1) ambiguos[c] = distintos;
    }
    const p = Object.keys(colunas).length;
    if (p > pontos) { pontos = p; melhor = { linhaCabecalho: i, colunas, ambiguos, rotulos }; }
  }
  return melhor;
}

export const deteccaoConfiavel = (d: Deteccao) =>
  d.linhaCabecalho >= 0 && d.colunas.cpf !== undefined && d.colunas.nome !== undefined && !d.ambiguos.cpf && !d.ambiguos.nome;

export interface LinhaFolha {
  origem: string; // "aba:linha", para o usuário achar a linha no arquivo
  nome: string;
  cpf: string;
  cpfValido: boolean;
  re: string;
  cargo: string;
  empresa: string;
  admissao: string | null;
}

export interface LeituraFolha {
  linhas: LinhaFolha[];
  ignoradas: { origem: string; motivo: string }[];
  /** Total impresso na própria planilha, quando existe. */
  totalImpresso: number | null;
}

const RODAPE = /\b(sub-?total|total|soma|liquido|bruto|pagina|pag|emissao|assinatura|relatorio|relacao cadatral|relacao cadastral)\b/;
const SECAO = /:|\b(ltda|eireli|s\/?a|me|departamento|setor|secao|centro de custo|filial|lotacao)\b/;
const TOTAL = /total de (?:empregados|funcionarios|colaboradores|trabalhadores)\D*(\d+)/;

function dataIso(v: unknown): string | null {
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  const m = /(\d{2})[/-](\d{2})[/-](\d{4})/.exec(celulaTexto(v));
  if (!m) return null;
  const iso = `${m[3]}-${m[2]}-${m[1]}`;
  const d = new Date(`${iso}T00:00:00Z`); // 31/02 vira 03/03: data impossível não passa
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === iso ? iso : null;
}

/** Linhas depois do cabeçalho. Vazia não conta; o resto vira funcionário ou ignorada, com motivo. */
export function extrairLinhas(m: Matriz, linhaCabecalho: number, colunas: Colunas, aba = ""): LeituraFolha {
  const out: LeituraFolha = { linhas: [], ignoradas: [], totalImpresso: null };
  const origem = (i: number) => `${aba ? `${aba}:` : ""}${i + 1}`;
  const celula = (l: unknown[], c: Campo) => (colunas[c] === undefined ? undefined : l[colunas[c] as number]);
  for (let i = linhaCabecalho + 1; i < m.length; i++) {
    const l = m[i] ?? [];
    const textos = l.map((c) => celulaTexto(c)).filter(Boolean);
    if (textos.length === 0) continue;
    const corrido = rotulo(textos.join(" "));
    const total = TOTAL.exec(corrido);
    if (total) { out.totalImpresso = (out.totalImpresso ?? 0) + Number(total[1]); out.ignoradas.push({ origem: origem(i), motivo: "total da planilha" }); continue; }

    const nome = celulaTexto(celula(l, "nome")).replace(/\s+/g, " ").trim();
    const cpfBruto = celula(l, "cpf");
    const cpf = cpfDaCelula(cpfBruto);
    const nomeRotulo = rotulo(nome);
    if (nomeRotulo && SINONIMOS.nome.exatos.includes(nomeRotulo)) { out.ignoradas.push({ origem: origem(i), motivo: "cabeçalho repetido" }); continue; }
    if (!cpf) {
      if (!nome) { out.ignoradas.push({ origem: origem(i), motivo: "sem nome e sem CPF" }); continue; }
      if (RODAPE.test(corrido)) { out.ignoradas.push({ origem: origem(i), motivo: "total ou rodapé" }); continue; }
      if (SECAO.test(nomeRotulo) || /\d/.test(nome) || nomeRotulo.length < 3) { out.ignoradas.push({ origem: origem(i), motivo: "título de seção" }); continue; }
    }
    out.linhas.push({
      origem: origem(i), nome, cpf, cpfValido: cpfValido(cpf),
      re: celulaTexto(celula(l, "re")), cargo: celulaTexto(celula(l, "cargo")), empresa: celulaTexto(celula(l, "empresa")),
      admissao: dataIso(celula(l, "admissao")),
    });
  }
  return out;
}

export interface Aba { nome: string; matriz: Matriz }

/** Worksheets do ExcelJS em matrizes simples (valores começam no índice 1 no ExcelJS). */
export function abasDoWorkbook(wb: { worksheets: { name: string; rowCount: number; getRow: (i: number) => { values: unknown } }[] }): Aba[] {
  return wb.worksheets
    .map((ws) => {
      const matriz: Matriz = [];
      for (let i = 1; i <= Math.min(ws.rowCount, LIMITE_LINHAS + 50); i++) {
        const v = ws.getRow(i).values;
        matriz.push(Array.isArray(v) ? Array.from(v).slice(1) : []);
      }
      return { nome: ws.name, matriz };
    })
    .filter((a) => a.matriz.some((l) => l.some((c) => celulaTexto(c))));
}
