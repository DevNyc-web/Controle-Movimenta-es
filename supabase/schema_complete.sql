-- =============================================================================
-- Folha Certa — Schema completo para recriar o banco no Supabase
-- Gerado a partir de supabase/migrations/* (estado final consolidado)
--
-- Uso: SQL Editor do Supabase → colar e executar em projeto vazio.
-- Requer: auth.users já existente (padrão Supabase).
-- Não inclui: DELETE de dados, reset de auth, seed de usuário admin.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Extensões
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- -----------------------------------------------------------------------------
-- Tipos enumerados
-- -----------------------------------------------------------------------------
CREATE TYPE public.app_role AS ENUM (
  'admin',
  'gestor',
  'rh',
  'apontamento',
  'supervisor'
);

CREATE TYPE public.ft_status AS ENUM (
  'PENDENTE',
  'APROVADA',
  'NEGADA',
  'CANCELADA'
);

-- -----------------------------------------------------------------------------
-- Tabelas
-- -----------------------------------------------------------------------------

-- Perfis de usuário (vinculados ao auth.users)
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nome TEXT NOT NULL,
  email TEXT NOT NULL,
  username TEXT,
  ativo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX profiles_username_unique
  ON public.profiles (LOWER(username))
  WHERE username IS NOT NULL;

-- Papéis / perfis de acesso
CREATE TABLE public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);

-- Funcionários
CREATE TABLE public.funcionarios (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome TEXT NOT NULL,
  cpf TEXT UNIQUE,
  re TEXT NOT NULL,
  cargo TEXT NOT NULL,
  setor TEXT,
  data_admissao DATE,
  turno TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'ativo'
    CHECK (status IN ('ativo', 'ferias')),
  status_ativo BOOLEAN NOT NULL DEFAULT true,
  supervisor TEXT,
  usa_banco_horas BOOLEAN NOT NULL DEFAULT false,
  banco_horas NUMERIC NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT funcionarios_cargo_check CHECK (
    cargo IN ('Vigilante', 'Porteiro', 'ASG', 'Recepcionista', 'Manutencista', 'Freelancer')
  )
);

-- Movimentações (FT)
CREATE TABLE public.ft (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  funcionario_id UUID NOT NULL REFERENCES public.funcionarios(id) ON DELETE CASCADE,
  funcionario_faltante_id UUID REFERENCES public.funcionarios(id) ON DELETE SET NULL,
  data_ft DATE NOT NULL,
  tipo_folga TEXT,
  motivo TEXT,
  status public.ft_status NOT NULL DEFAULT 'PENDENTE',
  horas_trabalhadas NUMERIC NOT NULL DEFAULT 0,
  horas_compensadas NUMERIC NOT NULL DEFAULT 0,
  observacao TEXT,
  escala_servico TEXT,
  posto_falta TEXT,
  valor_pago NUMERIC NOT NULL DEFAULT 0,
  aprovado_por UUID REFERENCES auth.users(id),
  lancado_por UUID REFERENCES auth.users(id),
  data_lancamento TIMESTAMPTZ NOT NULL DEFAULT now(),
  data_cancelamento TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (funcionario_id, data_ft),
  CONSTRAINT ft_posto_falta_check CHECK (
    posto_falta IS NULL OR posto_falta IN (
      'P10 - WECKERLE', 'P15 - COOPEROVOS', 'P19 ENGESIG AREA 2', 'P53 CENTRO ONCOLOGICO',
      'P63 DAG QUIMICA', 'P70 GALPÃO MOGI - DUTRA', 'P71 STRETCH SHRINK - SS FILMES',
      'P76 COSTA NAVARRO', 'P84 TERRA COMPANY', 'P93 PRESMETAL', 'P97 COND. SOL NASCENTE',
      'P100 SOX CONSULTÓRIA', 'P101 COND MANHATTAN / AREA 1', 'P105 COND. FIRENZE AREA 1',
      'P109 COND. MONTE REY', 'P111 RUD CORRENTES', 'P114 WEBER SAINT GOBAIN', 'P117 COND. ELLEGANCE',
      'P128 ENESA', 'P134 EDIFICIO GRIMBERG AREA 1', 'P136 WOLPAC AREA 2', 'P137 BLUE SKIES',
      'P145 RESOL QUIMICA AREA 2', 'P146 SPAZIO MIRAGE AREA 1', 'P147 IPIRANGA ONE AREA 1',
      'P158 COBRAL', 'P159 ATA SERVICE AREA 2', 'P161 COND. VILLAGIO ROSSI', 'P163 RESIDENCIA PKO AREA 1',
      'P164 FÁBRICA PKO', 'P165 TROPICAL FRESH', 'P169 AOPP AREA 1', 'P171 BOGNAR',
      'P172 REAL PARK RESERVA', 'P173 COND. HOME CLUB ITAPETY', 'P174 CONDOMINIO BELLA CITTA',
      'P180 CONDOMINIO METROPOLITAN', 'P182 PORTARIA ARUA AREA 2', 'P184 HELBOR TOWER', 'P185 CORPRINT',
      'P186 HELBOR LIFE CLUBE MOGILAR', 'P187 HELBOR IPOEMA CASAS', 'P188 COND. RES. PEDRA BELLA AREA 2',
      'P189 COND DO PORTO', 'P198 TOKIO MARINE SEGURADORA', 'P201 TINAGA AREA 2', 'P204 CONDOMINIO ORION',
      'P205 ALPES DA SERRA AREA 2', 'P207 RESIDENCIAL MAISON', 'P209 NEW FAMILY HOME',
      'P210 PARQUE DAS FIGUEIRAS', 'P211 COND. ESSENCE PRIME LIVING', 'P212 ATX TREFILADOS',
      'P213 SANTA CASA DE MOGI DAS CRUZES', 'P214 SITIO MARIO ROBERTO',
      'P215 MOGIANA - ESCOLA DE VIGILANTES', 'P216 MICROFILTER', 'P218 ZECODE', 'P220 COND AMARAIS 2',
      'P223 RESIDENCIA JOLIE', 'P224 HELBOR PATTEO MOGILAR SKY MALL & OFFICES',
      'P225 COND. COMBINATTO CHIARO', 'P226 COTAC ITAQUAQUECETUBA AREA 2', 'P227 INTEP AREA 2',
      'P228 COND. EDIFICIO ORQUIDEAS AREA 2', 'P229 COND. VILLAGE MONTPELLIER', 'P230 PLENA SAUDE ITAQUA',
      'P231 CONDOMINIO ESPANHA III AREA 1', 'P232 REFER', 'P233 MORADA MINEIRA',
      'P235 GD GIESECKE E DEVRIENT', 'P236 FLORA III AREA 1', 'P237 COND. EDIFICIO GRAND LOFT AREA 2',
      'P238 HONDA LEVESA SÃO MIGUEL AREA 2', 'P239 HONDA LEVESA SUZANO AREA 2', 'P240 GARCIQUIMICA AREA 2',
      'P241 RESIDENCIAL NOVA MOGI I', 'P242 HAPPY BRAZ CUBAS AREA 2', 'P243 HELBOR SPAZIO CLUB ALTO DO IPIRANGA',
      'P244 DOLCE VITA', 'P245 CONDOMINIO BONS VENTOS CLUBE', 'P246 COLÉGIO MILLENIUM CONSTRUTIVO',
      'P247 COND. GEORGIA', 'P248 VILAGIO DA SERRA AREA 2', 'P250 DROGARIA KOBAYASHI', 'P251 ACREDITAR FIDC AREA 1'
    )
  )
);

-- Histórico de status da FT
CREATE TABLE public.ft_historico (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ft_id UUID NOT NULL REFERENCES public.ft(id) ON DELETE CASCADE,
  acao TEXT NOT NULL,
  status_anterior public.ft_status,
  status_novo public.ft_status,
  alterado_por UUID REFERENCES auth.users(id),
  observacao TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Auditoria
CREATE TABLE public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID,
  username TEXT,
  role TEXT,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT,
  description TEXT,
  old_data JSONB,
  new_data JSONB,
  observacao TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_logs_created_at ON public.audit_logs (created_at DESC);
CREATE INDEX idx_audit_logs_user ON public.audit_logs (user_id);
CREATE INDEX idx_audit_logs_entity ON public.audit_logs (entity_type, entity_id);

-- -----------------------------------------------------------------------------
-- Funções
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role public.app_role)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role = _role
  );
$$;

CREATE OR REPLACE FUNCTION public.tg_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.tg_ft_validate_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF OLD.status = 'CANCELADA' AND NEW.status = 'APROVADA' THEN
    RAISE EXCEPTION 'FT cancelada não pode ser aprovada';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.tg_ft_log_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.ft_historico (ft_id, acao, status_novo, alterado_por)
    VALUES (NEW.id, 'CRIADA', NEW.status, NEW.lancado_por);
  ELSIF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO public.ft_historico (ft_id, acao, status_anterior, status_novo, alterado_por)
    VALUES (
      NEW.id,
      'STATUS_ALTERADO',
      OLD.status,
      NEW.status,
      COALESCE(NEW.aprovado_por, auth.uid())
    );
  END IF;
  RETURN NEW;
END;
$$;

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
  END;
$$;

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
  SELECT cargo, status INTO v_cargo, v_status
  FROM public.funcionarios
  WHERE id = NEW.funcionario_id;

  IF v_cargo IS NULL THEN
    RAISE EXCEPTION 'Funcionário inválido';
  END IF;

  NEW.valor_pago := public.valor_folga_por_cargo(v_cargo);

  SELECT COUNT(*) INTO v_count
  FROM public.ft
  WHERE funcionario_id = NEW.funcionario_id
    AND status <> 'CANCELADA'
    AND date_trunc('month', data_ft) = date_trunc('month', NEW.data_ft);

  IF v_count >= 4 THEN
    RAISE EXCEPTION 'LIMITE_MENSAL: Este funcionário já atingiu o limite de 4 movimentações no mês.';
  END IF;

  IF v_status = 'ferias' THEN
    SELECT public.has_role(NEW.lancado_por, 'gestor'::public.app_role) INTO v_is_gestor;
    IF NOT v_is_gestor THEN
      RAISE EXCEPTION 'PERMISSAO_FERIAS: Funcionário está de férias. Apenas um Gestor pode lançar esta movimentação.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_username TEXT;
  v_role public.app_role;
BEGIN
  v_username := COALESCE(NEW.raw_user_meta_data->>'username', split_part(NEW.email, '@', 1));
  v_role := COALESCE((NEW.raw_user_meta_data->>'role')::public.app_role, 'apontamento'::public.app_role);

  INSERT INTO public.profiles (id, nome, email, username, ativo)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'nome', v_username),
    NEW.email,
    v_username,
    true
  );

  INSERT INTO public.user_roles (user_id, role)
  VALUES (NEW.id, v_role);

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_audit(
  _action TEXT,
  _entity_type TEXT,
  _entity_id TEXT,
  _description TEXT DEFAULT NULL,
  _old JSONB DEFAULT NULL,
  _new JSONB DEFAULT NULL,
  _obs TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_username TEXT;
  v_role TEXT;
BEGIN
  IF v_uid IS NOT NULL THEN
    SELECT username INTO v_username FROM public.profiles WHERE id = v_uid;
    SELECT role::TEXT INTO v_role FROM public.user_roles WHERE user_id = v_uid LIMIT 1;
  END IF;

  INSERT INTO public.audit_logs (
    user_id, username, role, action, entity_type, entity_id,
    description, old_data, new_data, observacao
  )
  VALUES (
    v_uid, v_username, v_role, _action, _entity_type, _entity_id,
    _description, _old, _new, _obs
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.tg_audit_row()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_desc TEXT;
  v_id TEXT;
  v_entity TEXT := TG_TABLE_NAME;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_id := (to_jsonb(OLD)->>'id');
    v_desc := format('Excluiu registro em %s (id %s)', v_entity, v_id);
    PERFORM public.log_audit('DELETE', v_entity, v_id, v_desc, to_jsonb(OLD), NULL, NULL);
    RETURN OLD;
  ELSIF TG_OP = 'UPDATE' THEN
    v_id := (to_jsonb(NEW)->>'id');
    v_desc := format('Atualizou registro em %s (id %s)', v_entity, v_id);
    PERFORM public.log_audit('UPDATE', v_entity, v_id, v_desc, to_jsonb(OLD), to_jsonb(NEW), NULL);
    RETURN NEW;
  ELSE
    v_id := (to_jsonb(NEW)->>'id');
    v_desc := format('Criou registro em %s (id %s)', v_entity, v_id);
    PERFORM public.log_audit('INSERT', v_entity, v_id, v_desc, NULL, to_jsonb(NEW), NULL);
    RETURN NEW;
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- Triggers
-- -----------------------------------------------------------------------------

CREATE TRIGGER set_updated_at_profiles
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.tg_updated_at();

CREATE TRIGGER set_updated_at_funcionarios
  BEFORE UPDATE ON public.funcionarios
  FOR EACH ROW EXECUTE FUNCTION public.tg_updated_at();

CREATE TRIGGER set_updated_at_ft
  BEFORE UPDATE ON public.ft
  FOR EACH ROW EXECUTE FUNCTION public.tg_updated_at();

CREATE TRIGGER ft_validate_status
  BEFORE UPDATE ON public.ft
  FOR EACH ROW EXECUTE FUNCTION public.tg_ft_validate_status();

CREATE TRIGGER ft_log_history
  AFTER INSERT OR UPDATE ON public.ft
  FOR EACH ROW EXECUTE FUNCTION public.tg_ft_log_history();

CREATE TRIGGER trg_ft_before_insert
  BEFORE INSERT ON public.ft
  FOR EACH ROW EXECUTE FUNCTION public.tg_ft_before_insert();

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TRIGGER audit_ft
  AFTER INSERT OR UPDATE OR DELETE ON public.ft
  FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();

CREATE TRIGGER audit_funcionarios
  AFTER INSERT OR UPDATE OR DELETE ON public.funcionarios
  FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();

CREATE TRIGGER audit_profiles
  AFTER INSERT OR UPDATE OR DELETE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();

CREATE TRIGGER audit_user_roles
  AFTER INSERT OR UPDATE OR DELETE ON public.user_roles
  FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();

-- -----------------------------------------------------------------------------
-- Row Level Security (RLS)
-- -----------------------------------------------------------------------------

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.funcionarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ft ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ft_historico ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- profiles
CREATE POLICY "Users view own profile"
  ON public.profiles FOR SELECT TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Users update own profile"
  ON public.profiles FOR UPDATE TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Users insert own profile"
  ON public.profiles FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Gestor manage profiles"
  ON public.profiles FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'gestor'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'gestor'::public.app_role));

-- user_roles
CREATE POLICY "Authenticated read roles"
  ON public.user_roles FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admins manage roles"
  ON public.user_roles FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

-- funcionarios
CREATE POLICY "Authenticated read funcionarios"
  ON public.funcionarios FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Insert funcionarios gestor"
  ON public.funcionarios FOR INSERT TO authenticated
  WITH CHECK (public.has_role(auth.uid(), 'gestor'::public.app_role));

CREATE POLICY "Update funcionarios gestor"
  ON public.funcionarios FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'gestor'::public.app_role));

CREATE POLICY "Gestores delete funcionarios"
  ON public.funcionarios FOR DELETE TO authenticated
  USING (
    public.has_role(auth.uid(), 'gestor'::public.app_role)
    OR public.has_role(auth.uid(), 'admin'::public.app_role)
  );

-- ft
CREATE POLICY "Authenticated read ft"
  ON public.ft FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Insert ft gestor ou supervisor"
  ON public.ft FOR INSERT TO authenticated
  WITH CHECK (
    lancado_por = auth.uid()
    AND (
      public.has_role(auth.uid(), 'gestor'::public.app_role)
      OR public.has_role(auth.uid(), 'supervisor'::public.app_role)
    )
  );

CREATE POLICY "Update ft gestor"
  ON public.ft FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'gestor'::public.app_role));

CREATE POLICY "Gestores delete ft"
  ON public.ft FOR DELETE TO authenticated
  USING (
    public.has_role(auth.uid(), 'gestor'::public.app_role)
    OR public.has_role(auth.uid(), 'admin'::public.app_role)
  );

-- ft_historico
CREATE POLICY "Authenticated read historico"
  ON public.ft_historico FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Auth insert historico"
  ON public.ft_historico FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

-- audit_logs
CREATE POLICY "Gestor lê audit_logs"
  ON public.audit_logs FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'gestor'::public.app_role));

CREATE POLICY "Auth insert audit"
  ON public.audit_logs FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

-- -----------------------------------------------------------------------------
-- Permissões de execução (funções)
-- -----------------------------------------------------------------------------

REVOKE EXECUTE ON FUNCTION public.tg_ft_log_history() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tg_ft_validate_status() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tg_ft_before_insert() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tg_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.log_audit(TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tg_audit_row() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.valor_folga_por_cargo(TEXT) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.valor_folga_por_cargo(TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(UUID, public.app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(UUID, public.app_role) TO authenticated;

-- -----------------------------------------------------------------------------
-- Grants PostgREST (service_role precisa ler/escrever para API admin do app)
-- -----------------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO postgres, service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- =============================================================================
-- OPCIONAL: usuário admin inicial (descomente se precisar no primeiro deploy)
-- Preferível: executar supabase/seed_admin.sql após o schema
-- Senha padrão nas migrations antigas: Ab783514 — altere após o login.
-- =============================================================================
/*
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
    jsonb_build_object('username', 'admin', 'nome', 'Administrador', 'role', 'gestor'),
    false, '', '', '', ''
  );

  INSERT INTO auth.identities (
    id, user_id, identity_data, provider, provider_id,
    last_sign_in_at, created_at, updated_at
  ) VALUES (
    gen_random_uuid(),
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', 'admin@interno.local'),
    'email',
    v_user_id::text,
    now(), now(), now()
  );
END $$;
*/
