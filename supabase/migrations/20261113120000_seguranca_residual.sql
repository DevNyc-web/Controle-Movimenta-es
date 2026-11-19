-- SEGURANÇA RESIDUAL (Fase 1A): fecha a falsificação de registros em audit_logs e ft_historico pela API de cliente.
-- Antes: qualquer conta logada (inclusive desativada) inseria nas duas tabelas com autor, ação, status e data escolhidos.
--   * audit_logs: sem escrita por anon/authenticated. Quem grava continua gravando: gatilhos (tg_audit_row -> log_audit) e o
--     servidor com a chave de serviço (admin.server.ts).
--   * ft_historico: sem UPDATE/DELETE/TRUNCATE por anon/authenticated. INSERT de authenticated fica SÓ para o registro que o app
--     em produção (origin/main, _app.ft.$id.tsx salvarCorrecao) grava depois de corrigir valores: VALORES_CORRIGIDOS, pelo
--     próprio Gestor ativo, com a data do momento, sem status, em FT PENDENTE. Os demais registros vêm dos gatilhos
--     (tg_ft_log_history) e das RPCs de cancelamento, que não dependem dessas permissões.
--   * Não muda: leitura (SELECT), service_role, funções, gatilhos e dados.
-- Isolada e independente de ordem: hoje sozinha em produção (depois do hotfix 20261109200000), ou depois de 20261105120100
-- (que remove as duas políticas, revoga o INSERT do histórico e passa VALORES_CORRIGIDOS para gatilho, junto do frontend novo).
-- Políticas: ALTER só se existirem e mantendo o nome, porque 20261105120100 faz DROP POLICY delas (sem IF EXISTS) depois.
-- Reversão: supabase/rollback/20261113120000_rollback.sql.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- 0. Os gravadores legítimos precisam ignorar RLS e permissões do cliente: SECURITY DEFINER do dono das tabelas
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.log_audit(text,text,text,text,jsonb,jsonb,text)', 'public.tg_audit_row()', 'public.tg_ft_log_history()'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = to_regprocedure(f) AND p.prosecdef
                     AND p.proowner = (SELECT relowner FROM pg_class WHERE oid = 'public.audit_logs'::regclass)
                     AND p.proowner = (SELECT relowner FROM pg_class WHERE oid = 'public.ft_historico'::regclass)) THEN
      RAISE EXCEPTION 'Abortado: % não é SECURITY DEFINER do dono de audit_logs/ft_historico; os registros legítimos parariam.', f;
    END IF;
  END LOOP;
END $$;

-- 1. Políticas de inserção
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'audit_logs' AND policyname = 'Auth insert audit') THEN
    EXECUTE $p$ALTER POLICY "Auth insert audit" ON public.audit_logs WITH CHECK (false)$p$;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'ft_historico' AND policyname = 'Auth insert historico') THEN
    EXECUTE $p$ALTER POLICY "Auth insert historico" ON public.ft_historico WITH CHECK (
          acao = 'VALORES_CORRIGIDOS'
      AND alterado_por = (SELECT auth.uid())
      AND status_anterior IS NULL AND status_novo IS NULL
      AND created_at = now()
      AND (SELECT public.has_role(auth.uid(), 'gestor'::public.app_role))
      AND EXISTS (SELECT 1 FROM public.ft f WHERE f.id = ft_historico.ft_id AND f.status = 'PENDENTE'::public.ft_status)
    )$p$;
  END IF;
END $$;

-- 2. Permissões de escrita (TRUNCATE não passa pela RLS; REVOKE na tabela também remove as concessões por coluna)
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.audit_logs FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.ft_historico FROM anon;
REVOKE UPDATE, DELETE, TRUNCATE ON public.ft_historico FROM authenticated;

-- 3. Guardas
DO $$
DECLARE t text; p text;
BEGIN
  FOREACH t IN ARRAY ARRAY['public.audit_logs', 'public.ft_historico'] LOOP
    FOREACH p IN ARRAY ARRAY['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'] LOOP
      IF has_table_privilege('anon', t, p) OR (has_table_privilege('authenticated', t, p) AND NOT (t = 'public.ft_historico' AND p = 'INSERT')) THEN
        RAISE EXCEPTION 'Abortado: anon/authenticated ainda tem % em %.', p, t;
      END IF;
    END LOOP;
    IF has_any_column_privilege('anon', t, 'INSERT') OR has_any_column_privilege('anon', t, 'UPDATE')
       OR has_any_column_privilege('authenticated', t, 'UPDATE')
       OR (t = 'public.audit_logs' AND has_any_column_privilege('authenticated', t, 'INSERT')) THEN
      RAISE EXCEPTION 'Abortado: escrita por coluna em %.', t;
    END IF;
  END LOOP;
  IF has_function_privilege('anon', 'public.log_audit(text,text,text,text,jsonb,jsonb,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.log_audit(text,text,text,text,jsonb,jsonb,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Abortado: cliente executa log_audit.';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND cmd IN ('INSERT', 'ALL') AND coalesce(with_check, qual, 'true') <> 'false'
              AND (tablename = 'audit_logs' OR (tablename = 'ft_historico' AND coalesce(with_check, qual, 'true') !~ 'VALORES_CORRIGIDOS'))) THEN
    RAISE EXCEPTION 'Abortado: ainda há política de inserção aberta em audit_logs/ft_historico.';
  END IF;
END $$;

COMMIT;
