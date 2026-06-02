
-- Revoga execução pública/autenticada de funções de trigger e helpers internos
REVOKE EXECUTE ON FUNCTION public.tg_ft_log_history() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tg_ft_validate_status() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tg_ft_before_insert() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tg_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.valor_folga_por_cargo(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.valor_folga_por_cargo(text) TO authenticated;

-- has_role precisa ser invocável por autenticados (usado em policies)
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO authenticated;
