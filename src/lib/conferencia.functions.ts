import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, Json } from "@/integrations/supabase/types";
import { assertGestor } from "./admin.server";
import { compararOficial, compararPagamentos, paraExibir, paraGravar, type ConferenciaTela, type FuncionarioBase, type ItemTela } from "./conferencia";
import { EMPRESAS } from "./empresas";
import { cpfValido, LIMITE_LINHAS } from "./importacao-funcionarios";
import { lerTodas } from "./relatorio";

const txt = (max: number) => z.string().max(max);
const Linha = z.object({
  origem: txt(300), nome: txt(300), cpf: txt(20), re: txt(60), cargo: txt(200), empresa: txt(300), admissao: txt(10).nullable(),
});
const comValidade = (ls: z.infer<typeof Linha>[]) => ls.map((l) => ({ ...l, cpfValido: cpfValido(l.cpf) }));

/** Cadastro com o JWT do usuário (RLS vale). O CPF não é legível pela tabela: vem da função do Gestor, que exige perfil ativo. */
async function lerCadastro(sb: SupabaseClient<Database>): Promise<FuncionarioBase[]> {
  const funcionarios = await lerTodas<Omit<FuncionarioBase, "cpf">>(async (from, to) => {
    const { data, error } = await sb.from("funcionarios").select("id, nome, re, cargo, empresa, status, data_admissao").order("id").range(from, to);
    if (error) throw new Error("Não foi possível ler o cadastro de funcionários.");
    return (data ?? []) as Omit<FuncionarioBase, "cpf">[];
  });
  const { data: cpfs, error } = await sb.rpc("funcionarios_cpfs");
  if (error) throw new Error("Não foi possível ler os CPFs do cadastro.");
  const cpfDe = new Map<string, string>((cpfs ?? []).map((c: { id: string; cpf: string }) => [c.id, c.cpf]));
  return funcionarios.map((f) => ({ ...f, cpf: cpfDe.get(f.id) ?? null }));
}

/** Importação oficial: compara no servidor e grava a revisão. Nada é aplicado aqui. */
export const criarConferencia = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input) =>
    z.object({
      arquivo: z.object({
        nome: z.string().min(1).max(255),
        empresa: z.enum(EMPRESAS),
        abas: z.array(txt(300)).max(300),
        mapeamento: z.record(z.string(), z.unknown()),
        ignoradas: z.number().int().min(0),
        total_impresso: z.number().int().min(0).nullable(),
      }),
      linhas: z.array(Linha).min(1).max(LIMITE_LINHAS),
    }).parse(input))
  .handler(async ({ context, data }) => {
    await assertGestor(context.supabase, context.userId);
    const funcionarios = await lerCadastro(context.supabase);
    const { data: reg, error: e } = await context.supabase.from("importacao_empresas").select("empresa").eq("empresa", data.arquivo.empresa);
    if (e) throw new Error("Não foi possível ler o registro de importações.");
    // O banco recalcula "primeira" e recusa inativação nela; aqui só evita propor o que seria recusado.
    const { itens, resumo } = compararOficial(comValidade(data.linhas), funcionarios, { empresa: data.arquivo.empresa, primeira: !reg?.length });
    const { data: id, error } = await context.supabase.rpc("conferencia_criar", {
      _arquivo: data.arquivo as unknown as Json, _resumo: resumo as unknown as Json, _itens: itens.map(paraGravar) as unknown as Json,
    });
    if (error) throw new Error(error.message);
    return { id: id as string };
  });

/** Itens sempre mascarados: o CPF completo de um item aberto fica no banco e não vai ao navegador. */
export const lerConferencia = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input) => z.object({ id: z.string().uuid() }).parse(input))
  .handler(async ({ context, data }) => {
    await assertGestor(context.supabase, context.userId);
    const { data: conferencia, error } = await context.supabase.from("conferencias").select("*").eq("id", data.id).maybeSingle();
    if (error) throw new Error("Não foi possível ler a conferência.");
    if (!conferencia) return null;
    const itens = await lerTodas<ItemTela>(async (from, to) => {
      const { data: rows, error: e } = await context.supabase.from("conferencia_itens").select("*")
        .eq("conferencia_id", data.id).order("ordem").range(from, to);
      if (e) throw new Error("Não foi possível ler os itens da conferência.");
      return (rows ?? []) as unknown as ItemTela[];
    });
    return { conferencia: conferencia as unknown as ConferenciaTela, itens: itens.map(paraExibir) };
  });

/** Conferência do Itaú: SOMENTE LEITURA. Não chama nenhuma função de escrita e não grava nada; devolve só dados mascarados. */
export const conferirPagamentos = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input) => z.object({ linhas: z.array(Linha).min(1).max(LIMITE_LINHAS) }).parse(input))
  .handler(async ({ context, data }) => {
    await assertGestor(context.supabase, context.userId);
    const { itens, resumo } = compararPagamentos(comValidade(data.linhas), await lerCadastro(context.supabase));
    return { resumo, itens: itens.map((i) => paraExibir(i)) };
  });
