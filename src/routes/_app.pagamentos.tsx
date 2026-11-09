import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import ExcelJS from "exceljs";
import { toast } from "sonner";
import { Upload } from "lucide-react";
import { MapaAba } from "@/components/MapaAba";
import { leituraDa, mapeada, type Aba, type CampoMapa } from "@/lib/mapa-aba";
import { useAuth } from "@/lib/auth";
import type { ItemConferencia, ResumoConferencia, TipoItem } from "@/lib/conferencia";
import { conferirPagamentos } from "@/lib/conferencia.functions";
import { mensagemRegra } from "@/lib/funcionario-status";
import { abasDoWorkbook, deteccaoConfiavel, detectarColunas, LIMITE_BYTES, LIMITE_LINHAS, nomeNormalizado } from "@/lib/importacao-funcionarios";

export const Route = createFileRoute("/_app/pagamentos")({ component: ConferenciaItauPage });

// Só nome e CPF/CNPJ são lidos. Valores, agência, conta, tipo, data e situação nunca saem da leitura.
const CAMPOS: CampoMapa[] = [
  { campo: "cpf", label: "CPF/CNPJ", obrigatorio: true },
  { campo: "nome", label: "Nome do funcionário", obrigatorio: true },
];
const ROTULO: Record<TipoItem, string> = {
  CORRESPONDENTE: "Confere", DIVERGENCIA_NOME: "Nome diferente do cadastro", DIVERGENCIA_CPF: "CPF diferente do cadastro",
  DIVERGENCIA_CARGO: "—", DIVERGENCIA_RE: "—", DIVERGENCIA_EMPRESA: "—",
  NOVO: "Sem funcionário identificado", INATIVO: "Funcionário inativo", AUSENTE: "—", DUPLICADO: "CPF repetido", PENDENCIA: "Revisar",
};
const FILTROS: { id: string; label: string; chave: keyof ResumoConferencia; tipos: TipoItem[] }[] = [
  { id: "corr", label: "Conferem", chave: "correspondencias", tipos: ["CORRESPONDENTE"] },
  { id: "div", label: "Divergências", chave: "divergencias", tipos: ["DIVERGENCIA_NOME", "DIVERGENCIA_CPF"] },
  { id: "novo", label: "Sem funcionário", chave: "novos", tipos: ["NOVO"] },
  { id: "ina", label: "Inativos pagos", chave: "inativos", tipos: ["INATIVO"] },
  { id: "dup", label: "CPF repetido", chave: "duplicidades", tipos: ["DUPLICADO"] },
  { id: "pen", label: "Revisar", chave: "pendencias", tipos: ["PENDENCIA"] },
];
const inp = "w-full px-3 py-2 bg-sand rounded-xl text-sm border-none focus:outline-none focus:ring-2 focus:ring-oak-dark/20";

function ConferenciaItauPage() {
  const { isGestor } = useAuth();
  const [abas, setAbas] = useState<Aba[]>([]);
  const [arquivos, setArquivos] = useState("");
  const [lendo, setLendo] = useState(false);
  const [comparando, setComparando] = useState(false);
  const [resultado, setResultado] = useState<{ resumo: ResumoConferencia; itens: ItemConferencia[] } | null>(null);
  const [filtro, setFiltro] = useState("todos");
  const [busca, setBusca] = useState("");

  const visiveis = useMemo(() => {
    if (!resultado) return [];
    const tipos = FILTROS.find((f) => f.id === filtro)?.tipos;
    const q = nomeNormalizado(busca);
    return resultado.itens.filter((i) => (!tipos || tipos.includes(i.tipo)) && (!q || nomeNormalizado(`${i.folha?.nome ?? ""} ${i.atual?.nome ?? ""}`).includes(q)));
  }, [resultado, filtro, busca]);

  if (!isGestor) return <div className="text-sm text-muted-foreground">Acesso restrito ao Gestor.</div>;

  const usadas = abas.filter((a) => a.usar);
  const linhas = usadas.filter(mapeada).flatMap((a) => leituraDa(a).linhas);
  const pronto = usadas.length > 0 && usadas.every(mapeada) && linhas.length > 0 && linhas.length <= LIMITE_LINHAS;

  async function selecionar(e: React.ChangeEvent<HTMLInputElement>) {
    const files = [...(e.target.files ?? [])];
    e.target.value = "";
    if (!files.length) return;
    if (files.some((f) => f.size > LIMITE_BYTES)) return void toast.error("Cada arquivo pode ter no máximo 10 MB.");
    setLendo(true); setAbas([]); setResultado(null);
    try {
      const novas: Aba[] = [];
      for (const f of files) {
        const wb = new ExcelJS.Workbook();
        await wb.xlsx.load(await f.arrayBuffer());
        for (const a of abasDoWorkbook(wb)) {
          const d = detectarColunas(a.matriz);
          // só CPF e nome; as outras colunas detectadas são descartadas aqui
          const colunas = { cpf: d.colunas.cpf, nome: d.colunas.nome };
          novas.push({ id: `${novas.length}`, nome: files.length > 1 ? `${f.name} / ${a.nome}` : a.nome, matriz: a.matriz, linha: d.linhaCabecalho, colunas, duvida: !deteccaoConfiavel(d), usar: !a.oculta, oculta: a.oculta });
        }
      }
      setArquivos(files.map((f) => f.name).join(", "));
      setAbas(novas);
    } catch {
      toast.error("Não foi possível ler o arquivo. Envie um XLSX válido.");
    } finally {
      setLendo(false);
    }
  }

  async function comparar() {
    setComparando(true);
    try {
      const r = await conferirPagamentos({ data: { linhas: linhas.map((l) => ({ origem: l.origem, nome: l.nome, cpf: l.cpf, re: "", cargo: "", empresa: "", admissao: null })) } });
      setResultado(r);
      setFiltro("todos");
    } catch (err) {
      toast.error(mensagemRegra((err as Error).message ?? "Não foi possível comparar."));
    } finally {
      setComparando(false);
    }
  }

  return (
    <div className="space-y-8 max-w-5xl">
      <div>
        <h1 className="text-3xl font-light tracking-tight">Conferência de pagamentos (Itaú)</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          Compara nome e CPF do relatório do banco com o cadastro. Somente leitura: nada é alterado nem gravado, e valores e dados bancários não são lidos.
        </p>
      </div>

      <div className="bg-card border border-oak-light rounded-3xl p-6 sm:p-8 space-y-6">
        <label className="block">
          <div className="border-2 border-dashed border-oak-medium rounded-2xl p-8 text-center cursor-pointer hover:bg-sand/30 transition">
            <Upload className="size-8 mx-auto text-oak-dark/60" />
            <div className="mt-3 text-sm font-medium">{lendo ? "Lendo..." : "Selecionar relatório do Itaú (XLSX)"}</div>
            <div className="text-xs text-oak-dark/50 mt-1">{arquivos || "Consulta de Pagamentos de Salários, com Nome do funcionário e CPF/CNPJ"}</div>
          </div>
          <input type="file" accept=".xlsx" multiple onChange={selecionar} className="hidden" aria-label="Relatório do Itaú" />
        </label>
        {abas.map((a) => <MapaAba key={a.id} aba={a} campos={CAMPOS} alterar={(m) => setAbas((l) => l.map((x) => (x.id === a.id ? { ...x, ...m } : x)))} />)}
        {usadas.length > 0 && (
          <div className="border-t border-oak-light pt-6 space-y-3">
            <p className="text-sm"><strong>{linhas.length}</strong> pagamento(s) lido(s).</p>
            <button onClick={comparar} disabled={!pronto || comparando} className="w-full sm:w-auto px-6 py-3 bg-oak-dark text-primary-foreground text-sm font-medium rounded-xl hover:opacity-90 disabled:opacity-50">
              {comparando ? "Comparando..." : "Comparar com o cadastro"}
            </button>
          </div>
        )}
      </div>

      {resultado && (
        <section className="space-y-4">
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <Cartao label="Pagamentos" valor={resultado.resumo.total_folha} ativo={filtro === "todos"} onClick={() => setFiltro("todos")} />
            {FILTROS.map((f) => <Cartao key={f.id} label={f.label} valor={resultado.resumo[f.chave] ?? 0} ativo={filtro === f.id} onClick={() => setFiltro(f.id)} />)}
          </div>
          <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Buscar por nome" className={inp} aria-label="Buscar" />
          <ul className="space-y-2">
            {visiveis.slice(0, 300).map((i, k) => (
              <li key={k} className="bg-card border border-oak-light rounded-2xl p-4 grid gap-2 sm:grid-cols-3 text-sm" data-tipo={i.tipo}>
                <div className="min-w-0"><div className="text-[10px] font-bold uppercase tracking-widest text-oak-dark/60">Itaú</div><p className="break-words">{i.folha?.nome}</p><p className="tabular-nums text-xs">CPF {i.folha?.cpf}</p></div>
                <div className="min-w-0"><div className="text-[10px] font-bold uppercase tracking-widest text-oak-dark/60">Folha Certa</div>{i.atual ? <><p className="break-words">{i.atual.nome}</p><p className="tabular-nums text-xs">CPF {i.atual.cpf ?? "—"} · {i.atual.status}</p></> : <p className="text-oak-dark/50">Sem cadastro</p>}</div>
                <div className="min-w-0 text-xs"><p className="font-semibold">{ROTULO[i.tipo]}</p><p className="text-oak-dark/70">{i.motivo} · {i.origens.join(", ")}</p></div>
              </li>
            ))}
          </ul>
          {visiveis.length > 300 && <p className="text-xs text-oak-dark/60">Mostrando 300 de {visiveis.length}. Use a busca ou os filtros.</p>}
        </section>
      )}
    </div>
  );
}

function Cartao({ label, valor, ativo, onClick }: { label: string; valor: number; ativo: boolean; onClick: () => void }) {
  return (
    <button onClick={onClick} aria-pressed={ativo} className={`text-left rounded-2xl p-3 border ${ativo ? "border-oak-dark bg-sand/50" : "border-oak-light bg-card"}`}>
      <span className="block text-2xl font-light tabular-nums">{valor ?? 0}</span>
      <span className="block text-[10px] uppercase tracking-widest text-oak-dark/60">{label}</span>
    </button>
  );
}
