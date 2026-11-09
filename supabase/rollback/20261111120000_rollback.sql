-- Reverte 20261111120000 (auditoria com CPF mascarado na leitura). Executar o arquivo INTEIRO, antes do rollback 20261110120000.
-- Não toca em registros: a migration não alterou nenhum. Volta a leitura direta do Gestor (policy "Gestor lê audit_logs").

BEGIN;

SET LOCAL lock_timeout = '5s';

GRANT SELECT ON public.audit_logs TO authenticated;
DROP FUNCTION public.auditoria_listar(INT);
DROP FUNCTION public.audit_mascarar(JSONB);
DROP FUNCTION public.texto_cpf_mascarado(TEXT);

NOTIFY pgrst, 'reload schema';

COMMIT;
