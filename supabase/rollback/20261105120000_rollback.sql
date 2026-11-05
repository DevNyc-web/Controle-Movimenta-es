-- Reverte 20261105120000. Executar o arquivo INTEIRO, depois de 20261105120100_rollback.sql.
-- Recusa rodar se a reversão destruiria informação: funcionário inativo, período de inatividade ou FT com exceção retroativa.
-- Nesses casos, exporte e decida antes; este arquivo não apaga evidência.
-- De propósito NÃO restaura ON DELETE CASCADE/SET NULL: eles apagariam FTs e histórico. Exclusão de funcionário sem FT volta a funcionar.

BEGIN;

SET LOCAL lock_timeout = '5s';

LOCK TABLE public.ft_cancelamento_solicitacoes, public.ft, public.ft_historico, public.funcionarios IN ACCESS EXCLUSIVE MODE;

DO $$
DECLARE v_inativos BIGINT; v_periodos BIGINT; v_retro BIGINT;
BEGIN
  SELECT count(*) INTO v_inativos FROM public.funcionarios WHERE status = 'inativo';
  SELECT count(*) INTO v_periodos FROM public.funcionario_inatividades;
  SELECT count(*) INTO v_retro FROM public.ft WHERE retroativa_autorizada_em IS NOT NULL;
  IF v_inativos + v_periodos + v_retro > 0 THEN
    RAISE EXCEPTION 'Abortado sem alterações: % inativos, % períodos, % FTs retroativas perderiam informação. Exportar antes.',
      v_inativos, v_periodos, v_retro;
  END IF;
END $$;

DROP TRIGGER trg_ft_retroativa_registrar ON public.ft;
DROP TRIGGER trg_ft_validar_funcionarios ON public.ft;
DROP TRIGGER trg_ft_a_normalizar_insert ON public.ft;
DROP TRIGGER trg_funcionarios_status ON public.funcionarios;
DROP TRIGGER trg_funcionarios_bloquear_truncate ON public.funcionarios;
DROP TRIGGER trg_funcionarios_bloquear_exclusao ON public.funcionarios;
DROP TRIGGER trg_ft_bloquear_truncate ON public.ft;
DROP TRIGGER trg_ft_bloquear_exclusao ON public.ft;
DROP TRIGGER trg_ft_historico_bloquear_truncate ON public.ft_historico;
DROP TRIGGER trg_ft_historico_bloquear_exclusao ON public.ft_historico;

DROP FUNCTION public.anular_inatividade(UUID, TEXT);
DROP TABLE public.funcionario_inatividades;

DROP FUNCTION public.tg_ft_retroativa_registrar();
DROP FUNCTION public.tg_ft_validar_funcionarios();
DROP FUNCTION public.tg_ft_normalizar_insert();
DROP FUNCTION public.tg_funcionarios_status();
DROP FUNCTION public.tg_bloquear_exclusao();
DROP FUNCTION public.funcionario_em_inatividade(UUID, DATE);
DROP FUNCTION public.texto_justificativa_valido(TEXT);

ALTER TABLE public.funcionarios
  DROP CONSTRAINT funcionarios_reativacao_motivo_transitorio,
  DROP CONSTRAINT funcionarios_inativacao_coerente,
  DROP CONSTRAINT funcionarios_status_ativo_coerente,
  DROP CONSTRAINT funcionarios_status_check,
  ADD CONSTRAINT funcionarios_status_check CHECK (status IN ('ativo', 'ferias')),
  DROP COLUMN data_inativacao,
  DROP COLUMN inativado_por,
  DROP COLUMN reativacao_motivo;

ALTER TABLE public.ft
  DROP CONSTRAINT ft_retroativa_coerente,
  DROP COLUMN retroativa_justificativa,
  DROP COLUMN retroativa_autorizada_por,
  DROP COLUMN retroativa_autorizada_em;

CREATE POLICY "Gestores delete funcionarios" ON public.funcionarios FOR DELETE TO authenticated
  USING (public.has_role(auth.uid(), 'gestor'::public.app_role) OR public.has_role(auth.uid(), 'admin'::public.app_role));
GRANT DELETE ON public.funcionarios TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
