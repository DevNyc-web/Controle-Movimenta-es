-- Reverte 20261106120000 (Conferência). Executar o arquivo INTEIRO, antes dos rollbacks da Fase 1A.
-- Recusa rodar se já existir conferência: o histórico não é apagado por este arquivo. Alterações já aplicadas em funcionários permanecem.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.conferencias) THEN
    RAISE EXCEPTION 'Abortado sem alterações: há conferências registradas. Exportar antes.';
  END IF;
END $$;

DROP FUNCTION public.conferencia_descartar(UUID, TEXT);
DROP FUNCTION public.conferencia_aplicar(UUID, TEXT);
DROP FUNCTION public.conferencia_decidir(UUID, TEXT, TEXT, TEXT, JSONB);
DROP FUNCTION public.conferencia_criar(JSONB, JSONB, JSONB);
DROP FUNCTION public.conferencia_mascarar_itens(UUID);
DROP TABLE public.conferencia_itens;
DROP TABLE public.conferencias;
DROP FUNCTION public.cpf_mascarado(TEXT);
DROP FUNCTION public.cpf_digitos(TEXT);
DROP FUNCTION public.cpf_valido(TEXT);

NOTIFY pgrst, 'reload schema';

COMMIT;
