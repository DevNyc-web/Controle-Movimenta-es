import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import type { Json } from "@/integrations/supabase/types";
import { assertGestor } from "./admin.server";
import { compararFolha, paraExibir, paraGravar, type ConferenciaTela, type FuncionarioBase, type ItemTela } from "./conferencia";
import { cpfValido, LIMITE_LINHAS } from "./importacao-funcionarios";
import { lerTodas } from "./relatorio";

const txt = (max: number) => z.string().max(max);
const Linha = z.object({
  origem: txt(300), nome: txt(300), cpf: txt(20), re: txt(60), cargo: txt(200), empresa: txt(300), admissao: txt(10).nullable(),
});

/** Compara no servidor, com o JWT do usuário: a tela não decide o que é divergência e a RLS vale na leitura do cadastro. */
export const criarConferencia = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input) =>
    z.object({
      arquivo: z.object({
        nome: z.string().min(1).max(255),
        abas: z.array(txt(300)).max(300),
        mapeamento: z.record(z.string(), z.unknown()),
        ignoradas: z.number().int().min(0),
        total_impresso: z.number().int().min(0).nullable(),
      }),
      linhas: z.array(Linha).min(1).max(LIMITE_LINHAS),
    }).parse(input))
  .handler(async ({ context, data }) => {
    await assertGestor(context.supabase, context.userId);
    const funcionarios = await lerTodas<FuncionarioBase>(async (from, to) => {
      const { data: rows, error } = await context.supabase.from("funcionarios")
        .select("id, nome, cpf, re, cargo, empresa, status, data_admissao").order("id").range(from, to);
      if (error) throw new Error("Não foi possível ler o cadastro de funcionários.");
      return (rows ?? []) as FuncionarioBase[];
    });
    const { itens, resumo } = compararFolha(data.linhas.map((l) => ({ ...l, cpfValido: cpfValido(l.cpf) })), funcionarios);
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
