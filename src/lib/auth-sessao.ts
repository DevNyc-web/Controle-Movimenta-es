/**
 * Um evento de autenticação só deve "carregar" (desmontar as telas) quando a CONTA muda: primeira carga, entrada,
 * saída ou outro usuário. Renovação/recuperação da mesma conta (o supabase-js emite SIGNED_IN ao voltar para a aba e
 * TOKEN_REFRESHED a cada renovação) não pode apagar o que está na tela (P4-F4: relatório do Itaú sumia ao trocar de aba).
 * `atual` = id da conta já aplicada; `undefined` enquanto nada foi aplicado.
 */
export function trocaDeConta(atual: string | null | undefined, nova: string | null): boolean {
  return atual === undefined || atual !== nova;
}
