
-- ============================================
-- EXTENSÕES
-- ============================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================
-- FUNCIONARIOS: status (ativo/ferias), cargo controlado, posto controlado
-- ============================================
ALTER TABLE public.funcionarios
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'ativo'
    CHECK (status IN ('ativo', 'ferias'));

-- manter status_ativo sincronizado para retro-compat
UPDATE public.funcionarios SET status = CASE WHEN status_ativo THEN 'ativo' ELSE 'ferias' END;

-- check de cargo (lista fechada)
ALTER TABLE public.funcionarios
  DROP CONSTRAINT IF EXISTS funcionarios_cargo_check;
ALTER TABLE public.funcionarios
  ADD CONSTRAINT funcionarios_cargo_check
  CHECK (cargo IN ('Vigilante','Porteiro','ASG','Recepcionista','Manutencista','Freelancer'));

-- check de posto (lista fechada também — mesmo conjunto solicitado)
ALTER TABLE public.funcionarios
  DROP CONSTRAINT IF EXISTS funcionarios_posto_check;
ALTER TABLE public.funcionarios
  ADD CONSTRAINT funcionarios_posto_check
  CHECK (posto_servico IS NULL OR posto_servico IN ('Vigilante','Porteiro','ASG','Recepcionista','Manutencista','Freelancer'));

-- ============================================
-- FT: posto onde ocorreu a falta + valor pago
-- ============================================
ALTER TABLE public.ft
  ADD COLUMN IF NOT EXISTS posto_falta TEXT,
  ADD COLUMN IF NOT EXISTS valor_pago NUMERIC NOT NULL DEFAULT 0;

-- ============================================
-- PROFILES: username + ativo
-- ============================================
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS username TEXT,
  ADD COLUMN IF NOT EXISTS ativo BOOLEAN NOT NULL DEFAULT true;

CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_unique ON public.profiles(LOWER(username)) WHERE username IS NOT NULL;

-- ============================================
-- FUNÇÃO: valor fixo por cargo
-- ============================================
CREATE OR REPLACE FUNCTION public.valor_folga_por_cargo(_cargo TEXT)
RETURNS NUMERIC
LANGUAGE SQL
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE _cargo
    WHEN 'Vigilante' THEN 200.00
    WHEN 'Porteiro' THEN 150.00
    WHEN 'ASG' THEN 130.00
    WHEN 'Recepcionista' THEN 150.00
    WHEN 'Manutencista' THEN 130.00
    WHEN 'Freelancer' THEN 150.00
    ELSE 0
  END
$$;
REVOKE EXECUTE ON FUNCTION public.valor_folga_por_cargo(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.valor_folga_por_cargo(TEXT) TO authenticated;

-- ============================================
-- TRIGGER: preenche valor_pago, bloqueia limite mensal e férias
-- ============================================
CREATE OR REPLACE FUNCTION public.tg_ft_before_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cargo TEXT;
  v_status TEXT;
  v_count INT;
  v_is_gestor BOOLEAN;
BEGIN
  -- buscar cargo + status do funcionário que está cobrindo
  SELECT cargo, status INTO v_cargo, v_status
  FROM public.funcionarios WHERE id = NEW.funcionario_id;

  IF v_cargo IS NULL THEN
    RAISE EXCEPTION 'Funcionário inválido';
  END IF;

  -- aplicar valor fixo pelo cargo (sempre sobrescreve para garantir consistência)
  NEW.valor_pago := public.valor_folga_por_cargo(v_cargo);

  -- limite mensal de 4 movimentações por RE que está cobrindo
  SELECT COUNT(*) INTO v_count
  FROM public.ft
  WHERE funcionario_id = NEW.funcionario_id
    AND status <> 'CANCELADA'
    AND date_trunc('month', data_ft) = date_trunc('month', NEW.data_ft);

  IF v_count >= 4 THEN
    RAISE EXCEPTION 'LIMITE_MENSAL: Este funcionário já atingiu o limite de 4 movimentações no mês.';
  END IF;

  -- se funcionário que cobre está de férias, exigir gestor
  IF v_status = 'ferias' THEN
    SELECT public.has_role(NEW.lancado_por, 'gestor'::app_role) INTO v_is_gestor;
    IF NOT v_is_gestor THEN
      RAISE EXCEPTION 'PERMISSAO_FERIAS: Funcionário está de férias. Apenas um Gestor pode lançar esta movimentação.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.tg_ft_before_insert() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_ft_before_insert ON public.ft;
CREATE TRIGGER trg_ft_before_insert
  BEFORE INSERT ON public.ft
  FOR EACH ROW EXECUTE FUNCTION public.tg_ft_before_insert();

-- ============================================
-- AJUSTE: handle_new_user agora cria com role 'apontamento' por padrão
-- (mas vamos remover signup público — só admin cria)
-- ============================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_username TEXT;
  v_role app_role;
BEGIN
  v_username := COALESCE(NEW.raw_user_meta_data->>'username', split_part(NEW.email, '@', 1));
  v_role := COALESCE((NEW.raw_user_meta_data->>'role')::app_role, 'apontamento'::app_role);

  INSERT INTO public.profiles (id, nome, email, username, ativo)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'nome', v_username), NEW.email, v_username, true);

  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, v_role);

  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================
-- Garantir search_path nas demais SECURITY DEFINER (boa prática)
-- ============================================
ALTER FUNCTION public.has_role(uuid, app_role) SET search_path = public;
ALTER FUNCTION public.tg_ft_log_history() SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.tg_ft_log_history() FROM PUBLIC;

-- ============================================
-- POLÍTICAS RLS (atualizadas para os novos perfis)
-- ============================================

-- ft: INSERT só gestor ou supervisor
DROP POLICY IF EXISTS "Auth insert ft" ON public.ft;
CREATE POLICY "Insert ft gestor ou supervisor"
  ON public.ft FOR INSERT TO authenticated
  WITH CHECK (
    lancado_por = auth.uid()
    AND (public.has_role(auth.uid(), 'gestor'::app_role) OR public.has_role(auth.uid(), 'supervisor'::app_role))
  );

-- ft: UPDATE só gestor
DROP POLICY IF EXISTS "Auth update ft" ON public.ft;
CREATE POLICY "Update ft gestor"
  ON public.ft FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'gestor'::app_role));

-- funcionarios: INSERT/UPDATE só gestor
DROP POLICY IF EXISTS "Auth insert funcionarios" ON public.funcionarios;
DROP POLICY IF EXISTS "Auth update funcionarios" ON public.funcionarios;
CREATE POLICY "Insert funcionarios gestor"
  ON public.funcionarios FOR INSERT TO authenticated
  WITH CHECK (public.has_role(auth.uid(), 'gestor'::app_role));
CREATE POLICY "Update funcionarios gestor"
  ON public.funcionarios FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'gestor'::app_role));

-- profiles: gestor pode ver/atualizar todos
DROP POLICY IF EXISTS "Gestor manage profiles" ON public.profiles;
CREATE POLICY "Gestor manage profiles"
  ON public.profiles FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'gestor'::app_role))
  WITH CHECK (public.has_role(auth.uid(), 'gestor'::app_role));

-- ============================================
-- SEED: usuário admin inicial
-- ============================================
DO $$
DECLARE
  v_user_id UUID := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    is_super_admin, confirmation_token, email_change, email_change_token_new, recovery_token
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    v_user_id,
    'authenticated', 'authenticated',
    'admin@interno.local',
    crypt('Ab783514', gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('username','admin','nome','Administrador','role','gestor'),
    false, '', '', '', ''
  );

  INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
  VALUES (
    gen_random_uuid(),
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', 'admin@interno.local'),
    'email',
    v_user_id::text,
    now(), now(), now()
  );
END $$;
