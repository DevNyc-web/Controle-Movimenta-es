import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { supabaseAdmin } from "@/integrations/supabase/client.server";

/** Nome de quem lançou a FT (ft.lancado_por, gravado no INSERT e exigido = auth.uid() pela RLS).
 *  A FT é lida com o cliente do usuário logado: se a RLS (janela do supervisor) não a mostra, nada é revelado.
 *  Só então o nome é buscado com a service role, porque profiles só é legível pelo próprio usuário ou por gestor.
 *  Devolve apenas o nome; null = não identificado. */
export const getLancadorFt = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input) => z.object({ ftId: z.string().uuid() }).parse(input))
  .handler(async ({ context, data }) => {
    const { data: ft } = await context.supabase.from("ft").select("lancado_por").eq("id", data.ftId).maybeSingle();
    if (!ft?.lancado_por) return { nome: null };
    const { data: p } = await supabaseAdmin.from("profiles").select("nome").eq("id", ft.lancado_por).maybeSingle();
    return { nome: p?.nome?.trim() || null };
  });
