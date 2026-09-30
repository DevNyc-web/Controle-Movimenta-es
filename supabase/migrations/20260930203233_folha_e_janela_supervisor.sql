-- 1) Pagamento em folha (aditivo; registros antigos = FALSE, nada é reinterpretado)
ALTER TABLE public.ft
  ADD COLUMN IF NOT EXISTS pagamento_em_folha BOOLEAN NOT NULL DEFAULT FALSE;

-- 2) Janela de visibilidade do SUPERVISOR: data_ft (DATE) em [hoje-7, hoje+7], inclusivo.
--    "hoje" = data civil em America/Sao_Paulo (evita off-by-one em UTC perto da meia-noite).
--    _hoje é parametrizável apenas para testes.
CREATE OR REPLACE FUNCTION public.ft_na_janela_supervisor(
  _data DATE,
  _hoje DATE DEFAULT (now() AT TIME ZONE 'America/Sao_Paulo')::date
) RETURNS BOOLEAN
LANGUAGE SQL IMMUTABLE SET search_path = public AS $$
  SELECT _data BETWEEN _hoje - 7 AND _hoje + 7
$$;
GRANT EXECUTE ON FUNCTION public.ft_na_janela_supervisor(DATE, DATE) TO authenticated;

-- 3) Quem pode ver uma FT: todos, exceto supervisor "puro" fora da janela.
--    A janela vale SÓ para supervisor; gestor, admin e demais roles mantêm o acesso irrestrito anterior.
--    Dentro da janela o supervisor vê FTs de QUALQUER lançador (intencional: sem filtro lancado_por).
--    supervisor_restrito() é a definição única de "sujeito à janela": supervisor sem gestor/admin.
CREATE OR REPLACE FUNCTION public.supervisor_restrito()
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.has_role(auth.uid(), 'supervisor'::public.app_role)
     AND NOT public.has_role(auth.uid(), 'gestor'::public.app_role)
     AND NOT public.has_role(auth.uid(), 'admin'::public.app_role)
$$;
REVOKE EXECUTE ON FUNCTION public.supervisor_restrito() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.supervisor_restrito() TO authenticated;

CREATE OR REPLACE FUNCTION public.pode_ver_ft_data(_data DATE)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT NOT public.supervisor_restrito() OR public.ft_na_janela_supervisor(_data)
$$;
REVOKE EXECUTE ON FUNCTION public.pode_ver_ft_data(DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pode_ver_ft_data(DATE) TO authenticated;

-- 4) RLS: SELECT de ft passa a respeitar a janela
DROP POLICY IF EXISTS "Authenticated read ft" ON public.ft;
CREATE POLICY "Read ft com janela supervisor"
  ON public.ft FOR SELECT TO authenticated
  USING (public.pode_ver_ft_data(data_ft));

-- 5) Tabelas filhas (inclui o INSERT de cancelamento, cuja policy faz EXISTS em ft => também fica sob a janela; intencional):
--    Tabelas filhas: não vazam FT fora da janela (EXISTS em ft aplica a RLS acima ao chamador)
DROP POLICY IF EXISTS "Authenticated read historico" ON public.ft_historico;
CREATE POLICY "Read historico via ft visivel"
  ON public.ft_historico FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.ft f WHERE f.id = ft_id));

DROP POLICY IF EXISTS "Autenticados leem solicitacoes cancelamento" ON public.ft_cancelamento_solicitacoes;
CREATE POLICY "Read solicitacoes via ft visivel"
  ON public.ft_cancelamento_solicitacoes FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.ft f WHERE f.id = ft_id));

-- 6) Cancelamento: fechar o oráculo de informação por ID.
--    Ordem no Postgres: BEFORE ROW trigger -> WITH CHECK da RLS. Como tg_cancelamento_on_insert é SECURITY DEFINER e
--    roda ANTES da RLS, ele respondia "não encontrada" / "ESTADO_INVALIDO" para qualquer ID, revelando existência e status.
--    Agora o trigger aplica a janela primeiro: para supervisor restrito, FT inexistente OU fora da janela retorna o
--    MESMO erro da RLS (42501, mesma mensagem), sem ler status e sem lock. Autorização (ownership, janela, PENDENTE)
--    e demais mensagens/comportamento permanecem; gestor/admin/service_role não são afetados (supervisor_restrito()=false).
CREATE OR REPLACE FUNCTION public.tg_cancelamento_on_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ft_status public.ft_status;
  v_data      DATE;
  v_achou     BOOLEAN;
BEGIN
  SELECT data_ft INTO v_data FROM public.ft WHERE id = NEW.ft_id;
  v_achou := FOUND;

  IF public.supervisor_restrito() AND (NOT v_achou OR NOT public.ft_na_janela_supervisor(v_data)) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'new row violates row-level security policy for table "ft_cancelamento_solicitacoes"';
  END IF;

  -- FOR UPDATE: serializa inserções concorrentes para a mesma FT
  SELECT status INTO v_ft_status
    FROM public.ft
   WHERE id = NEW.ft_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Movimentação não encontrada';
  END IF;

  IF v_ft_status <> 'PENDENTE'::public.ft_status THEN
    RAISE EXCEPTION 'ESTADO_INVALIDO: Somente movimentações PENDENTES podem ter cancelamento solicitado';
  END IF;

  -- tg_ft_log_history dispara aqui: registra PENDENTE -> CANCELAMENTO_SOLICITADO em ft_historico
  UPDATE public.ft
     SET status = 'CANCELAMENTO_SOLICITADO'::public.ft_status
   WHERE id = NEW.ft_id;

  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.tg_cancelamento_on_insert() FROM PUBLIC, anon, authenticated;

-- ROLLBACK manual (além do abaixo: reaplicar a versão original de tg_cancelamento_on_insert da migration 20260609130000 e DROP FUNCTION public.supervisor_restrito()):
-- DROP POLICY "Read ft com janela supervisor" ON public.ft;
-- CREATE POLICY "Authenticated read ft" ON public.ft FOR SELECT TO authenticated USING (true);
-- DROP POLICY "Read historico via ft visivel" ON public.ft_historico;
-- CREATE POLICY "Authenticated read historico" ON public.ft_historico FOR SELECT TO authenticated USING (true);
-- DROP POLICY "Read solicitacoes via ft visivel" ON public.ft_cancelamento_solicitacoes;
-- CREATE POLICY "Autenticados leem solicitacoes cancelamento" ON public.ft_cancelamento_solicitacoes FOR SELECT TO authenticated USING (true);
-- DROP FUNCTION public.pode_ver_ft_data(DATE); DROP FUNCTION public.ft_na_janela_supervisor(DATE, DATE);
-- ALTER TABLE public.ft DROP COLUMN pagamento_em_folha;
