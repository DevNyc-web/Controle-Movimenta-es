import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import ExcelJS from "exceljs";
import { format } from "date-fns";
import { toast } from "sonner";
import { AlertTriangle, Upload } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/auth";
import type { ConferenciaTela } from "@/lib/conferencia";
import { criarConferencia } from "@/lib/conferencia.functions";
import { mensagemRegra } from "@/lib/funcionario-status";
import {
  abasDoWorkbook, celulaTexto, deteccaoConfiavel, detectarColunas, extrairLinhas, LIMITE_BYTES, LIMITE_LINHAS,
  type Campo, type Colunas, type Matriz,
} from "@/lib/importacao-funcionarios";

export const Route = createFileRoute("/_app/conferencia/")({ component: ConferenciaPage });

/** nome: "arquivo / aba" com vários arquivos, para achar a linha certa quando as abas têm o mesmo nome. */
type Aba = { id: string; nome: string; matriz: Matriz; linha: number; colunas: Colunas; duvida: boolean; usar: boolean };
type Conf = Pick<ConferenciaTela, "id" | "status" | "arquivo_nome" | "criada_em" | "resumo" | "resultado">;

const CAMPOS: { campo: Campo; label: string; obrigatorio?: boolean }[] = [
  { campo: "cpf", label: "CPF", obrigatorio: true },
  { campo: "nome", label: "Nome completo", obrigatorio: true },
  { campo: "re", label: "RE / matrícula" },
  { campo: "cargo", label: "Cargo" },
  { campo: "empresa", label: "Empresa" },
  { campo: "admissao", label: "Admissão" },
];
const STATUS: Record<string, string> = { ABERTA: "Em revisão", CONCLUIDA: "Concluída", DESCARTADA: "Descartada" };
const inp = "w-full px-3 py-2 bg-sand rounded-xl text-sm border-none focus:outline-none focus:ring-2 focus:ring-oak-dark/20";

const leitura = (a: Aba) => extrairLinhas(a.matriz, a.linha, a.colunas, a.nome);
const mapeada = (a: Aba) => a.linha >= 0 && a.colunas.cpf !== undefined && a.colunas.nome !== undefined && a.colunas.cpf !== a.colunas.nome;

function ConferenciaPage() {
  const { isGestor } = useAuth();
  const navigate = useNavigate();
  const [lista, setLista] = useState<Conf[]>([]);
  const [abas, setAbas] = useState<Aba[]>([]);
  const [arquivos, setArquivos] = useState("");
  const [lendo, setLendo] = useState(false);
  const [enviando, setEnviando] = useState(false);

  useEffect(() => {
    if (!isGestor) return;
    supabase.from("conferencias").select("id, status, arquivo_nome, criada_em, resumo, resultado").order("criada_em", { ascending: false }).limit(100)
      .then(({ data, error }) => {
        if (error) toast.error("Não foi possível carregar o histórico.");
        setLista((data ?? []) as unknown as Conf[]);
      });
  }, [isGestor]);

  if (!isGestor) return <div className="text-sm text-muted-foreground">Acesso restrito ao Gestor.</div>;

  const aberta = lista.find((c) => c.status === "ABERTA");
  const usadas = abas.filter((a) => a.usar);
  const leituras = usadas.filter(mapeada).map(leitura);
  const linhas = leituras.flatMap((l) => l.linhas);
  const ignoradas = leituras.flatMap((l) => l.ignoradas);
  const comTotal = leituras.filter((l) => l.totalImpresso !== null); // aba sem total impresso não entra na comparação
  const impresso = comTotal.length ? comTotal.reduce((s, l) => s + (l.totalImpresso as number), 0) : null;
  const lidasComTotal = comTotal.reduce((s, l) => s + l.linhas.length, 0);
  const pronto = usadas.length > 0 && usadas.every(mapeada) && linhas.length > 0 && linhas.length <= LIMITE_LINHAS;

  async function selecionar(e: React.ChangeEvent<HTMLInputElement>) {
    const files = [...(e.target.files ?? [])];
    e.target.value = "";
    if (!files.length) return;
    if (files.some((f) => f.size > LIMITE_BYTES)) return void toast.error("Cada arquivo pode ter no máximo 10 MB.");
    setLendo(true);
    setAbas([]);
    try {
      const novas: Aba[] = [];
      for (const f of files) {
        const wb = new ExcelJS.Workbook();
        await wb.xlsx.load(await f.arrayBuffer());
        for (const a of abasDoWorkbook(wb)) {
          const d = detectarColunas(a.matriz);
          novas.push({ id: `${novas.length}`, nome: files.length > 1 ? `${f.name} / ${a.nome}` : a.nome, matriz: a.matriz, linha: d.linhaCabecalho, colunas: d.colunas, duvida: !deteccaoConfiavel(d), usar: true });
        }
      }
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
    setEnviando(true);
    try {
      const mapeamento = Object.fromEntries(usadas.map((a) => [a.nome, { linha: a.linha + 1, colunas: a.colunas }]));
      const { id } = await criarConferencia({
        data: {
          arquivo: { nome: arquivos.slice(0, 255), abas: usadas.map((a) => a.nome), mapeamento, ignoradas: ignoradas.length, total_impresso: impresso },
          linhas: linhas.map(({ cpfValido: _, ...l }) => l),
        },
      });
      navigate({ to: "/conferencia/$id", params: { id } });
    } catch (err) {
      toast.error(mensagemRegra((err as Error).message ?? "Não foi possível criar a conferência."));
      setEnviando(false);
    }
  }

  return (
    <div className="space-y-8 max-w-5xl">
      <div>
        <h1 className="text-3xl font-light tracking-tight">Conferência de funcionários</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          Compare a folha de pagamento com o cadastro. Nada muda até você aprovar item a item e confirmar a aplicação.
        </p>
      </div>

      {aberta ? (
        <div className="bg-card border border-oak-light rounded-3xl p-6 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-sm">Há uma conferência em revisão: <strong>{aberta.arquivo_nome}</strong>. Conclua ou descarte antes de iniciar outra.</p>
          <Link to="/conferencia/$id" params={{ id: aberta.id }} className="px-4 py-2 bg-oak-dark text-primary-foreground text-sm font-medium rounded-xl text-center">Continuar revisão</Link>
        </div>
      ) : (
        <div className="bg-card border border-oak-light rounded-3xl p-6 sm:p-8 space-y-6">
          <label className="block">
            <div className="border-2 border-dashed border-oak-medium rounded-2xl p-8 text-center cursor-pointer hover:bg-sand/30 transition">
              <Upload className="size-8 mx-auto text-oak-dark/60" />
              <div className="mt-3 text-sm font-medium">{lendo ? "Lendo..." : "Selecionar folha de pagamento (XLSX)"}</div>
              <div className="text-xs text-oak-dark/50 mt-1">{arquivos || "Um ou mais arquivos, com CPF e nome completo"}</div>
            </div>
            <input type="file" accept=".xlsx" multiple onChange={selecionar} className="hidden" aria-label="Folha de pagamento" />
          </label>

          {abas.map((a) => <MapaAba key={a.id} aba={a} alterar={(m) => alterar(a.id, m)} />)}

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
        {lista.length === 0 ? <p className="text-sm text-muted-foreground">Nenhuma conferência realizada.</p> : (
          <ul className="bg-card border border-oak-light rounded-3xl divide-y divide-oak-light">
            {lista.map((c) => (
              <li key={c.id}>
                <Link to="/conferencia/$id" params={{ id: c.id }} className="flex flex-col gap-1 p-4 sm:flex-row sm:items-center sm:justify-between hover:bg-sand/30">
                  <span className="min-w-0">
                    <span className="block text-sm font-medium truncate">{c.arquivo_nome}</span>
                    <span className="block text-xs text-oak-dark/60">{format(new Date(c.criada_em), "dd/MM/yyyy HH:mm")} · {c.resumo?.total_folha ?? 0} na folha</span>
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

/** Mapeamento de uma aba. Fechado quando a detecção é confiável, mas sempre pode ser aberto e corrigido. */
function MapaAba({ aba, alterar }: { aba: Aba; alterar: (m: Partial<Aba>) => void }) {
  const problema = aba.usar && !mapeada(aba);
  const rotulos = (aba.linha >= 0 ? aba.matriz[aba.linha] ?? [] : []).map((c) => celulaTexto(c));
  const opcoes = rotulos.map((r, i) => ({ i, r })).filter((o) => o.r);
  const definir = (campo: Campo, v: string) => {
    const colunas = { ...aba.colunas };
    if (v === "") delete colunas[campo];
    else colunas[campo] = Number(v);
    alterar({ colunas });
  };
  return (
    <details open={aba.duvida} className="border border-oak-light rounded-2xl p-4">
      <summary className="cursor-pointer text-sm font-medium">
        {aba.nome} {problema ? <span className="text-amber-700 text-xs">· informe as colunas de CPF e nome</span> : <span className="text-oak-dark/60 text-xs">· {aba.usar ? `${leitura(aba).linhas.length} linha(s)` : "ignorada"}</span>}
      </summary>
      <div className="mt-4 space-y-4">
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={aba.usar} onChange={(e) => alterar({ usar: e.target.checked })} /> Usar esta aba
        </label>
        {aba.usar && (
          <div className="grid gap-3 sm:grid-cols-2 md:grid-cols-4">
            <label className="text-xs">
              Linha do cabeçalho
              <input type="number" min={1} value={aba.linha >= 0 ? aba.linha + 1 : ""} onChange={(e) => alterar({ linha: Number(e.target.value) - 1, colunas: {} })} className={`${inp} mt-1`} />
            </label>
            {CAMPOS.map(({ campo, label, obrigatorio }) => (
              <label key={campo} className="text-xs">
                {label}{obrigatorio ? " *" : ""}
                <select value={aba.colunas[campo] ?? ""} onChange={(e) => definir(campo, e.target.value)} className={`${inp} mt-1`} aria-label={`Coluna de ${label}`}>
                  <option value="">{obrigatorio ? "Selecione" : "Não usar"}</option>
                  {opcoes.map((o) => <option key={o.i} value={o.i}>{o.r}</option>)}
                </select>
              </label>
            ))}
          </div>
        )}
      </div>
    </details>
  );
}
