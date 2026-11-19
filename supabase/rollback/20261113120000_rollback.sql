-- Reverte 20261113120000 (segurança residual) SOMENTE se 20261105120100 ainda NÃO foi aplicada (depois dela, o estado é o dela).
-- Não altera dados. Restaura as duas políticas de inserção (qualquer conta logada) e INSERT/UPDATE/DELETE de authenticated
-- (UPDATE/DELETE seguem sem política, como antes). De propósito NÃO restaura TRUNCATE de anon/authenticated (não usado pelo app;
-- ignora a RLS).
BEGIN;
SET LOCAL lock_timeout = '5s';
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND policyname = 'Conta ativa le funcionarios') THEN
    RAISE EXCEPTION 'Abortado: 20261105120100 já aplicada; reverter 20261113120000 isoladamente não se aplica.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'audit_logs' AND policyname = 'Auth insert audit')
     OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'ft_historico' AND policyname = 'Auth insert historico') THEN
    RAISE EXCEPTION 'Abortado: políticas "Auth insert audit"/"Auth insert historico" ausentes; estado inesperado.';
  END IF;
END $$;

ALTER POLICY "Auth insert audit" ON public.audit_logs WITH CHECK (auth.uid() IS NOT NULL);
ALTER POLICY "Auth insert historico" ON public.ft_historico WITH CHECK (auth.uid() IS NOT NULL);
GRANT INSERT, UPDATE, DELETE ON public.audit_logs TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.ft_historico TO authenticated;
COMMIT;
