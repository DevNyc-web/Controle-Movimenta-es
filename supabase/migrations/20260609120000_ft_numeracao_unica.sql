-- Numeração única de movimentações (Phase 1)
-- Adiciona numero_ft à tabela ft com sequência global, backfill e constraints.
--
-- Sem BEGIN/COMMIT explícito: projeto não usa Supabase CLI (sem config.toml);
-- migrations são aplicadas via SQL Editor / Lovable — nenhuma outra migration
-- do projeto usa controle de transação top-level.

-- 1. Sequência global monotônica (não reseta por ano; o ano é apenas rótulo no texto)
CREATE SEQUENCE IF NOT EXISTS public.ft_numero_seq START 1;

-- 2. Coluna nullable primeiro — backfill precisa rodar antes do NOT NULL
ALTER TABLE public.ft
  ADD COLUMN IF NOT EXISTS numero_ft TEXT;

-- 3. Backfill de registros existentes
--    - Ordena por created_at ASC, id ASC (desempate determinístico)
--    - Ano extraído do created_at de cada registro (não de now())
--    - nextval chamado uma vez por linha dentro do loop
--    - WHERE numero_ft IS NULL: seguro para re-execução após falha parcial
DO $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT id, EXTRACT(YEAR FROM created_at)::INT AS ano
    FROM public.ft
    WHERE numero_ft IS NULL
    ORDER BY created_at ASC, id ASC
  LOOP
    UPDATE public.ft
      SET numero_ft = 'FT-' || rec.ano::TEXT || '-'
                   || lpad(nextval('public.ft_numero_seq')::TEXT, 6, '0')
    WHERE id = rec.id;
  END LOOP;
END;
$$;

-- 4. Enforçar NOT NULL somente após backfill completo
ALTER TABLE public.ft
  ALTER COLUMN numero_ft SET NOT NULL;

-- 5. Unicidade garantida por constraint nomeada
ALTER TABLE public.ft
  ADD CONSTRAINT ft_numero_ft_unique UNIQUE (numero_ft);

-- 6. Função do trigger para novos registros
CREATE OR REPLACE FUNCTION public.tg_ft_gerar_numero()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.numero_ft IS NULL THEN
    NEW.numero_ft := 'FT-' || to_char(now(), 'YYYY') || '-'
                  || lpad(nextval('public.ft_numero_seq')::TEXT, 6, '0');
  END IF;
  RETURN NEW;
END;
$$;

-- Revoga execução pública (consistente com as demais funções de trigger no schema)
REVOKE EXECUTE ON FUNCTION public.tg_ft_gerar_numero() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_ft_numero
  BEFORE INSERT ON public.ft
  FOR EACH ROW EXECUTE FUNCTION public.tg_ft_gerar_numero();

-- =============================================================================
-- ROLLBACK (executar manualmente se necessário após deploy):
--
-- DROP TRIGGER IF EXISTS trg_ft_numero ON public.ft;
-- DROP FUNCTION IF EXISTS public.tg_ft_gerar_numero();
-- ALTER TABLE public.ft DROP CONSTRAINT IF EXISTS ft_numero_ft_unique;
-- ALTER TABLE public.ft DROP COLUMN IF EXISTS numero_ft;
-- DROP SEQUENCE IF EXISTS public.ft_numero_seq;
-- =============================================================================
