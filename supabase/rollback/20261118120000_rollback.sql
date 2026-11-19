-- Reverte 20261118120000 (auditoria paginada). Executar o arquivo INTEIRO, antes do rollback 20261112120000/20261111120000.
-- Não toca em registros nem em permissões de audit_logs: remove só as duas funções novas e o índice do cursor.
-- Depois disso a tela nova de Auditoria deixa de funcionar: reverter também o código da aplicação.

BEGIN;

SET LOCAL lock_timeout = '5s';

DROP FUNCTION IF EXISTS public.auditoria_pagina(DATE, DATE, UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ, UUID, INT);
DROP FUNCTION IF EXISTS public.auditoria_filtros();
DROP INDEX IF EXISTS public.idx_audit_logs_created_id;

NOTIFY pgrst, 'reload schema';

COMMIT;
