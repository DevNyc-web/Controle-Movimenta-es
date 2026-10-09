-- FT CANCELADA ou NEGADA não deve bloquear novo lançamento do mesmo funcionário na mesma data.
-- Causa: UNIQUE (funcionario_id, data_ft) valia para qualquer status.
-- Troca por índice único PARCIAL: só FTs "vivas" (PENDENTE, APROVADA, CANCELAMENTO_SOLICITADO) competem pela data.
-- Efeitos: lançar sobre CANCELADA/NEGADA passa; duplicata entre vivas segue dando 23505; e reativar (UPDATE de status)
-- uma NEGADA para status vivo quando já há outra viva na data também dá 23505. CANCELADA→qualquer já é barrada por tg_ft_validate_status.
-- Nenhuma linha é lida, alterada ou apagada. O novo índice é menos restritivo que o antigo, então nunca falha por dados existentes.
-- Observação: o limite mensal não é mais regra de banco (apenas sinalização no frontend); nada a mudar nos triggers.
-- Atenção: as FTs CANCELADA/NEGADA seguem com numero_ft próprio (UNIQUE numero_ft intocado).

CREATE UNIQUE INDEX ft_funcionario_data_ativa_key
  ON public.ft (funcionario_id, data_ft)
  WHERE status NOT IN ('CANCELADA'::public.ft_status, 'NEGADA'::public.ft_status);

ALTER TABLE public.ft DROP CONSTRAINT ft_funcionario_id_data_ft_key;

-- ROLLBACK (só possível se não houver, entre as FTs de qualquer status, duas na mesma data para o mesmo funcionário):
-- ALTER TABLE public.ft ADD CONSTRAINT ft_funcionario_id_data_ft_key UNIQUE (funcionario_id, data_ft);
-- DROP INDEX public.ft_funcionario_data_ativa_key;
