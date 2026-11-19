-- Reverte o HOTFIX 20261109200000 SOMENTE se 20261105120100 ainda NÃO foi aplicada (senão, nada a reverter aqui: o estado é o dela).
-- De propósito MANTÉM o gatilho seguro (handle_new_user sem papel e desativado): o fluxo do app não depende do gatilho.
-- Restaura: leitura de funcionários/FTs como antes, edição do próprio perfil, gestão de papéis pelo Admin e grants de escrita.
BEGIN;
SET LOCAL lock_timeout = '5s';
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND policyname = 'Conta ativa le funcionarios') THEN
    RAISE EXCEPTION 'Abortado: 20261105120100 já aplicada; reverter o hotfix isoladamente não se aplica.';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role = _role
  );
$$;
CREATE OR REPLACE FUNCTION public.pode_ver_ft_data(_data DATE)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT NOT public.supervisor_restrito() OR public.ft_na_janela_supervisor(_data)
$$;
ALTER POLICY "Read ft com janela supervisor" ON public.ft USING (public.pode_ver_ft_data(data_ft));
ALTER POLICY "Authenticated read funcionarios" ON public.funcionarios USING (true);
ALTER POLICY "Users update own profile" ON public.profiles USING (auth.uid() = id);
ALTER POLICY "Users insert own profile" ON public.profiles WITH CHECK (auth.uid() = id);
ALTER POLICY "Admins manage roles" ON public.user_roles USING (public.has_role(auth.uid(), 'admin'::public.app_role)) WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));
GRANT INSERT, UPDATE, DELETE ON public.profiles, public.user_roles TO authenticated;
-- conta_ativa() fica (inofensiva; 20261105120100 a recria igual).
COMMIT;
