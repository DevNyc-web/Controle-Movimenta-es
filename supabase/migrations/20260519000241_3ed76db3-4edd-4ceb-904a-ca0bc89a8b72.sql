
REVOKE EXECUTE ON FUNCTION public.log_audit(text, text, text, text, jsonb, jsonb, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tg_audit_row() FROM PUBLIC, anon, authenticated;
