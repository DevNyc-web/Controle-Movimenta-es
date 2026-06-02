-- Enum de papéis
CREATE TYPE public.app_role AS ENUM ('admin', 'gestor', 'rh');

-- Enum de status de FT
CREATE TYPE public.ft_status AS ENUM ('PENDENTE', 'APROVADA', 'NEGADA', 'CANCELADA');

-- Profiles
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nome TEXT NOT NULL,
  email TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
CREATE POLICY "Users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);
CREATE POLICY "Users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

-- User roles
CREATE TABLE public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;

CREATE POLICY "Authenticated read roles" ON public.user_roles FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins manage roles" ON public.user_roles FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'admin')) WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- Funcionarios
CREATE TABLE public.funcionarios (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome TEXT NOT NULL,
  cpf TEXT NOT NULL UNIQUE,
  re TEXT NOT NULL UNIQUE,
  cargo TEXT NOT NULL,
  setor TEXT NOT NULL,
  data_admissao DATE NOT NULL,
  turno TEXT NOT NULL,
  status_ativo BOOLEAN NOT NULL DEFAULT true,
  supervisor TEXT,
  banco_horas NUMERIC NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.funcionarios ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read funcionarios" ON public.funcionarios FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated insert funcionarios" ON public.funcionarios FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Authenticated update funcionarios" ON public.funcionarios FOR UPDATE TO authenticated USING (true);
CREATE POLICY "Gestores delete funcionarios" ON public.funcionarios FOR DELETE TO authenticated USING (public.has_role(auth.uid(), 'gestor') OR public.has_role(auth.uid(), 'admin'));

-- FT
CREATE TABLE public.ft (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  funcionario_id UUID NOT NULL REFERENCES public.funcionarios(id) ON DELETE CASCADE,
  data_ft DATE NOT NULL,
  tipo_folga TEXT NOT NULL,
  motivo TEXT NOT NULL,
  status ft_status NOT NULL DEFAULT 'PENDENTE',
  horas_trabalhadas NUMERIC NOT NULL DEFAULT 0,
  horas_compensadas NUMERIC NOT NULL DEFAULT 0,
  observacao TEXT,
  aprovado_por UUID REFERENCES auth.users(id),
  data_lancamento TIMESTAMPTZ NOT NULL DEFAULT now(),
  data_cancelamento TIMESTAMPTZ,
  lancado_por UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (funcionario_id, data_ft)
);
ALTER TABLE public.ft ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read ft" ON public.ft FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated insert ft" ON public.ft FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Authenticated update ft" ON public.ft FOR UPDATE TO authenticated USING (true);
CREATE POLICY "Gestores delete ft" ON public.ft FOR DELETE TO authenticated USING (public.has_role(auth.uid(), 'gestor') OR public.has_role(auth.uid(), 'admin'));

-- Histórico
CREATE TABLE public.ft_historico (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ft_id UUID NOT NULL REFERENCES public.ft(id) ON DELETE CASCADE,
  acao TEXT NOT NULL,
  status_anterior ft_status,
  status_novo ft_status,
  alterado_por UUID REFERENCES auth.users(id),
  observacao TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.ft_historico ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read historico" ON public.ft_historico FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated insert historico" ON public.ft_historico FOR INSERT TO authenticated WITH CHECK (true);

-- Trigger updated_at
CREATE OR REPLACE FUNCTION public.tg_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

CREATE TRIGGER set_updated_at_profiles BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.tg_updated_at();
CREATE TRIGGER set_updated_at_funcionarios BEFORE UPDATE ON public.funcionarios FOR EACH ROW EXECUTE FUNCTION public.tg_updated_at();
CREATE TRIGGER set_updated_at_ft BEFORE UPDATE ON public.ft FOR EACH ROW EXECUTE FUNCTION public.tg_updated_at();

-- Trigger: bloquear aprovação de FT cancelada
CREATE OR REPLACE FUNCTION public.tg_ft_validate_status()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status = 'CANCELADA' AND NEW.status = 'APROVADA' THEN
    RAISE EXCEPTION 'FT cancelada não pode ser aprovada';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER ft_validate_status BEFORE UPDATE ON public.ft FOR EACH ROW EXECUTE FUNCTION public.tg_ft_validate_status();

-- Trigger: histórico automático em mudanças de status
CREATE OR REPLACE FUNCTION public.tg_ft_log_history()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.ft_historico (ft_id, acao, status_novo, alterado_por)
    VALUES (NEW.id, 'CRIADA', NEW.status, NEW.lancado_por);
  ELSIF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO public.ft_historico (ft_id, acao, status_anterior, status_novo, alterado_por)
    VALUES (NEW.id, 'STATUS_ALTERADO', OLD.status, NEW.status, COALESCE(NEW.aprovado_por, auth.uid()));
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER ft_log_history AFTER INSERT OR UPDATE ON public.ft FOR EACH ROW EXECUTE FUNCTION public.tg_ft_log_history();

-- Trigger: criar profile + role rh padrão no signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, nome, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'nome', split_part(NEW.email, '@', 1)), NEW.email);
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'gestor');
  RETURN NEW;
END; $$;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();