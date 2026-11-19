-- HOTFIX DE SEGURANÇA (independente da Fase 1A e da Importação oficial). NÃO APLICADA EM PRODUÇÃO.
-- Fecha a elevação de privilégio pelo cadastro público:
--   1. handle_new_user não lê papel nem perfil ativo de raw_user_meta_data (controlado pelo cliente): cria o perfil DESATIVADO e
--      SEM papel. O fluxo legítimo (admin.functions.ts: createUser com a chave de serviço) grava perfil ativo e papel em seguida.
--   2. Conta sem perfil ativo não lê funcionários nem FTs e não tem efeito de papel (conta_ativa / has_role / pode_ver_ft_data).
--   3. Usuário não altera nem cria o próprio perfil; Admin não concede papel pela API; authenticated não grava profiles/user_roles.
-- Texto das funções IDÊNTICO ao de 20261105120100: a ordem de aplicação não importa (hoje sozinha em produção, ou depois dela).
-- Políticas: ALTER só se existirem (produção atual); 20261105120100 as remove/recria normalmente depois.
-- Reversão: supabase/rollback/20261109200000_rollback.sql (mantém o gatilho seguro).

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.user_roles r WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = r.user_id)) THEN
    RAISE EXCEPTION 'Abortado: há papel sem perfil; has_role passaria a negar esse usuário. Revisar antes.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.user_roles r JOIN public.profiles p ON p.id = r.user_id WHERE NOT p.ativo) THEN
    RAISE NOTICE 'Atenção: há contas com papel e perfil desativado; elas deixam de ter efeito de papel (comportamento pretendido).';
  END IF;
END $$;

-- 1. Criação de conta: sem papel e desativada (mesmo texto de 20261105120100)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_username TEXT;
BEGIN
  v_username := COALESCE(NEW.raw_user_meta_data->>'username', split_part(NEW.email, '@', 1));

  INSERT INTO public.profiles (id, nome, email, username, ativo)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'nome', v_username), NEW.email, v_username, false);

  RETURN NEW;
END;
$$;

-- 2. Conta desativada não tem efeito de papel nem leitura (mesmo texto de 20261105120100)
CREATE OR REPLACE FUNCTION public.conta_ativa()
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND ativo)
$$;
REVOKE EXECUTE ON FUNCTION public.conta_ativa() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.conta_ativa() TO authenticated;

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role public.app_role)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.user_roles r
      JOIN public.profiles p ON p.id = r.user_id
     WHERE r.user_id = _user_id AND r.role = _role AND p.ativo
  )
$$;

CREATE OR REPLACE FUNCTION public.pode_ver_ft_data(_data DATE)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.conta_ativa() AND (NOT public.supervisor_restrito() OR public.ft_na_janela_supervisor(_data))
$$;

-- 3. Políticas de produção atual (ALTER mantém o nome; 20261105120100 remove/recria depois)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'ft' AND policyname = 'Read ft com janela supervisor') THEN
    EXECUTE 'ALTER POLICY "Read ft com janela supervisor" ON public.ft USING ((SELECT public.conta_ativa()) AND (NOT (SELECT public.supervisor_restrito()) OR public.ft_na_janela_supervisor(data_ft)))';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'funcionarios' AND policyname = 'Authenticated read funcionarios') THEN
    EXECUTE 'ALTER POLICY "Authenticated read funcionarios" ON public.funcionarios USING ((SELECT public.conta_ativa()))';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'profiles' AND policyname = 'Users update own profile') THEN
    EXECUTE 'ALTER POLICY "Users update own profile" ON public.profiles USING (false) WITH CHECK (false)';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'profiles' AND policyname = 'Users insert own profile') THEN
    EXECUTE 'ALTER POLICY "Users insert own profile" ON public.profiles WITH CHECK (false)';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'user_roles' AND policyname = 'Admins manage roles') THEN
    EXECUTE 'ALTER POLICY "Admins manage roles" ON public.user_roles USING (false) WITH CHECK (false)';
  END IF;
END $$;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.profiles, public.user_roles FROM anon, authenticated;

-- 4. Guardas
DO $$
BEGIN
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'public.handle_new_user()'::regprocedure) ~* '(user_roles|raw_user_meta_data->>''role''|,\s*true\s*\))' THEN
    RAISE EXCEPTION 'Abortado: handle_new_user ainda atribui papel ou perfil ativo.';
  END IF;
  IF has_table_privilege('authenticated', 'public.user_roles', 'INSERT') OR has_table_privilege('authenticated', 'public.user_roles', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.profiles', 'INSERT') OR has_table_privilege('authenticated', 'public.profiles', 'UPDATE') THEN
    RAISE EXCEPTION 'Abortado: authenticated ainda grava em profiles/user_roles.';
  END IF;
END $$;

COMMIT;
