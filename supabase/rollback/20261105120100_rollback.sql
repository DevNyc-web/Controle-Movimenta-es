-- Reverte 20261105120100 (perfis e auditoria). Executar o arquivo INTEIRO; reverter ANTES de 20261105120000.
-- De propósito NÃO restaura o que era falha: papel vindo de metadata (handle_new_user), autoconcessão do Admin (A1),
-- autorreativação (A2) e audit_logs aberto (A6). O frontend antigo não depende de nada disso.
-- Restaura o que o frontend antigo usa: INSERT em ft_historico (correção de valores) e leitura como antes.

BEGIN;

SET LOCAL lock_timeout = '5s';

LOCK TABLE public.ft, public.ft_historico, public.funcionarios IN ACCESS EXCLUSIVE MODE;

DROP TRIGGER trg_ft_registrar_correcao ON public.ft;
DROP FUNCTION public.tg_ft_registrar_correcao();

GRANT INSERT ON public.ft_historico TO authenticated;
CREATE POLICY "Auth insert historico" ON public.ft_historico FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

DROP POLICY "Conta ativa le funcionarios" ON public.funcionarios;
CREATE POLICY "Authenticated read funcionarios" ON public.funcionarios FOR SELECT TO authenticated USING (true);

DROP POLICY "Read ft com janela supervisor" ON public.ft;
CREATE POLICY "Read ft com janela supervisor" ON public.ft FOR SELECT TO authenticated
  USING (public.pode_ver_ft_data(data_ft));

CREATE OR REPLACE FUNCTION public.pode_ver_ft_data(_data DATE)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT NOT public.supervisor_restrito() OR public.ft_na_janela_supervisor(_data)
$$;

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role public.app_role)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;

DROP FUNCTION public.conta_ativa();

NOTIFY pgrst, 'reload schema';

COMMIT;
