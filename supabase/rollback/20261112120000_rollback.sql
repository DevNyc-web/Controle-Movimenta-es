-- Reverte 20261112120000: volta a regra de 20261111120000 (executar antes do rollback 20261111120000). Não toca em registros.
BEGIN;
SET LOCAL lock_timeout = '5s';
CREATE OR REPLACE FUNCTION public.texto_cpf_mascarado(_t TEXT)
RETURNS TEXT
LANGUAGE SQL IMMUTABLE
SET search_path = public
AS $$
  SELECT regexp_replace(_t, '(?<![0-9])[0-9]{3}[ ./-]?([0-9]{3})[ ./-]?([0-9]{3})[ ./-]?[0-9]{2}(?![0-9])', '***.\1.\2-**', 'g')
$$;
REVOKE EXECUTE ON FUNCTION public.texto_cpf_mascarado(TEXT) FROM PUBLIC, anon, authenticated;
COMMIT;
