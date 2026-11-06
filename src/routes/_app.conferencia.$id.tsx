import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useCallback, useEffect, useMemo, useState } from "react";
import { format } from "date-fns";
import { toast } from "sonner";
import { ArrowLeft } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useAuth } from "@/lib/auth";
import { ACAO_LABEL, TIPO_LABEL, type Acao, type ConferenciaTela, type ItemTela, type ResultadoConferencia, type ResumoConferencia, type TipoItem } from "@/lib/conferencia";
import { lerConferencia } from "@/lib/conferencia.functions";
import { EMPRESAS, normalizarEmpresa } from "@/lib/empresas";
import { formatarData, JUSTIFICATIVA_MIN, justificativaValida, mensagemRegra } from "@/lib/funcionario-status";
import { CARGOS, cargoReconhecido, nomeNormalizado } from "@/lib/importacao-funcionarios";

export const Route = createFileRoute("/_app/conferencia/$id")({ component: ConferenciaDetalhe });

type Item = ItemTela;
type Dados = { conferencia: ConferenciaTela; itens: Item[] };

const PASSO = 50;
const inp = "w-full px-3 py-2 bg-sand rounded-xl text-sm border-none focus:outline-none focus:ring-2 focus:ring-oak-dark/20";
const btn = "px-3 py-2 rounded-xl text-xs font-medium disabled:opacity-50";
const FILTROS: { id: string; label: string; chave: keyof ResumoConferencia; tipos: TipoItem[] }[] = [
  { id: "corr", label: "Correspondências", chave: "correspondencias", tipos: ["CORRESPONDENTE"] },
  { id: "novo", label: "Novos", chave: "novos", tipos: ["NOVO"] },
  { id: "aus", label: "Ausentes", chave: "ausentes", tipos: ["AUSENTE"] },
  { id: "div", label: "Divergências", chave: "divergencias", tipos: ["DIVERGENCIA_NOME", "DIVERGENCIA_CPF"] },
  { id: "ina", label: "Inativos", chave: "inativos", tipos: ["INATIVO"] },
  { id: "dup", label: "Duplicidades", chave: "duplicidades", tipos: ["DUPLICADO"] },
  { id: "pen", label: "Pendências", chave: "pendencias", tipos: ["PENDENCIA"] },
];
const DECISAO: Record<string, string> = { PENDENTE: "Pendente", APROVADA: "Aprovado", REJEITADA: "Rejeitado", REVISADA: "Revisado", SEM_ACAO: "Sem ação" };
/** Mesma regra de conferencia_decidir: cadastrar a partir de uma pendência é possível homônimo. */
const exigeJustificativa = (a: Acao, t: TipoItem) => a === "CORRIGIR_CPF" || a === "PREENCHER_CPF" || a === "REATIVAR" || (a === "CADASTRAR" && t === "PENDENCIA");

function ConferenciaDetalhe() {
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

  const carregar = useCallback(async () => {
    try {
      setDados(await lerConferencia({ data: { id } }));
    } catch {
      toast.error("Não foi possível carregar a conferência.");
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
  if (dados === null) return <div className="text-sm text-muted-foreground">Conferência não encontrada.</div>;

  const c = dados.conferencia;
  const aberta = c.status === "ABERTA";
  const aprovados = dados.itens.filter((i) => i.decisao === "APROVADA");

  async function decidir(item: Item, decisao: string, acao?: Acao, justificativa?: string, extra?: Record<string, string>) {
    const { error } = await supabase.rpc("conferencia_decidir", { _item: item.id, _decisao: decisao, _acao: acao, _justificativa: justificativa, _dados: extra });
    if (error) { toast.error(mensagemRegra(error.message)); return false; }
    setDados((d) => d && { ...d, itens: d.itens.map((i) => (i.id === item.id ? { ...i, decisao, acao: acao ?? null, justificativa: justificativa ?? null } : i)) });
    return true;
  }

  return (
    <div className="space-y-6 max-w-5xl pb-24">
      <div>
        <Link to="/conferencia" className="text-xs text-oak-dark/60 hover:underline inline-flex items-center gap-1"><ArrowLeft className="size-3" /> Conferências</Link>
        <h1 className="text-2xl font-light tracking-tight mt-2 break-words">{c.arquivo_nome}</h1>
        <p className="text-sm text-muted-foreground mt-1">
          {format(new Date(c.criada_em), "dd/MM/yyyy HH:mm")} · {aberta ? "Em revisão" : c.status === "CONCLUIDA" ? "Concluída" : "Descartada"}
          {c.resultado && ` · ${c.resultado.aplicados} aplicada(s), ${c.resultado.conflitos} conflito(s)`}
          {c.motivo_descarte && ` · ${c.motivo_descarte}`}
        </p>
      </div>

      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <Cartao label="Total na folha" valor={c.resumo.total_folha} ativo={filtro === "todos"} onClick={() => { setFiltro("todos"); setLimite(PASSO); }} />
        {FILTROS.map((f) => <Cartao key={f.id} label={f.label} valor={c.resumo[f.chave]} ativo={filtro === f.id} onClick={() => { setFiltro(f.id); setLimite(PASSO); }} />)}
      </div>

      {filtro === "aus" && <p className="text-sm bg-sand/50 rounded-xl p-3">Ausentes são apenas sinalizados: uma folha isolada não comprova desligamento e a Conferência não inativa ninguém.</p>}

      <input value={busca} onChange={(e) => { setBusca(e.target.value); setLimite(PASSO); }} placeholder="Buscar por nome, RE ou parte do CPF" className={inp} aria-label="Buscar" />

      {visiveis.length === 0 ? <p className="text-sm text-muted-foreground">Nenhum item neste filtro.</p> : (
        <ul className="space-y-3">
          {visiveis.slice(0, limite).map((i) => (
            <ItemCard key={i.id} item={i} aberta={aberta} aoAprovar={(acao) => setAprovar({ item: i, acao })} decidir={decidir} />
          ))}
        </ul>
      )}
      {visiveis.length > limite && (
        <button onClick={() => setLimite((l) => l + PASSO)} className={`${btn} bg-oak-medium/30 w-full`}>Mostrar mais ({visiveis.length - limite} restantes)</button>
      )}

      {aberta && (
        <div className="sticky bottom-0 bg-card border border-oak-light rounded-2xl p-3 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <span className="text-sm"><strong>{aprovados.length}</strong> item(ns) aprovado(s)</span>
          <div className="flex gap-2">
            <button onClick={() => setDescartando(true)} className={`${btn} flex-1 sm:flex-none bg-oak-medium/30`}>Descartar</button>
            <button onClick={() => setAplicando(true)} disabled={aprovados.length === 0} className={`${btn} flex-1 sm:flex-none bg-oak-dark text-primary-foreground`}>Aplicar alterações</button>
          </div>
        </div>
      )}

      {aprovar && <DialogoAprovar {...aprovar} fechar={() => setAprovar(null)} decidir={decidir} />}
      {aplicando && <DialogoAplicar id={id} aprovados={aprovados} fechar={() => setAplicando(false)} concluido={carregar} />}
      {descartando && <DialogoDescartar id={id} fechar={() => setDescartando(false)} concluido={() => navigate({ to: "/conferencia" })} />}
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

function Lado({ titulo, d, nomeDifere, cpfDifere }: { titulo: string; d: { nome: string; cpf: string | null; re: string; cargo: string; empresa: string | null; admissao?: string | null; status?: string } | null; nomeDifere?: boolean; cpfDifere?: boolean }) {
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

function ItemCard({ item: i, aberta, aoAprovar, decidir }: { item: Item; aberta: boolean; aoAprovar: (a: Acao) => void; decidir: (i: Item, d: string) => Promise<boolean> }) {
  const folha = i.folha, atual = i.atual;
  const editavel = aberta && i.decisao !== "SEM_ACAO";
  return (
    <li className="bg-card border border-oak-light rounded-2xl p-4 space-y-3" data-tipo={i.tipo}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="text-xs font-semibold">{TIPO_LABEL[i.tipo]}</span>
        <span className="text-xs text-oak-dark/70">
          {i.resultado === "APLICADO" ? "Aplicado" : i.resultado === "CONFLITO" ? `Conflito: ${i.resultado_detalhe}` : DECISAO[i.decisao]}
          {i.acao && ` · ${ACAO_LABEL[i.acao]}`}
        </span>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <Lado titulo="Folha" d={i.folha} nomeDifere={!!folha && !!atual && nomeNormalizado(folha.nome) !== nomeNormalizado(atual.nome)} cpfDifere={!!folha && !!atual && folha.cpf !== atual.cpf} />
        <Lado titulo="Folha Certa" d={i.atual} />
      </div>
      <p className="text-xs text-oak-dark/70">{i.motivo}{i.origens.length > 0 && ` · Planilha: ${i.origens.join(", ")}`}</p>
      {i.justificativa && <p className="text-xs">Justificativa: {i.justificativa}</p>}
      {editavel && (
        <div className="flex flex-wrap gap-2">
          {i.opcoes.map((a) => <button key={a} onClick={() => aoAprovar(a)} className={`${btn} bg-oak-dark text-primary-foreground`}>{ACAO_LABEL[a]}</button>)}
          {i.opcoes.length > 0 && <button onClick={() => decidir(i, "REJEITADA")} className={`${btn} bg-oak-medium/30`}>Rejeitar</button>}
          {i.opcoes.length === 0 && <button onClick={() => decidir(i, "REVISADA")} className={`${btn} bg-oak-medium/30`}>Marcar como revisado</button>}
        </div>
      )}
    </li>
  );
}

function DialogoAprovar({ item, acao, fechar, decidir }: { item: Item; acao: Acao; fechar: () => void; decidir: (i: Item, d: string, a: Acao, j?: string, x?: Record<string, string>) => Promise<boolean> }) {
  const [justificativa, setJustificativa] = useState("");
  const [re, setRe] = useState(item.folha?.re ?? "");
  const [cargo, setCargo] = useState<string>(cargoReconhecido(item.folha?.cargo ?? "") ?? "");
  const [empresa, setEmpresa] = useState<string>(normalizarEmpresa(item.folha?.empresa) ?? "");
  const [salvando, setSalvando] = useState(false);
  const [fts, setFts] = useState<number | null>(null);
  const cadastro = acao === "CADASTRAR";
  const precisa = exigeJustificativa(acao, item.tipo);

  useEffect(() => {
    if (!item.funcionario_id || cadastro) return;
    supabase.from("ft").select("id", { count: "exact", head: true }).eq("funcionario_id", item.funcionario_id).then(({ count }) => setFts(count ?? null));
  }, [item.funcionario_id, cadastro]);
  const valido = (!precisa || justificativaValida(justificativa)) && (!cadastro || (re.trim() && cargo));

  async function salvar() {
    setSalvando(true);
    const ok = await decidir(item, "APROVADA", acao, precisa ? justificativa.trim() : undefined, cadastro ? { re: re.trim(), cargo, empresa } : undefined);
    setSalvando(false);
    if (ok) fechar();
  }

  return (
    <Dialog open onOpenChange={(o) => !o && fechar()}>
      <DialogContent>
        <DialogHeader><DialogTitle>{ACAO_LABEL[acao]}</DialogTitle></DialogHeader>
        <div className="space-y-3 text-sm">
          <p className="break-words"><strong>{item.folha?.nome}</strong>{item.folha?.cpf ? ` · CPF ${item.folha.cpf}` : ""}</p>
          <p className="text-xs text-oak-dark/70">Esta aprovação só será aplicada quando você confirmar a conferência.</p>
          {!!fts && <p className="text-xs text-amber-800">Este cadastro tem {fts} FT(s) vinculada(s). Elas não são alteradas e continuarão nele: confirme que é a mesma pessoa.</p>}
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
              <label className="text-xs sm:col-span-2">Empresa
                <select value={empresa} onChange={(e) => setEmpresa(e.target.value)} className={`${inp} mt-1`}>
                  <option value="">Não informada</option>
                  {EMPRESAS.map((x) => <option key={x}>{x}</option>)}
                </select>
              </label>
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

function DialogoAplicar({ id, aprovados, fechar, concluido }: { id: string; aprovados: Item[]; fechar: () => void; concluido: () => Promise<void> }) {
  const [texto, setTexto] = useState("");
  const [salvando, setSalvando] = useState(false);
  const esperado = `APLICAR ${aprovados.length}`;
  const contagem = Object.entries(aprovados.reduce<Record<string, number>>((m, i) => { const a = i.acao as string; m[a] = (m[a] ?? 0) + 1; return m; }, {}));

  async function aplicar() {
    setSalvando(true);
    const { data, error } = await supabase.rpc("conferencia_aplicar", { _id: id, _confirmacao: texto.trim() });
    setSalvando(false);
    if (error) return void toast.error(mensagemRegra(error.message));
    const r = data as unknown as ResultadoConferencia;
    if (r.conflitos) toast.warning(`${r.aplicados} aplicada(s), ${r.conflitos} em conflito.`);
    else toast.success(`${r.aplicados} alteração(ões) aplicada(s).`);
    fechar();
    await concluido();
  }

  return (
    <Dialog open onOpenChange={(o) => !o && fechar()}>
      <DialogContent>
        <DialogHeader><DialogTitle>Aplicar alterações</DialogTitle></DialogHeader>
        <div className="space-y-3 text-sm">
          <ul className="space-y-1">{contagem.map(([a, n]) => <li key={a}>{ACAO_LABEL[a as Acao]}: <strong>{n}</strong></li>)}</ul>
          <p className="text-xs text-oak-dark/70">Itens cujo cadastro mudou depois da leitura não serão aplicados e ficarão como conflito. Nenhum funcionário será inativado ou excluído, e as FTs não são alteradas.</p>
          <label className="block text-xs">Para confirmar, digite <strong>{esperado}</strong>
            <input value={texto} onChange={(e) => setTexto(e.target.value)} className={`${inp} mt-1`} aria-label="Confirmação" />
          </label>
        </div>
        <DialogFooter>
          <button onClick={fechar} className={`${btn} bg-oak-medium/30`}>Cancelar</button>
          <button onClick={aplicar} disabled={texto.trim() !== esperado || salvando} className={`${btn} bg-oak-dark text-primary-foreground`}>Confirmar aplicação</button>
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
    toast.success("Conferência descartada. Nada foi aplicado.");
    concluido();
  }
  return (
    <Dialog open onOpenChange={(o) => !o && fechar()}>
      <DialogContent>
        <DialogHeader><DialogTitle>Descartar conferência</DialogTitle></DialogHeader>
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
