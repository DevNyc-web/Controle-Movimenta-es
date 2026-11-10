-- Corrige a máscara de CPF em texto da auditoria (20261111120000): UUIDs e hashes com 11 dígitos seguidos eram corrompidos
-- na exibição (ex.: ...-8000-12345678901a virava ...-8000-***.456.789-**a; ~0,5% dos UUIDs aleatórios).
-- Regra nova: formato oficial em qualquer posição; logo após a palavra CPF; ou 11 dígitos como token isolado (sem letra ou dígito colado). NÃO APLICADA.
-- Não altera nenhum registro gravado. Reversão: supabase/rollback/20261112120000_rollback.sql.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $$
BEGIN
  IF to_regprocedure('public.texto_cpf_mascarado(text)') IS NULL THEN
    RAISE EXCEPTION 'Abortado: aplique antes 20261111120000.';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.texto_cpf_mascarado(_t TEXT)
RETURNS TEXT
LANGUAGE SQL IMMUTABLE
SET search_path = public
AS $$
  -- 1) formato oficial 000.000.000-00 em qualquer posição (nunca ocorre em UUID/hash); 2) logo após a palavra CPF;
  -- 3) 11 dígitos como token isolado, com ou sem separadores (letra ou dígito colado = UUID/hash, não mascara)
  SELECT regexp_replace(
           regexp_replace(
             regexp_replace(_t, '(?<![0-9])[0-9]{3}\.([0-9]{3})\.([0-9]{3})-[0-9]{2}(?![0-9])', '***.\1.\2-**', 'g'),
             '(cpf)[ :.#-]?[0-9]{3}[ ./-]?([0-9]{3})[ ./-]?([0-9]{3})[ ./-]?[0-9]{2}(?![0-9])', '\1 ***.\2.\3-**', 'gi'),
           '(?<![0-9A-Za-z])[0-9]{3}[ ./-]?([0-9]{3})[ ./-]?([0-9]{3})[ ./-]?[0-9]{2}(?![0-9A-Za-z])', '***.\1.\2-**', 'g')
$$;
REVOKE EXECUTE ON FUNCTION public.texto_cpf_mascarado(TEXT) FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  IF public.texto_cpf_mascarado('id ad000000-0000-4000-8000-12345678901a') <> 'id ad000000-0000-4000-8000-12345678901a'
     OR public.texto_cpf_mascarado('cpf 613.001.013-34') <> 'cpf ***.001.013-**'
     OR public.texto_cpf_mascarado('documento613.001.013-34') <> 'documento***.001.013-**'
     OR public.texto_cpf_mascarado('CPF61300101334') <> 'CPF ***.001.013-**' THEN
    RAISE EXCEPTION 'Abortado: máscara não se comporta como esperado.';
  END IF;
END $$;

COMMIT;
