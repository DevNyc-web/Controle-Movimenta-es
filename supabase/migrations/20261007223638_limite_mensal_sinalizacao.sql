-- Limite mensal de movimentações: de BLOQUEIO para SINALIZAÇÃO.
-- Antes: tg_ft_before_insert() recusava a 5ª FT do mês de um funcionário (LIMITE_MENSAL).
-- Agora: a FT é sempre aceita; quem excede 4 no mês (funcionario_id + mês de data_ft, status <> 'CANCELADA')
-- é apenas destacado nos relatórios (cálculo feito no frontend).
--
-- Escopo: SOMENTE o bloqueio foi removido. Preservados sem alteração: valor_pago por cargo, PERMISSAO_FERIAS,
-- SECURITY DEFINER, search_path, o trigger trg_ft_before_insert e os GRANT/REVOKE (CREATE OR REPLACE mantém privilégios).
-- Não toca em RLS, janela do supervisor, cancelamento, UNIQUE (funcionario_id, data_ft), numero_ft nem pagamento_em_folha.

CREATE OR REPLACE FUNCTION public.tg_ft_before_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cargo TEXT;
  v_status TEXT;
  v_is_gestor BOOLEAN;
BEGIN
  -- buscar cargo + status do funcionário que está cobrindo
  SELECT cargo, status INTO v_cargo, v_status
  FROM public.funcionarios WHERE id = NEW.funcionario_id;

  IF v_cargo IS NULL THEN
    RAISE EXCEPTION 'Funcionário inválido';
  END IF;

  -- aplicar valor fixo pelo cargo (sempre sobrescreve para garantir consistência)
  NEW.valor_pago := public.valor_folga_por_cargo(v_cargo);

  -- se funcionário que cobre está de férias, exigir gestor
  IF v_status = 'ferias' THEN
    SELECT public.has_role(NEW.lancado_por, 'gestor'::app_role) INTO v_is_gestor;
    IF NOT v_is_gestor THEN
      RAISE EXCEPTION 'PERMISSAO_FERIAS: Funcionário está de férias. Apenas um Gestor pode lançar esta movimentação.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
