-- Fix search_path
CREATE OR REPLACE FUNCTION public.tg_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

CREATE OR REPLACE FUNCTION public.tg_ft_validate_status()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF OLD.status = 'CANCELADA' AND NEW.status = 'APROVADA' THEN
    RAISE EXCEPTION 'FT cancelada não pode ser aprovada';
  END IF;
  RETURN NEW;
END; $$;

-- Restrict permissive policies
DROP POLICY "Authenticated insert funcionarios" ON public.funcionarios;
DROP POLICY "Authenticated update funcionarios" ON public.funcionarios;
DROP POLICY "Authenticated insert ft" ON public.ft;
DROP POLICY "Authenticated update ft" ON public.ft;
DROP POLICY "Authenticated insert historico" ON public.ft_historico;

CREATE POLICY "Auth insert funcionarios" ON public.funcionarios FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Auth update funcionarios" ON public.funcionarios FOR UPDATE TO authenticated USING (auth.uid() IS NOT NULL);
CREATE POLICY "Auth insert ft" ON public.ft FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL AND lancado_por = auth.uid());
CREATE POLICY "Auth update ft" ON public.ft FOR UPDATE TO authenticated USING (auth.uid() IS NOT NULL);
CREATE POLICY "Auth insert historico" ON public.ft_historico FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);