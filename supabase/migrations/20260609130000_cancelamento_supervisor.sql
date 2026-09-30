-- Solicitação de cancelamento pelo supervisor
-- Fase 1: DB — enum, tabela, triggers, RPCs, RLS
-- Arquivo: supabase/migrations/20260609130000_cancelamento_supervisor.sql

-- ============================================================
-- 1. Novo valor no enum ft_status
--    IF NOT EXISTS: seguro para re-execução
-- ============================================================
ALTER TYPE public.ft_status ADD VALUE IF NOT EXISTS 'CANCELAMENTO_SOLICITADO';

-- ============================================================
-- 2. Atualiza tg_ft_validate_status
--    Antes: bloqueava apenas CANCELADA → APROVADA
--    Agora:  bloqueia QUALQUER transição a partir de CANCELADA
--    CANCELAMENTO_SOLICITADO → PENDENTE (rejeição) deve passar ✓
-- ============================================================
CREATE OR REPLACE FUNCTION public.tg_ft_validate_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF OLD.status = 'CANCELADA'::public.ft_status THEN
    RAISE EXCEPTION 'FT cancelada não pode ter o status alterado';
  END IF;
  RETURN NEW;
END;
$$;

-- ============================================================
-- 3. Nova tabela
-- ============================================================
CREATE TABLE public.ft_cancelamento_solicitacoes (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  ft_id          UUID        NOT NULL REFERENCES public.ft(id) ON DELETE CASCADE,
  solicitado_por UUID        NOT NULL REFERENCES auth.users(id),
  motivo         TEXT        NOT NULL,
  status         TEXT        NOT NULL DEFAULT 'PENDENTE'
                               CHECK (status IN ('PENDENTE', 'APROVADO', 'REJEITADO')),
  decidido_por   UUID        REFERENCES auth.users(id),
  data_decisao   TIMESTAMPTZ,
  observacao     TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 4. Índices
-- ============================================================
-- Garante no banco: máximo uma solicitação PENDENTE por FT
CREATE UNIQUE INDEX uq_ft_cancelamento_pendente
  ON public.ft_cancelamento_solicitacoes (ft_id)
  WHERE status = 'PENDENTE';

CREATE INDEX idx_ft_cancelamento_ft_id
  ON public.ft_cancelamento_solicitacoes (ft_id);

CREATE INDEX idx_ft_cancelamento_status_pendente
  ON public.ft_cancelamento_solicitacoes (status)
  WHERE status = 'PENDENTE';

-- ============================================================
-- 5. updated_at trigger (reutiliza função existente)
-- ============================================================
CREATE TRIGGER set_updated_at_ft_cancelamento
  BEFORE UPDATE ON public.ft_cancelamento_solicitacoes
  FOR EACH ROW EXECUTE FUNCTION public.tg_updated_at();

-- ============================================================
-- 6. BEFORE INSERT: valida estado da FT e muda para
--    CANCELAMENTO_SOLICITADO atomicamente com a inserção
-- ============================================================
CREATE OR REPLACE FUNCTION public.tg_cancelamento_on_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ft_status public.ft_status;
BEGIN
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

  -- tg_ft_log_history dispara aqui:
  -- registra PENDENTE → CANCELAMENTO_SOLICITADO em ft_historico
  UPDATE public.ft
     SET status = 'CANCELAMENTO_SOLICITADO'::public.ft_status
   WHERE id = NEW.ft_id;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tg_cancelamento_on_insert()
  FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_cancelamento_on_insert
  BEFORE INSERT ON public.ft_cancelamento_solicitacoes
  FOR EACH ROW EXECUTE FUNCTION public.tg_cancelamento_on_insert();

-- ============================================================
-- 7. AFTER UPDATE em ft: cleanup quando FT é cancelada diretamente
--    Gestor cancela FT sem usar RPC → solicitação PENDENTE → APROVADO
-- ============================================================
CREATE OR REPLACE FUNCTION public.tg_ft_cancelamento_cleanup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status
     AND NEW.status = 'CANCELADA'::public.ft_status
  THEN
    UPDATE public.ft_cancelamento_solicitacoes
       SET status       = 'APROVADO',
           decidido_por = auth.uid(),
           data_decisao = now(),
           observacao   = COALESCE(observacao, 'Movimentação cancelada diretamente')
     WHERE ft_id = NEW.id
       AND status = 'PENDENTE';
    -- Nota: quando aprovar_cancelamento executa, a solicitação já está APROVADO
    -- antes do UPDATE em ft — WHERE status = 'PENDENTE' não a encontra. ✓
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.tg_ft_cancelamento_cleanup()
  FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_ft_cancelamento_cleanup
  AFTER UPDATE ON public.ft
  FOR EACH ROW EXECUTE FUNCTION public.tg_ft_cancelamento_cleanup();

-- ============================================================
-- 8. Audit trigger (reutiliza tg_audit_row existente)
-- ============================================================
CREATE TRIGGER audit_ft_cancelamento_solicitacoes
  AFTER INSERT OR UPDATE OR DELETE ON public.ft_cancelamento_solicitacoes
  FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();

-- ============================================================
-- 9. RPC: aprovar cancelamento
--    FT: CANCELAMENTO_SOLICITADO → CANCELADA
-- ============================================================
CREATE OR REPLACE FUNCTION public.aprovar_cancelamento(
  _solicitacao_id UUID,
  _obs            TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ft_id  UUID;
  v_status TEXT;
  v_uid    UUID := auth.uid();
BEGIN
  IF NOT (
    public.has_role(v_uid, 'gestor'::public.app_role)
    OR public.has_role(v_uid, 'admin'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'PERMISSAO: Apenas gestores e admins podem aprovar cancelamentos';
  END IF;

  SELECT ft_id, status
    INTO v_ft_id, v_status
    FROM public.ft_cancelamento_solicitacoes
   WHERE id = _solicitacao_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Solicitação não encontrada';
  END IF;

  IF v_status <> 'PENDENTE' THEN
    RAISE EXCEPTION 'ESTADO_INVALIDO: Solicitação já processada (%)', v_status;
  END IF;

  -- Marca como APROVADO antes de alterar ft:
  -- tg_ft_cancelamento_cleanup faz WHERE status = 'PENDENTE' → não afeta. ✓
  UPDATE public.ft_cancelamento_solicitacoes
     SET status       = 'APROVADO',
         decidido_por = v_uid,
         data_decisao = now(),
         observacao   = COALESCE(_obs, observacao)
   WHERE id = _solicitacao_id;

  -- tg_ft_validate_status: OLD = CANCELAMENTO_SOLICITADO ≠ CANCELADA → passa ✓
  -- tg_ft_log_history: registra CANCELAMENTO_SOLICITADO → CANCELADA      ✓
  UPDATE public.ft
     SET status            = 'CANCELADA'::public.ft_status,
         data_cancelamento = now()
   WHERE id = v_ft_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.aprovar_cancelamento(UUID, TEXT)
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.aprovar_cancelamento(UUID, TEXT)
  TO authenticated;

-- ============================================================
-- 10. RPC: rejeitar cancelamento
--     FT: CANCELAMENTO_SOLICITADO → PENDENTE
-- ============================================================
CREATE OR REPLACE FUNCTION public.rejeitar_cancelamento(
  _solicitacao_id UUID,
  _obs            TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ft_id  UUID;
  v_status TEXT;
  v_uid    UUID := auth.uid();
BEGIN
  IF NOT (
    public.has_role(v_uid, 'gestor'::public.app_role)
    OR public.has_role(v_uid, 'admin'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'PERMISSAO: Apenas gestores e admins podem rejeitar cancelamentos';
  END IF;

  SELECT ft_id, status
    INTO v_ft_id, v_status
    FROM public.ft_cancelamento_solicitacoes
   WHERE id = _solicitacao_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Solicitação não encontrada';
  END IF;

  IF v_status <> 'PENDENTE' THEN
    RAISE EXCEPTION 'ESTADO_INVALIDO: Solicitação já processada (%)', v_status;
  END IF;

  UPDATE public.ft_cancelamento_solicitacoes
     SET status       = 'REJEITADO',
         decidido_por = v_uid,
         data_decisao = now(),
         observacao   = COALESCE(_obs, observacao)
   WHERE id = _solicitacao_id;

  -- tg_ft_validate_status: OLD = CANCELAMENTO_SOLICITADO ≠ CANCELADA → passa ✓
  -- tg_ft_log_history: registra CANCELAMENTO_SOLICITADO → PENDENTE       ✓
  UPDATE public.ft
     SET status = 'PENDENTE'::public.ft_status
   WHERE id = v_ft_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rejeitar_cancelamento(UUID, TEXT)
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.rejeitar_cancelamento(UUID, TEXT)
  TO authenticated;

-- ============================================================
-- 11. RLS
-- ============================================================
ALTER TABLE public.ft_cancelamento_solicitacoes ENABLE ROW LEVEL SECURITY;

-- Todos autenticados leem (gestores precisam ver a fila completa)
CREATE POLICY "Autenticados leem solicitacoes cancelamento"
  ON public.ft_cancelamento_solicitacoes FOR SELECT TO authenticated
  USING (true);

-- Supervisor insere somente para FTs PENDENTES que ele mesmo lançou
CREATE POLICY "Supervisor solicita cancelamento"
  ON public.ft_cancelamento_solicitacoes FOR INSERT TO authenticated
  WITH CHECK (
    solicitado_por = auth.uid()
    AND public.has_role(auth.uid(), 'supervisor'::public.app_role)
    AND EXISTS (
      SELECT 1 FROM public.ft f
       WHERE f.id          = ft_id
         AND f.lancado_por = auth.uid()
         AND f.status      = 'PENDENTE'::public.ft_status
    )
  );

-- UPDATE e DELETE diretos bloqueados.
-- Use os RPCs SECURITY DEFINER: aprovar_cancelamento / rejeitar_cancelamento.

-- ============================================================
-- 12. Grants
-- ============================================================
GRANT SELECT, INSERT ON public.ft_cancelamento_solicitacoes TO authenticated;
GRANT ALL             ON public.ft_cancelamento_solicitacoes TO postgres, service_role;

-- ============================================================
-- ROLLBACK (executar manualmente em ordem):
--
-- DROP TRIGGER IF EXISTS trg_ft_cancelamento_cleanup ON public.ft;
-- DROP FUNCTION IF EXISTS public.tg_ft_cancelamento_cleanup();
-- DROP TABLE IF EXISTS public.ft_cancelamento_solicitacoes;
--   (dropa em cascata: triggers, índices, policies, FK)
-- DROP FUNCTION IF EXISTS public.tg_cancelamento_on_insert();
-- DROP FUNCTION IF EXISTS public.aprovar_cancelamento(UUID, TEXT);
-- DROP FUNCTION IF EXISTS public.rejeitar_cancelamento(UUID, TEXT);
-- Reverter tg_ft_validate_status para versão anterior:
-- CREATE OR REPLACE FUNCTION public.tg_ft_validate_status() ...
--   IF OLD.status = 'CANCELADA' AND NEW.status = 'APROVADA' THEN
--     RAISE EXCEPTION 'FT cancelada não pode ser aprovada';
--   END IF;
-- Nota: CANCELAMENTO_SOLICITADO permanece no enum — sem impacto se inativo.
-- ============================================================
