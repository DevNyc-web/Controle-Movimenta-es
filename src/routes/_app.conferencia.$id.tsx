import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useCallback, useEffect, useMemo, useState } from "react";
import { format } from "date-fns";
import { toast } from "sonner";
import { ArrowLeft } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useAuth } from "@/lib/auth";
import { ACAO_LABEL, exigeJustificativa, TIPO_LABEL, type Acao, type ConferenciaTela, type ItemTela, type ResultadoConferencia, type ResumoConferencia, type TipoItem } from "@/lib/conferencia";
import { lerConferencia } from "@/lib/conferencia.functions";
import { formatarData, JUSTIFICATIVA_MIN, justificativaValida, mensagemRegra } from "@/lib/funcionario-status";
import { CARGOS, cargoReconhecido, nomeNormalizado, VALOR_FT } from "@/lib/importacao-funcionarios";

export const Route = createFileRoute("/_app/conferencia/$id")({ component: ImportacaoDetalhe });

type Item = ItemTela;
type Dados = { conferencia: ConferenciaTela; itens: Item[] };

const PASSO = 50;
const inp = "w-full px-3 py-2 bg-sand rounded-xl text-sm border-none focus:outline-none focus:ring-2 focus:ring-oak-dark/20";
const btn = "px-3 py-2 rounded-xl text-xs font-medium disabled:opacity-50";
const FILTROS: { id: string; label: string; chave: keyof ResumoConferencia; tipos: TipoItem[] }[] = [
  { id: "corr", label: "Correspondências", chave: "correspondencias", tipos: ["CORRESPONDENTE"] },
  { id: "novo", label: "Novos", chave: "novos", tipos: ["NOVO"] },
  { id: "aus", label: "Ausentes", chave: "ausentes", tipos: ["AUSENTE"] },
  { id: "div", label: "Divergências", chave: "divergencias", tipos: ["DIVERGENCIA_NOME", "DIVERGENCIA_CPF", "DIVERGENCIA_CARGO", "DIVERGENCIA_RE", "DIVERGENCIA_EMPRESA"] },
  { id: "ina", label: "Inativos", chave: "inativos", tipos: ["INATIVO"] },
  { id: "dup", label: "Duplicidades", chave: "duplicidades", tipos: ["DUPLICADO"] },
  { id: "pen", label: "Pendências", chave: "pendencias", tipos: ["PENDENCIA"] },
];
const DECISAO: Record<string, string> = { PENDENTE: "Pendente", APROVADA: "Aprovado", REJEITADA: "Rejeitado", REVISADA: "Revisado", SEM_ACAO: "Sem ação" };
const valor = (c?: string | null) => (c && c in VALOR_FT ? `R$ ${VALOR_FT[c as keyof typeof VALOR_FT].toFixed(2)}` : "—");

function ImportacaoDetalhe() {
  const { id } = Route.useParams();
  const { isGestor } = useAuth();
  const navigate = useNavigate();
  const [dados, setDados] = useState<Dados | null | undefined>(undefined);
  const [filtro, setFiltro] = useState("todos");
  const [busca, setBusca] = useState("");
  const [limite, setLimite] = useState(PASSO);
  const [aprovar, setAprovar] = useState<{ item: Item; acao: Acao } | null>(null);
  const [aplicando, setAplicando] = useState(false);
  const [descartando, setDescartando] = useState(false);
  const [quadro, setQuadro] = useState(false);
  const [lote, setLote] = useState<Set<string>>(new Set());
  const [loteAberto, setLoteAberto] = useState(false);

  const carregar = useCallback(async () => {
    try {
      setDados(await lerConferencia({ data: { id } }));
      setLote(new Set());
    } catch {
      toast.error("Não foi possível carregar a importação.");
      setDados(null);
    }
  }, [id]);
  useEffect(() => { if (isGestor) carregar(); }, [isGestor, carregar]);

  const visiveis = useMemo(() => {
    if (!dados) return [];
    const tipos = FILTROS.find((f) => f.id === filtro)?.tipos;
    const q = nomeNormalizado(busca);
    const d = busca.replace(/\D/g, "");
    return dados.itens.filter((i) => (!tipos || tipos.includes(i.tipo)) && (!busca.trim()
      || (q && nomeNormalizado(`${i.folha?.nome ?? ""} ${i.atual?.nome ?? ""}`).includes(q))
      || (d && `${i.folha?.re ?? ""} ${i.atual?.re ?? ""} ${i.folha?.cpf ?? ""} ${i.atual?.cpf ?? ""}`.replace(/[.*-]/g, "").includes(d))));
  }, [dados, filtro, busca]);

  if (!isGestor) return <div className="text-sm text-muted-foreground">Acesso restrito ao Gestor.</div>;
  if (dados === undefined) return <div className="text-sm text-muted-foreground">Carregando...</div>;
  if (dados === null) return <div className="text-sm text-muted-foreground">Importação não encontrada.</div>;

  const c = dados.conferencia;
  // O banco recusa decidir, confirmar e aplicar depois de 7 dias; a tela só deixa descartar.
  const expirada = c.status === "ABERTA" && Date.now() - new Date(c.criada_em).getTime() > 7 * 86_400_000;
  const aberta = c.status === "ABERTA" && !expirada;
  const aprovados = dados.itens.filter((i) => i.decisao === "APROVADA");
  const podeInativar = aberta && c.primeira_da_empresa === false && !!c.quadro_completo_em;
  const inativaveis = dados.itens.filter((i) => i.tipo === "AUSENTE" && i.opcoes.includes("INATIVAR") && i.decisao !== "APROVADA");
  const novaRevisao = (r: number | null) => setDados((d) => d && { ...d, conferencia: { ...d.conferencia, revisao: r ?? d.conferencia.revisao } });

  async function decidir(item: Item, decisao: string, acao?: Acao, justificativa?: string, extra?: Record<string, string>) {
    const { data, error } = await supabase.rpc("conferencia_decidir", { _item: item.id, _decisao: decisao, _acao: acao, _justificativa: justificativa, _dados: extra });
    if (error) { toast.error(mensagemRegra(error.message)); return false; }
    setDados((d) => d && { conferencia: { ...d.conferencia, revisao: data ?? d.conferencia.revisao }, itens: d.itens.map((i) => (i.id === item.id ? { ...i, decisao, acao: acao ?? null, justificativa: justificativa ?? null } : i)) });
    return true;
  }

  return (
    <div className="space-y-6 max-w-5xl pb-24">
      <div>
        <Link to="/conferencia" className="text-xs text-oak-dark/60 hover:underline inline-flex items-center gap-1"><ArrowLeft className="size-3" /> Importações</Link>
        <h1 className="text-2xl font-light tracking-tight mt-2 break-words">{c.empresa ?? c.arquivo_nome}</h1>
        <p className="text-sm text-muted-foreground mt-1 break-words">
          {format(new Date(c.criada_em), "dd/MM/yyyy HH:mm")} · {c.arquivo_nome} · {aberta ? "Em revisão" : c.status === "CONCLUIDA" ? "Concluída" : "Descartada"}
          {c.resultado && ` · ${c.resultado.aplicados} aplicada(s), ${c.resultado.conflitos} conflito(s)`}
          {c.motivo_descarte && ` · ${c.motivo_descarte}`}
        </p>
      </div>

      {expirada && <p className="text-sm bg-amber-50 text-amber-900 rounded-xl p-3">Importação aberta há mais de 7 dias: expirou e não pode mais ser aprovada nem aplicada. Descarte e envie a planilha de novo.</p>}
      {c.primeira_da_empresa && <p className="text-sm bg-sand/50 rounded-xl p-3">Primeira importação desta empresa: ausentes são apenas sinalizados e não podem ser inativados.</p>}
      {aberta && c.primeira_da_empresa === false && (
        <div className="bg-card border border-oak-light rounded-2xl p-4 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          {c.quadro_completo_em
            ? <p className="text-sm">Quadro completo confirmado em {format(new Date(c.quadro_completo_em), "dd/MM/yyyy HH:mm")}. Ausentes podem ser propostos para inativação.</p>
            : <p className="text-sm">Ausentes só podem ser inativados se esta planilha representar o quadro completo da empresa.</p>}
          {!c.quadro_completo_em && <button onClick={() => setQuadro(true)} className={`${btn} bg-oak-dark text-primary-foreground`}>Confirmar quadro completo</button>}
        </div>
      )}

      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <Cartao label="Total na planilha" valor={c.resumo.total_folha} ativo={filtro === "todos"} onClick={() => { setFiltro("todos"); setLimite(PASSO); }} />
        {FILTROS.map((f) => <Cartao key={f.id} label={f.label} valor={c.resumo[f.chave] ?? 0} ativo={filtro === f.id} onClick={() => { setFiltro(f.id); setLimite(PASSO); }} />)}
      </div>
      {!!c.resumo.nao_avaliados && <p className="text-xs text-oak-dark/70">{c.resumo.nao_avaliados} freelancer(s) desta empresa não entram na avaliação de ausentes.</p>}

      {filtro === "aus" && (
        <div className="text-sm bg-sand/50 rounded-xl p-3 space-y-2">
          <p>Ausentes nunca são inativados automaticamente. {podeInativar ? "Revise cada um; a inativação usa as regras normais e preserva as FTs." : "Nesta importação eles são apenas sinalizados."}</p>
          {podeInativar && inativaveis.length > 0 && (
            <div className="flex flex-wrap items-center gap-2">
              <label className="flex items-center gap-2 text-xs">
                <input type="checkbox" checked={lote.size === inativaveis.length} onChange={(e) => setLote(new Set(e.target.checked ? inativaveis.map((i) => i.id) : []))} /> Selecionar todos ({inativaveis.length})
              </label>
              <button onClick={() => setLoteAberto(true)} disabled={lote.size === 0} className={`${btn} bg-oak-dark text-primary-foreground`}>Inativar selecionados ({lote.size})</button>
            </div>
          )}
        </div>
      )}

      <input value={busca} onChange={(e) => { setBusca(e.target.value); setLimite(PASSO); }} placeholder="Buscar por nome, RE ou parte do CPF" className={inp} aria-label="Buscar" />

      {visiveis.length === 0 ? <p className="text-sm text-muted-foreground">Nenhum item neste filtro.</p> : (
        <ul className="space-y-3">
          {visiveis.slice(0, limite).map((i) => (
            <ItemCard key={i.id} item={i} aberta={aberta} podeInativar={podeInativar} aoAprovar={(acao) => setAprovar({ item: i, acao })} decidir={decidir}
              selecionado={lote.has(i.id)} selecionar={inativaveis.includes(i) && podeInativar ? (v) => setLote((s) => { const n = new Set(s); if (v) n.add(i.id); else n.delete(i.id); return n; }) : undefined} />
          ))}
        </ul>
      )}
      {visiveis.length > limite && (
        <button onClick={() => setLimite((l) => l + PASSO)} className={`${btn} bg-oak-medium/30 w-full`}>Mostrar mais ({visiveis.length - limite} restantes)</button>
      )}

      {(aberta || expirada) && (
        <div className="sticky bottom-0 bg-card border border-oak-light rounded-2xl p-3 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <span className="text-sm"><strong>{aprovados.length}</strong> item(ns) aprovado(s)</span>
          <div className="flex gap-2">
            <button onClick={() => setDescartando(true)} className={`${btn} flex-1 sm:flex-none bg-oak-medium/30`}>Descartar</button>
            {aberta && <button onClick={() => setAplicando(true)} className={`${btn} flex-1 sm:flex-none bg-oak-dark text-primary-foreground`}>
              {aprovados.length ? "Aplicar alterações" : "Concluir sem alterações"}
            </button>}
          </div>
        </div>
      )}

      {aprovar && <DialogoAprovar {...aprovar} empresa={c.empresa} fechar={() => setAprovar(null)} decidir={decidir} />}
      {aplicando && <DialogoAplicar id={id} revisao={c.revisao} primeira={!!c.primeira_da_empresa} aprovados={aprovados} fechar={() => setAplicando(false)} concluido={carregar} />}
      {descartando && <DialogoDescartar id={id} fechar={() => setDescartando(false)} concluido={() => navigate({ to: "/conferencia" })} />}
      {quadro && c.empresa && <DialogoQuadro id={id} empresa={c.empresa} fechar={() => setQuadro(false)} concluido={carregar} />}
      {loteAberto && c.empresa && <DialogoLote id={id} empresa={c.empresa} itens={dados.itens.filter((i) => lote.has(i.id))} fechar={() => setLoteAberto(false)} concluido={(r) => { novaRevisao(r); carregar(); }} />}
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

type Lado = { nome: string; cpf: string | null; re: string; cargo: string; empresa: string | null; admissao?: string | null; status?: string } | null;
function Lado({ titulo, d, nomeDifere, cpfDifere }: { titulo: string; d: Lado; nomeDifere?: boolean; cpfDifere?: boolean }) {
  return (
    <div className="min-w-0 text-sm">
      <div className="text-[10px] font-bold uppercase tracking-widest text-oak-dark/60">{titulo}</div>
      {!d ? <p className="text-oak-dark/50 mt-1">Sem registro</p> : (
        <div className="mt-1 space-y-0.5">
          <p className={`break-words ${nomeDifere ? "text-amber-800 font-medium" : ""}`}>{d.nome || "—"}</p>
          <p className={`tabular-nums ${cpfDifere ? "text-amber-800 font-medium" : ""}`}>CPF {d.cpf || "—"}</p>
          <p className="text-xs text-oak-dark/60 break-words">RE {d.re || "—"} · {d.cargo || "—"}{d.empresa ? ` · ${d.empresa}` : ""}</p>
          {d.admissao && <p className="text-xs text-oak-dark/60">Admissão {formatarData(d.admissao)}</p>}
          {d.status && <p className="text-xs text-oak-dark/60">{d.status}</p>}
        </div>
      )}
    </div>
  );
}

function ItemCard({ item: i, aberta, podeInativar, aoAprovar, decidir, selecionado, selecionar }: {
  item: Item; aberta: boolean; podeInativar: boolean; aoAprovar: (a: Acao) => void; decidir: (i: Item, d: string) => Promise<boolean>;
  selecionado: boolean; selecionar?: (v: boolean) => void;
}) {
  const folha = i.folha, atual = i.atual;
  const editavel = aberta && i.decisao !== "SEM_ACAO";
  // inativar só aparece com quadro completo confirmado (o banco confere de novo)
  const opcoes = i.opcoes.filter((a) => a !== "INATIVAR" || podeInativar);
  return (
    <li className="bg-card border border-oak-light rounded-2xl p-4 space-y-3" data-tipo={i.tipo}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="text-xs font-semibold flex items-center gap-2">
          {selecionar && <input type="checkbox" checked={selecionado} onChange={(e) => selecionar(e.target.checked)} aria-label={`Selecionar ${atual?.nome ?? ""}`} />}
          {TIPO_LABEL[i.tipo]}
        </span>
        <span className="text-xs text-oak-dark/70">
          {i.resultado === "APLICADO" ? "Aplicado" : i.resultado === "CONFLITO" ? `Conflito: ${i.resultado_detalhe}` : DECISAO[i.decisao]}
          {i.acao && ` · ${ACAO_LABEL[i.acao]}`}
        </span>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <Lado titulo="Planilha oficial" d={folha} nomeDifere={!!folha && !!atual && nomeNormalizado(folha.nome) !== nomeNormalizado(atual.nome)} cpfDifere={!!folha && !!atual && folha.cpf !== atual.cpf} />
        <Lado titulo="Folha Certa" d={atual} />
      </div>
      <p className="text-xs text-oak-dark/70">{i.motivo}{i.origens.length > 0 && ` · Planilha: ${i.origens.join(", ")}`}</p>
      {i.justificativa && <p className="text-xs">Justificativa: {i.justificativa}</p>}
      {editavel && (
        <div className="flex flex-wrap gap-2">
          {opcoes.map((a) => <button key={a} onClick={() => aoAprovar(a)} className={`${btn} bg-oak-dark text-primary-foreground`}>{ACAO_LABEL[a]}</button>)}
          {opcoes.length > 0 && <button onClick={() => decidir(i, "REJEITADA")} className={`${btn} bg-oak-medium/30`}>Rejeitar</button>}
          {opcoes.length === 0 && <button onClick={() => decidir(i, "REVISADA")} className={`${btn} bg-oak-medium/30`}>Marcar como revisado</button>}
        </div>
      )}
    </li>
  );
}

function DialogoAprovar({ item, acao, empresa, fechar, decidir }: {
  item: Item; acao: Acao; empresa: string | null; fechar: () => void; decidir: (i: Item, d: string, a: Acao, j?: string, x?: Record<string, string>) => Promise<boolean>;
}) {
  const [justificativa, setJustificativa] = useState("");
  const [re, setRe] = useState(item.folha?.re ?? "");
  const [cargo, setCargo] = useState<string>(item.folha?.cargo_sistema ?? cargoReconhecido(item.folha?.cargo ?? "") ?? "");
  const [salvando, setSalvando] = useState(false);
  const [fts, setFts] = useState<{ total: number; abertas: number } | null>(null);
  const cadastro = acao === "CADASTRAR";
  const precisa = exigeJustificativa(acao, item.tipo, [item.atual?.cargo, item.folha?.cargo_sistema]);

  useEffect(() => {
    if (!item.funcionario_id || cadastro) return;
    const fid = item.funcionario_id;
    Promise.all([
      supabase.from("ft").select("id", { count: "exact", head: true }).eq("funcionario_id", fid),
      supabase.from("ft").select("id", { count: "exact", head: true }).eq("funcionario_id", fid).or(`status.eq.PENDENTE,data_ft.gte.${new Date().toISOString().slice(0, 10)}`),
    ]).then(([a, b]) => setFts({ total: a.count ?? 0, abertas: b.count ?? 0 }));
  }, [item.funcionario_id, cadastro]);
  const valido = (!precisa || justificativaValida(justificativa)) && (!cadastro || (re.trim() && cargo));

  async function salvar() {
    setSalvando(true);
    const ok = await decidir(item, "APROVADA", acao, precisa ? justificativa.trim() : undefined, cadastro ? { re: re.trim(), cargo } : undefined);
    setSalvando(false);
    if (ok) fechar();
  }

  return (
    <Dialog open onOpenChange={(o) => !o && fechar()}>
      <DialogContent>
        <DialogHeader><DialogTitle>{ACAO_LABEL[acao]}</DialogTitle></DialogHeader>
        <div className="space-y-3 text-sm">
          <p className="break-words"><strong>{item.folha?.nome ?? item.atual?.nome}</strong>{(item.folha?.cpf ?? item.atual?.cpf) ? ` · CPF ${item.folha?.cpf ?? item.atual?.cpf}` : ""}</p>
          <p className="text-xs text-oak-dark/70">Esta aprovação só será aplicada quando você confirmar a importação.</p>
          {!!fts?.total && acao !== "INATIVAR" && <p className="text-xs text-amber-800">Este cadastro tem {fts.total} FT(s) vinculada(s). Elas não são alteradas e continuarão nele: confirme que é a mesma pessoa.</p>}
          {acao === "INATIVAR" && <p className="text-xs text-amber-800">O funcionário deixa de aparecer em novos lançamentos. {fts?.abertas ? `Tem ${fts.abertas} FT(s) pendente(s) ou futura(s), que não poderão ser aprovadas depois. ` : ""}As FTs históricas são preservadas.</p>}
          {acao === "ATUALIZAR_CARGO" && (
            <p className="text-xs text-amber-800">Cargo {item.atual?.cargo} → {item.folha?.cargo_sistema}. Valor da FT: {valor(item.atual?.cargo)} → {valor(item.folha?.cargo_sistema)}. FTs já lançadas mantêm o valor gravado.</p>
          )}
          {acao === "CORRIGIR_RE" && <p className="text-xs">RE {item.atual?.re} → {item.folha?.re}</p>}
          {acao === "CORRIGIR_EMPRESA" && <p className="text-xs">{item.atual?.empresa} (RE {item.atual?.re}) → {empresa} (RE {item.folha?.re})</p>}
          {cadastro && item.tipo === "PENDENCIA" && <p className="text-xs text-amber-800">Já existe cadastro com este nome e outro CPF. Cadastre só se for outra pessoa.</p>}
          {cadastro && (
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="text-xs">RE *<input value={re} onChange={(e) => setRe(e.target.value)} className={`${inp} mt-1`} /></label>
              <label className="text-xs">Cargo *
                <select value={cargo} onChange={(e) => setCargo(e.target.value)} className={`${inp} mt-1`}>
                  <option value="">Selecione</option>
                  {CARGOS.map((x) => <option key={x}>{x}</option>)}
                </select>
              </label>
              {!item.folha?.cargo_sistema && <p className="text-xs text-amber-800 sm:col-span-2">Cargo da planilha "{item.folha?.cargo}" não reconhecido: escolha o cargo correto.</p>}
              <p className="text-xs text-oak-dark/70 sm:col-span-2">Empresa: {empresa}</p>
            </div>
          )}
          {precisa && (
            <label className="block text-xs">Justificativa * (pelo menos {JUSTIFICATIVA_MIN} letras ou números)
              <textarea value={justificativa} onChange={(e) => setJustificativa(e.target.value)} rows={3} className={`${inp} mt-1`} />
            </label>
          )}
        </div>
        <DialogFooter>
          <button onClick={fechar} className={`${btn} bg-oak-medium/30`}>Cancelar</button>
          <button onClick={salvar} disabled={!valido || salvando} className={`${btn} bg-oak-dark text-primary-foreground`}>Aprovar</button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function DialogoAplicar({ id, revisao, primeira, aprovados, fechar, concluido }: { id: string; revisao: number; primeira: boolean; aprovados: Item[]; fechar: () => void; concluido: () => Promise<void> }) {
  const [texto, setTexto] = useState("");
  const [salvando, setSalvando] = useState(false);
  const esperado = `APLICAR ${aprovados.length}`;
  const contagem = Object.entries(aprovados.reduce<Record<string, number>>((m, i) => { const a = i.acao as string; m[a] = (m[a] ?? 0) + 1; return m; }, {}));

  async function aplicar() {
    setSalvando(true);
    const { data, error } = await supabase.rpc("conferencia_aplicar", { _id: id, _confirmacao: texto.trim(), _revisao: revisao });
    setSalvando(false);
    if (error) {
      toast.error(mensagemRegra(error.message));
      if (error.message.startsWith("CONFERENCIA_ALTERADA")) { fechar(); await concluido(); }
      return;
    }
    const r = data as unknown as ResultadoConferencia;
    if (r.conflitos) toast.warning(`${r.aplicados} aplicada(s), ${r.conflitos} em conflito.`);
    else toast.success(`${r.aplicados} alteração(ões) aplicada(s).`);
    fechar();
    await concluido();
  }

  return (
    <Dialog open onOpenChange={(o) => !o && fechar()}>
      <DialogContent>
        <DialogHeader><DialogTitle>{aprovados.length ? "Aplicar alterações" : "Concluir sem alterações"}</DialogTitle></DialogHeader>
        <div className="space-y-3 text-sm">
          {aprovados.length ? <ul className="space-y-1">{contagem.map(([a, n]) => <li key={a}>{ACAO_LABEL[a as Acao]}: <strong>{n}</strong></li>)}</ul>
            : <p>Nenhum item aprovado. A importação será encerrada sem alterar o cadastro{primeira ? " e registrada como a primeira desta empresa" : ""}.</p>}
          <p className="text-xs text-oak-dark/70">Itens cujo cadastro mudou depois da leitura não serão aplicados e ficarão como conflito. Nenhum funcionário é excluído, e as FTs não são alteradas.</p>
          <label className="block text-xs">Para confirmar, digite <strong>{esperado}</strong>
            <input value={texto} onChange={(e) => setTexto(e.target.value)} className={`${inp} mt-1`} aria-label="Confirmação" />
          </label>
        </div>
        <DialogFooter>
          <button onClick={fechar} className={`${btn} bg-oak-medium/30`}>Cancelar</button>
          <button onClick={aplicar} disabled={texto.trim() !== esperado || salvando} className={`${btn} bg-oak-dark text-primary-foreground`}>Confirmar</button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function DialogoQuadro({ id, empresa, fechar, concluido }: { id: string; empresa: string; fechar: () => void; concluido: () => Promise<void> }) {
  const [texto, setTexto] = useState("");
  const esperado = `QUADRO COMPLETO ${empresa}`;
  async function confirmar() {
    const { error } = await supabase.rpc("conferencia_confirmar_quadro", { _id: id, _confirmacao: texto.trim() });
    if (error) return void toast.error(mensagemRegra(error.message));
    toast.success("Quadro completo confirmado.");
    fechar();
    await concluido();
  }
  return (
    <Dialog open onOpenChange={(o) => !o && fechar()}>
      <DialogContent>
        <DialogHeader><DialogTitle>Confirmar quadro completo</DialogTitle></DialogHeader>
        <div className="space-y-3 text-sm">
          <p>Confirme apenas se esta planilha lista <strong>todos</strong> os funcionários de {empresa}. Com a confirmação, os ausentes poderão ser propostos para inativação, sempre com revisão e justificativa.</p>
          <label className="block text-xs">Digite <strong>{esperado}</strong>
            <input value={texto} onChange={(e) => setTexto(e.target.value)} className={`${inp} mt-1`} aria-label="Confirmação do quadro" />
          </label>
        </div>
        <DialogFooter>
          <button onClick={fechar} className={`${btn} bg-oak-medium/30`}>Cancelar</button>
          <button onClick={confirmar} disabled={texto.trim() !== esperado} className={`${btn} bg-oak-dark text-primary-foreground`}>Confirmar</button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function DialogoLote({ id, empresa, itens, fechar, concluido }: { id: string; empresa: string; itens: Item[]; fechar: () => void; concluido: (revisao: number | null) => void }) {
  const [justificativa, setJustificativa] = useState("");
  const [texto, setTexto] = useState("");
  const [salvando, setSalvando] = useState(false);
  const esperado = `INATIVAR ${itens.length} ${empresa}`;
  async function confirmar() {
    setSalvando(true);
    const { data, error } = await supabase.rpc("conferencia_inativar_lote", { _id: id, _itens: itens.map((i) => i.id), _justificativa: justificativa.trim(), _confirmacao: texto.trim() });
    setSalvando(false);
    if (error) return void toast.error(mensagemRegra(error.message));
    toast.success(`${itens.length} inativação(ões) aprovada(s). Aplique a importação para efetivar.`);
    fechar();
    concluido(data);
  }
  return (
    <Dialog open onOpenChange={(o) => !o && fechar()}>
      <DialogContent>
        <DialogHeader><DialogTitle>Aprovar inativação em lote</DialogTitle></DialogHeader>
        <div className="space-y-3 text-sm">
          <ul className="max-h-40 overflow-auto text-xs space-y-0.5">{itens.map((i) => <li key={i.id}>{i.atual?.nome} · RE {i.atual?.re}</li>)}</ul>
          <p className="text-xs text-oak-dark/70">Cada funcionário recebe sua própria decisão e seu registro de auditoria. Nada é inativado antes de aplicar a importação.</p>
          <label className="block text-xs">Justificativa * (pelo menos {JUSTIFICATIVA_MIN} letras ou números)
            <textarea value={justificativa} onChange={(e) => setJustificativa(e.target.value)} rows={2} className={`${inp} mt-1`} />
          </label>
          <label className="block text-xs">Digite <strong>{esperado}</strong>
            <input value={texto} onChange={(e) => setTexto(e.target.value)} className={`${inp} mt-1`} aria-label="Confirmação do lote" />
          </label>
        </div>
        <DialogFooter>
          <button onClick={fechar} className={`${btn} bg-oak-medium/30`}>Cancelar</button>
          <button onClick={confirmar} disabled={!justificativaValida(justificativa) || texto.trim() !== esperado || salvando} className={`${btn} bg-oak-dark text-primary-foreground`}>Aprovar inativação</button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function DialogoDescartar({ id, fechar, concluido }: { id: string; fechar: () => void; concluido: () => void }) {
  const [motivo, setMotivo] = useState("");
  const [salvando, setSalvando] = useState(false);
  async function descartar() {
    setSalvando(true);
    const { error } = await supabase.rpc("conferencia_descartar", { _id: id, _motivo: motivo.trim() });
    setSalvando(false);
    if (error) return void toast.error(mensagemRegra(error.message));
    toast.success("Importação descartada. Nada foi aplicado.");
    concluido();
  }
  return (
    <Dialog open onOpenChange={(o) => !o && fechar()}>
      <DialogContent>
        <DialogHeader><DialogTitle>Descartar importação</DialogTitle></DialogHeader>
        <label className="block text-xs">Motivo * (pelo menos {JUSTIFICATIVA_MIN} letras ou números)
          <textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={3} className={`${inp} mt-1`} />
        </label>
        <DialogFooter>
          <button onClick={fechar} className={`${btn} bg-oak-medium/30`}>Cancelar</button>
          <button onClick={descartar} disabled={!justificativaValida(motivo) || salvando} className={`${btn} bg-oak-dark text-primary-foreground`}>Descartar</button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
