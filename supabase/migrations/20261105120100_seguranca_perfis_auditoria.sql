-- Fase 1A: perfis e auditoria. NÃO APLICADA. Aplicar logo depois de 20261105120000, no mesmo horário.
-- Reversão: supabase/rollback/20261105120100_rollback.sql.
-- Depende de configuração fora do SQL: desligar o cadastro público no Supabase (Authentication > Sign In / Providers).
--
-- Regras:
--  * Nenhuma conta nasce com perfil nem ativa por trigger. Só o fluxo administrativo (service role) concede perfil e ativa.
--    raw_user_meta_data é editável pelo próprio usuário e não concede nada.
--  * Conta desativada perde o efeito dos perfis em toda a RLS, e não consegue se reativar.
--  * profiles, user_roles, audit_logs e ft_historico não têm escrita pela API de cliente. Quem escreve: service role ou trigger.
--  * Em produção (2026-11-05): 12 usuários, 12 profiles ativos, nenhum papel sem profile. Ninguém perde acesso.

BEGIN;

SET LOCAL lock_timeout = '5s';

LOCK TABLE public.ft, public.ft_historico, public.funcionarios, public.profiles, public.user_roles, public.audit_logs IN ACCESS EXCLUSIVE MODE;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.user_roles r WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = r.user_id)) THEN
    RAISE EXCEPTION 'Abortado: há perfil sem profile; has_role passaria a negar esse usuário. Revisar antes de migrar.';
  END IF;
END $$;

-- ============================================================
-- 1. Criação de conta: sem perfil e desativada
--    O service role cria a conta e, na sequência, grava ativo=true e o perfil (admin.functions.ts: createUser).
-- ============================================================
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

-- ============================================================
-- 2. Conta desativada não tem efeito de perfil
-- ============================================================
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

-- supervisor_restrito() usa has_role: sem o conta_ativa() aqui, supervisor desativado deixaria de ser "restrito" e veria todas as FTs.
CREATE OR REPLACE FUNCTION public.pode_ver_ft_data(_data DATE)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.conta_ativa() AND (NOT public.supervisor_restrito() OR public.ft_na_janela_supervisor(_data))
$$;

-- Mesma regra de pode_ver_ft_data, com (SELECT ...): avaliado uma vez por consulta, não por linha. Sem isto a leitura de FTs dobra de custo
-- (medido em 5.000 FTs), e o limite de statement_timeout para authenticated é 8s.
DROP POLICY "Read ft com janela supervisor" ON public.ft;
CREATE POLICY "Read ft com janela supervisor" ON public.ft FOR SELECT TO authenticated
  USING ((SELECT public.conta_ativa()) AND (NOT (SELECT public.supervisor_restrito()) OR public.ft_na_janela_supervisor(data_ft)));

DROP POLICY "Authenticated read funcionarios" ON public.funcionarios;
CREATE POLICY "Conta ativa le funcionarios" ON public.funcionarios FOR SELECT TO authenticated
  USING ((SELECT public.conta_ativa()));

-- ============================================================
-- 3. profiles e user_roles: escrita só pelo service role (fluxo administrativo do servidor)
-- ============================================================
DROP POLICY "Users update own profile" ON public.profiles;  -- permitia ativo=true na própria conta
DROP POLICY "Users insert own profile" ON public.profiles;
DROP POLICY "Gestor manage profiles" ON public.profiles;
CREATE POLICY "Gestor le profiles" ON public.profiles FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'gestor'::public.app_role));

DROP POLICY "Admins manage roles" ON public.user_roles;     -- permitia Admin se conceder Gestor

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.profiles, public.user_roles FROM anon, authenticated;

-- ============================================================
-- 4. audit_logs: só trigger (log_audit) e service role inserem; ninguém altera
-- ============================================================
DROP POLICY "Auth insert audit" ON public.audit_logs;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.audit_logs FROM anon, authenticated;
REVOKE UPDATE, DELETE, TRUNCATE ON public.audit_logs FROM service_role;

-- ============================================================
-- 5. ft_historico: só trigger insere; ninguém altera
--    A correção de valores, antes um segundo comando do frontend, passa a ser registrada aqui, na mesma transação.
--    Mesmo texto de descreverCorrecao (src/lib/ft-valor.ts).
-- ============================================================
DROP POLICY "Auth insert historico" ON public.ft_historico;
REVOKE INSERT, UPDATE ON public.ft_historico FROM anon, authenticated, service_role;
REVOKE TRUNCATE ON public.ft_cancelamento_solicitacoes FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.tg_ft_registrar_correcao()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_partes TEXT[] := '{}';
BEGIN
  IF NEW.valor_pago IS DISTINCT FROM OLD.valor_pago THEN
    v_partes := v_partes || format('Valor: R$ %s → R$ %s',
      translate(to_char(OLD.valor_pago, 'FM999,999,990.00'), ',.', '.,'),
      translate(to_char(NEW.valor_pago, 'FM999,999,990.00'), ',.', '.,'));
  END IF;
  IF NEW.pagamento_em_folha IS DISTINCT FROM OLD.pagamento_em_folha THEN
    v_partes := v_partes || format('Pagamento em folha: %s → %s',
      CASE WHEN OLD.pagamento_em_folha THEN 'Sim' ELSE 'Não' END,
      CASE WHEN NEW.pagamento_em_folha THEN 'Sim' ELSE 'Não' END);
  END IF;

  INSERT INTO public.ft_historico (ft_id, acao, alterado_por, observacao)
  VALUES (NEW.id, 'VALORES_CORRIGIDOS', auth.uid(), array_to_string(v_partes, ' · '));
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.tg_ft_registrar_correcao() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_ft_registrar_correcao
  AFTER UPDATE ON public.ft
  FOR EACH ROW
  WHEN (OLD.valor_pago IS DISTINCT FROM NEW.valor_pago OR OLD.pagamento_em_folha IS DISTINCT FROM NEW.pagamento_em_folha)
  EXECUTE FUNCTION public.tg_ft_registrar_correcao();

-- ============================================================
-- 6. Guarda final
-- ============================================================
DO $$
DECLARE r TEXT; t TEXT; p TEXT;
BEGIN
  FOREACH r IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    FOREACH t IN ARRAY ARRAY['public.profiles', 'public.user_roles', 'public.audit_logs', 'public.ft_historico'] LOOP
      FOREACH p IN ARRAY ARRAY['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'] LOOP
        IF has_table_privilege(r, t, p) THEN
          RAISE EXCEPTION 'Abortado: % ainda tem % em %.', r, p, t;
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
