import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import ExcelJS from "exceljs";
import { format } from "date-fns";
import { toast } from "sonner";
import { AlertTriangle, Upload } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { MapaAba } from "@/components/MapaAba";
import { leituraDa, mapeada, type Aba, type CampoMapa } from "@/lib/mapa-aba";
import { useAuth } from "@/lib/auth";
import type { ConferenciaTela } from "@/lib/conferencia";
import { criarConferencia } from "@/lib/conferencia.functions";
import { EMPRESAS, normalizarEmpresa } from "@/lib/empresas";
import { mensagemRegra } from "@/lib/funcionario-status";
import { abasDoWorkbook, deteccaoConfiavel, detectarColunas, empresaDoTitulo, LIMITE_BYTES, LIMITE_LINHAS } from "@/lib/importacao-funcionarios";

export const Route = createFileRoute("/_app/conferencia/")({ component: ImportacaoOficialPage });

type Conf = Pick<ConferenciaTela, "id" | "status" | "arquivo_nome" | "criada_em" | "resumo" | "resultado" | "empresa" | "primeira_da_empresa">;
type Empresa = (typeof EMPRESAS)[number];

// Só estas colunas são lidas; RG, nascimento e qualquer outra coluna nunca saem do navegador.
const CAMPOS: CampoMapa[] = [
  { campo: "cpf", label: "CPF", obrigatorio: true },
  { campo: "nome", label: "Nome completo", obrigatorio: true },
  { campo: "re", label: "Código / RE" },
  { campo: "cargo", label: "Cargo" },
  { campo: "admissao", label: "Admissão" },
];
const STATUS: Record<string, string> = { ABERTA: "Em revisão", CONCLUIDA: "Concluída", DESCARTADA: "Descartada" };
const inp = "w-full px-3 py-2 bg-sand rounded-xl text-sm border-none focus:outline-none focus:ring-2 focus:ring-oak-dark/20";

function ImportacaoOficialPage() {
  const { isGestor } = useAuth();
  const navigate = useNavigate();
  const [lista, setLista] = useState<Conf[]>([]);
  const [validadas, setValidadas] = useState<Set<string>>(new Set());
  const [abas, setAbas] = useState<Aba[]>([]);
  const [arquivos, setArquivos] = useState("");
  const [empresa, setEmpresa] = useState<Empresa | "">("");
  const [empresaDetectada, setEmpresaDetectada] = useState(false);
  const [lendo, setLendo] = useState(false);
  const [enviando, setEnviando] = useState(false);

  useEffect(() => {
    if (!isGestor) return;
    supabase.from("conferencias").select("id, status, arquivo_nome, criada_em, resumo, resultado, empresa, primeira_da_empresa").order("criada_em", { ascending: false }).limit(100)
      .then(({ data, error }) => {
        if (error) toast.error("Não foi possível carregar o histórico.");
        setLista((data ?? []) as unknown as Conf[]);
      });
    supabase.from("importacao_empresas").select("empresa").then(({ data }) => setValidadas(new Set((data ?? []).map((r) => r.empresa))));
  }, [isGestor]);

  if (!isGestor) return <div className="text-sm text-muted-foreground">Acesso restrito ao Gestor.</div>;

  const aberta = lista.find((c) => c.status === "ABERTA");
  const usadas = abas.filter((a) => a.usar);
  const leituras = usadas.filter(mapeada).map(leituraDa);
  const linhas = leituras.flatMap((l) => l.linhas);
  const ignoradas = leituras.flatMap((l) => l.ignoradas);
  const comTotal = leituras.filter((l) => l.totalImpresso !== null); // aba sem total impresso não entra na comparação
  const impresso = comTotal.length ? comTotal.reduce((s, l) => s + (l.totalImpresso as number), 0) : null;
  const lidasComTotal = comTotal.reduce((s, l) => s + l.linhas.length, 0);
  const pronto = !!empresa && usadas.length > 0 && usadas.every(mapeada) && linhas.length > 0 && linhas.length <= LIMITE_LINHAS;
  const primeira = !!empresa && !validadas.has(empresa);

  async function selecionar(e: React.ChangeEvent<HTMLInputElement>) {
    const files = [...(e.target.files ?? [])];
    e.target.value = "";
    if (!files.length) return;
    if (files.some((f) => f.size > LIMITE_BYTES)) return void toast.error("Cada arquivo pode ter no máximo 10 MB.");
    setLendo(true);
    setAbas([]);
    try {
      const novas: Aba[] = [];
      const empresas = new Set<string | null>();
      for (const f of files) {
        const wb = new ExcelJS.Workbook();
        await wb.xlsx.load(await f.arrayBuffer());
        for (const a of abasDoWorkbook(wb)) {
          const d = detectarColunas(a.matriz);
          if (!a.oculta) empresas.add(empresaDoTitulo(a.matriz, d.linhaCabecalho, normalizarEmpresa));
          novas.push({ id: `${novas.length}`, nome: files.length > 1 ? `${f.name} / ${a.nome}` : a.nome, matriz: a.matriz, linha: d.linhaCabecalho, colunas: d.colunas, duvida: !deteccaoConfiavel(d), usar: !a.oculta, oculta: a.oculta });
        }
      }
      // Empresa só é assumida quando todas as abas trazem a mesma no título; senão o Gestor escolhe.
      const unica = empresas.size === 1 ? [...empresas][0] : null;
      setEmpresa((unica ?? "") as Empresa | "");
      setEmpresaDetectada(!!unica);
      setArquivos(files.map((f) => f.name).join(", "));
      setAbas(novas);
      if (!novas.length) toast.error("Nenhuma aba com conteúdo foi encontrada.");
    } catch {
      toast.error("Não foi possível ler o arquivo. Envie um XLSX válido.");
    } finally {
      setLendo(false);
    }
  }

  const alterar = (id: string, m: Partial<Aba>) => setAbas((l) => l.map((a) => (a.id === id ? { ...a, ...m } : a)));

  async function comparar() {
    if (!empresa) return;
    setEnviando(true);
    try {
      const mapeamento = Object.fromEntries(usadas.map((a) => [a.nome, { linha: a.linha + 1, colunas: a.colunas }]));
      const { id } = await criarConferencia({
        data: {
          arquivo: { nome: arquivos.slice(0, 255), empresa, abas: usadas.map((a) => a.nome), mapeamento, ignoradas: ignoradas.length, total_impresso: impresso },
          linhas: linhas.map(({ cpfValido: _, ...l }) => ({ ...l, empresa: "" })),
        },
      });
      navigate({ to: "/conferencia/$id", params: { id } });
    } catch (err) {
      toast.error(mensagemRegra((err as Error).message ?? "Não foi possível criar a importação."));
      setEnviando(false);
    }
  }

  return (
    <div className="space-y-8 max-w-5xl">
      <div>
        <h1 className="text-3xl font-light tracking-tight">Importação oficial de funcionários</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          Envie a Relação Cadastral de uma empresa. O sistema propõe inclusões e atualizações; nada muda até você aprovar item a item e confirmar a aplicação.
        </p>
      </div>

      {aberta ? (
        <div className="bg-card border border-oak-light rounded-3xl p-6 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-sm">Há uma importação em revisão: <strong>{aberta.arquivo_nome}</strong>. Conclua ou descarte antes de iniciar outra.</p>
          <Link to="/conferencia/$id" params={{ id: aberta.id }} className="px-4 py-2 bg-oak-dark text-primary-foreground text-sm font-medium rounded-xl text-center">Continuar revisão</Link>
        </div>
      ) : (
        <div className="bg-card border border-oak-light rounded-3xl p-6 sm:p-8 space-y-6">
          <label className="block">
            <div className="border-2 border-dashed border-oak-medium rounded-2xl p-8 text-center cursor-pointer hover:bg-sand/30 transition">
              <Upload className="size-8 mx-auto text-oak-dark/60" />
              <div className="mt-3 text-sm font-medium">{lendo ? "Lendo..." : "Selecionar planilha oficial (XLSX)"}</div>
              <div className="text-xs text-oak-dark/50 mt-1">{arquivos || "Relação Cadastral de uma empresa, com Código/RE, nome, cargo e CPF"}</div>
            </div>
            <input type="file" accept=".xlsx" multiple onChange={selecionar} className="hidden" aria-label="Planilha oficial" />
          </label>

          {abas.length > 0 && (
            <div className="space-y-2">
              <label className="block text-xs">Empresa da planilha *
                <select value={empresa} onChange={(e) => { setEmpresa(e.target.value as Empresa | ""); setEmpresaDetectada(false); }} className={`${inp} mt-1`} aria-label="Empresa da planilha">
                  <option value="">Selecione</option>
                  {EMPRESAS.map((x) => <option key={x}>{x}</option>)}
                </select>
              </label>
              {!empresa && <p className="text-xs text-amber-800">Não foi possível identificar a empresa pelo título. Escolha a empresa desta planilha.</p>}
              {empresa && empresaDetectada && <p className="text-xs text-oak-dark/60">Empresa identificada pelo título do relatório.</p>}
              {primeira && <p className="text-sm bg-sand/50 rounded-xl p-3">Primeira importação desta empresa: inclusões e atualizações podem ser aprovadas; ausentes serão apenas sinalizados.</p>}
            </div>
          )}

          {abas.map((a) => <MapaAba key={a.id} aba={a} campos={CAMPOS} alterar={(m) => alterar(a.id, m)} />)}

          {usadas.length > 0 && (
            <div className="border-t border-oak-light pt-6 space-y-3">
              <p className="text-sm"><strong>{linhas.length}</strong> funcionário(s) lido(s); <strong>{ignoradas.length}</strong> linha(s) ignorada(s).</p>
              {impresso !== null && impresso !== lidasComTotal && (
                <p className="text-sm text-amber-800 flex gap-2"><AlertTriangle className="size-4 shrink-0 mt-0.5" /> A planilha informa {impresso} funcionário(s), mas foram lidos {lidasComTotal}. Confira o mapeamento.</p>
              )}
              {ignoradas.length > 0 && (
                <details className="text-xs text-oak-dark/70">
                  <summary className="cursor-pointer">Ver linhas ignoradas</summary>
                  <ul className="mt-2 max-h-40 overflow-auto space-y-0.5">{ignoradas.slice(0, 200).map((i) => <li key={i.origem}>{i.origem}: {i.motivo}</li>)}</ul>
                </details>
              )}
              {linhas.length > LIMITE_LINHAS && <p className="text-sm text-amber-800">Limite de {LIMITE_LINHAS} linhas excedido.</p>}
              <button onClick={comparar} disabled={!pronto || enviando} className="w-full sm:w-auto px-6 py-3 bg-oak-dark text-primary-foreground text-sm font-medium rounded-xl hover:opacity-90 disabled:opacity-50">
                {enviando ? "Comparando..." : "Comparar com o cadastro"}
              </button>
            </div>
          )}
        </div>
      )}

      <section className="space-y-3">
        <h2 className="text-sm font-medium">Histórico</h2>
        {lista.length === 0 ? <p className="text-sm text-muted-foreground">Nenhuma importação realizada.</p> : (
          <ul className="bg-card border border-oak-light rounded-3xl divide-y divide-oak-light">
            {lista.map((c) => (
              <li key={c.id}>
                <Link to="/conferencia/$id" params={{ id: c.id }} className="flex flex-col gap-1 p-4 sm:flex-row sm:items-center sm:justify-between hover:bg-sand/30">
                  <span className="min-w-0">
                    <span className="block text-sm font-medium truncate">{c.empresa ?? c.arquivo_nome}</span>
                    <span className="block text-xs text-oak-dark/60 truncate">
                      {format(new Date(c.criada_em), "dd/MM/yyyy HH:mm")} · {c.arquivo_nome} · {c.resumo?.total_folha ?? 0} na planilha{c.primeira_da_empresa ? " · primeira importação" : ""}
                    </span>
                  </span>
                  <span className="text-xs text-oak-dark/70 shrink-0">
                    {STATUS[c.status] ?? c.status}{c.resultado ? `: ${c.resultado.aplicados} aplicada(s), ${c.resultado.conflitos} conflito(s)` : ""}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
