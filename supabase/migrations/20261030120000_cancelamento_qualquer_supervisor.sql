-- Qualquer supervisor pode SOLICITAR cancelamento de FT PENDENTE, inclusive lançada por outro supervisor.
-- Única mudança: sai "f.lancado_por = auth.uid()" da policy de INSERT. Não toca em dados, triggers, RPCs nem leitura.
-- Mantido: solicitado_por = auth.uid() (grava quem pediu, nunca o lançador), role supervisor, FT PENDENTE.
-- Continuam valendo: janela ±7 dias (EXISTS em ft sob a RLS "Read ft com janela supervisor" + tg_cancelamento_on_insert),
-- uq_ft_cancelamento_pendente (uma PENDENTE por FT), aprovar/rejeitar só gestor/admin (RPCs).
-- Policy de produção conferida (somente leitura) em 2026-10-30: idêntica à de 20260609130000.
DROP POLICY IF EXISTS "Supervisor solicita cancelamento" ON public.ft_cancelamento_solicitacoes;
CREATE POLICY "Supervisor solicita cancelamento"
  ON public.ft_cancelamento_solicitacoes FOR INSERT TO authenticated
  WITH CHECK (
    solicitado_por = auth.uid()
    AND public.has_role(auth.uid(), 'supervisor'::public.app_role)
    AND EXISTS (
      SELECT 1 FROM public.ft f
       WHERE f.id     = ft_id
         AND f.status = 'PENDENTE'::public.ft_status
    )
  );

-- ROLLBACK manual (restaura a regra "somente quem lançou"):
-- DROP POLICY IF EXISTS "Supervisor solicita cancelamento" ON public.ft_cancelamento_solicitacoes;
-- CREATE POLICY "Supervisor solicita cancelamento"
--   ON public.ft_cancelamento_solicitacoes FOR INSERT TO authenticated
--   WITH CHECK (
--     solicitado_por = auth.uid()
--     AND public.has_role(auth.uid(), 'supervisor'::public.app_role)
--     AND EXISTS (
--       SELECT 1 FROM public.ft f
--        WHERE f.id          = ft_id
--          AND f.lancado_por = auth.uid()
--          AND f.status      = 'PENDENTE'::public.ft_status
--     )
--   );
-- Solicitações já criadas entre supervisores diferentes permanecem válidas e seguem o fluxo normal de aprovação.
