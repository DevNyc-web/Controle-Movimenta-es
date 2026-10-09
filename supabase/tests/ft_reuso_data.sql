-- TESTE DE STAGING/LOCAL — NÃO RODAR EM PRODUÇÃO. Requer as migrations 20261009120000 e 20261009120100 aplicadas no banco de teste.
-- Execução: SQL Editor de STAGING (role postgres) ou psql/PGlite com as migrations em ordem. Tudo em transação com ROLLBACK final.
-- Cobre: CANCELADA/NEGADA liberam a data (inclusive turno noturno 22h às 06h); FTs vivas (PENDENTE, APROVADA,
-- CANCELAMENTO_SOLICITADO) continuam bloqueando; reativar NEGADA sobre data ocupada dá 23505; CANCELADA continua imutável.

BEGIN;

INSERT INTO auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
VALUES ('00000000-0000-0000-0000-000000000000', 'c1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
        'reuso_gestor@teste.local', jsonb_build_object('username','reuso_gestor','nome','reuso_gestor','role','gestor'), now(), now());

INSERT INTO public.funcionarios (id, nome, re, cargo, setor, turno, status) VALUES
  ('d1000000-0000-0000-0000-000000000001', 'FERNANDO TESTE', 'REU-1', 'Vigilante', 'teste', 'noite', 'ativo'),
  ('d1000000-0000-0000-0000-000000000002', 'OUTRO TESTE',    'REU-2', 'Vigilante', 'teste', 'dia',   'ativo');

-- estado do índice
DO $$ BEGIN
  ASSERT NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.ft'::regclass AND conname = 'ft_funcionario_id_data_ft_key'), 'UNIQUE antigo removido';
  ASSERT (SELECT indexdef FROM pg_indexes WHERE indexname = 'ft_funcionario_data_ativa_key') LIKE '%WHERE%CANCELADA%NEGADA%', 'índice parcial exclui CANCELADA e NEGADA';
END $$;

CREATE TEMP TABLE _ins(n int);  -- helper: tenta inserir e devolve SQLSTATE ('' = ok)
CREATE FUNCTION pg_temp.tenta(p_fid uuid, p_data date, p_esc text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.ft (funcionario_id, data_ft, motivo, escala_servico, horas_trabalhadas, lancado_por, posto_falta)
  VALUES (p_fid, p_data, 'Falta', p_esc, 8, 'c1000000-0000-0000-0000-000000000002', NULL);
  RETURN '';
EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE;
END $$;

-- 1) Caso Fernando: FT noturna lançada errada, cancelada, relançada na mesma data
INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, escala_servico, horas_trabalhadas, lancado_por, posto_falta)
VALUES ('f4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', DATE '2026-03-05', 'Falta', 'Horário das 22h às 06h', 8, 'c1000000-0000-0000-0000-000000000002', NULL);
DO $$ BEGIN
  ASSERT pg_temp.tenta('d1000000-0000-0000-0000-000000000001', DATE '2026-03-05', 'Horário das 22h às 06h') = '23505', 'FT PENDENTE bloqueia a data';
END $$;
UPDATE public.ft SET status = 'CANCELADA' WHERE id = 'f4000000-0000-0000-0000-000000000001';
DO $$ BEGIN
  ASSERT pg_temp.tenta('d1000000-0000-0000-0000-000000000001', DATE '2026-03-05', 'Horário das 22h às 06h') = '', 'CANCELADA libera relançamento (22h às 06h)';
  ASSERT (SELECT count(*) FROM public.ft WHERE funcionario_id = 'd1000000-0000-0000-0000-000000000001' AND data_ft = DATE '2026-03-05') = 2, 'histórico preservado: CANCELADA + nova';
  ASSERT (SELECT status FROM public.ft WHERE id = 'f4000000-0000-0000-0000-000000000001') = 'CANCELADA', 'FT histórica intocada';
  ASSERT pg_temp.tenta('d1000000-0000-0000-0000-000000000001', DATE '2026-03-05', 'Horário das 06h às 16h') = '23505', 'nova FT viva bloqueia terceira';
END $$;

-- 2) NEGADA libera; depois APROVADA bloqueia
INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, escala_servico, horas_trabalhadas, lancado_por, posto_falta)
VALUES ('f4000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000002', DATE '2026-03-06', 'SDF', 'Horário das 22h às 06h', 8, 'c1000000-0000-0000-0000-000000000002', NULL);
UPDATE public.ft SET status = 'NEGADA' WHERE id = 'f4000000-0000-0000-0000-000000000002';
DO $$ BEGIN
  ASSERT pg_temp.tenta('d1000000-0000-0000-0000-000000000002', DATE '2026-03-06', 'Horário das 08h às 16h') = '', 'NEGADA libera relançamento';
END $$;
UPDATE public.ft SET status = 'APROVADA' WHERE funcionario_id = 'd1000000-0000-0000-0000-000000000002' AND data_ft = DATE '2026-03-06' AND status = 'PENDENTE';
DO $$ BEGIN
  ASSERT pg_temp.tenta('d1000000-0000-0000-0000-000000000002', DATE '2026-03-06', 'Horário das 08h às 16h') = '23505', 'APROVADA bloqueia';
-- 3) reativar a NEGADA com viva na data: 23505
  BEGIN
    UPDATE public.ft SET status = 'PENDENTE' WHERE id = 'f4000000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FALHA: NEGADA reativada sobre data ocupada';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END $$;

-- 4) CANCELAMENTO_SOLICITADO continua bloqueando
INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por, posto_falta)
VALUES ('f4000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000001', DATE '2026-03-07', 'Falta', 'c1000000-0000-0000-0000-000000000002', NULL);
UPDATE public.ft SET status = 'CANCELAMENTO_SOLICITADO' WHERE id = 'f4000000-0000-0000-0000-000000000003';
DO $$ BEGIN
  ASSERT pg_temp.tenta('d1000000-0000-0000-0000-000000000001', DATE '2026-03-07', NULL) = '23505', 'CANCELAMENTO_SOLICITADO bloqueia';
-- 5) CANCELADA nunca volta a status vivo (trigger existente), mesmo com a data livre
  BEGIN
    UPDATE public.ft SET status = 'PENDENTE' WHERE id = 'f4000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FALHA: CANCELADA voltou a PENDENTE';
  EXCEPTION WHEN raise_exception THEN
    ASSERT SQLERRM LIKE 'FT cancelada%', 'esperado bloqueio do trigger, veio: ' || SQLERRM;
  END;
END $$;

-- 6) NEGADA reativada com data livre é permitida (comportamento anterior mantido: nenhuma regra proíbe)
UPDATE public.ft SET status = 'CANCELADA' WHERE funcionario_id = 'd1000000-0000-0000-0000-000000000002' AND data_ft = DATE '2026-03-06' AND status = 'APROVADA';
DO $$ BEGIN
  UPDATE public.ft SET status = 'PENDENTE' WHERE id = 'f4000000-0000-0000-0000-000000000002';
  ASSERT (SELECT status FROM public.ft WHERE id = 'f4000000-0000-0000-0000-000000000002') = 'PENDENTE', 'NEGADA→PENDENTE com data livre';
END $$;

-- 7) Postos P252–P258 aceitos; posto inexistente continua recusado (requer também a migration 20261009120100)
DO $$ DECLARE p text; i int := 0; st text;
BEGIN
  FOREACH p IN ARRAY ARRAY['P252 L2 EMPREENDIMENTOS E PARTICIPACOES LTDA AREA 1 OBRA SR MURILO','P253 TREND LOFT NOVA MOGILAR','P254 OK BRAZIL TRANSPORTE E LOGISTICA LTDA',
    'P255 NGN SPLENDOR','P256 SP&G ENGENHARIA LTDA (DENTRO DA COCA COLA)','P257 CONDOMINIO SPAZIO SUBLIME','P258 COND. VILA CERES','P251 ACREDITAR FIDC AREA 1'] LOOP
    i := i + 1;
    INSERT INTO public.ft (funcionario_id, data_ft, motivo, lancado_por, posto_falta)
    VALUES ('d1000000-0000-0000-0000-000000000001', DATE '2026-04-01' + i, 'Falta', 'c1000000-0000-0000-0000-000000000002', p);
  END LOOP;
  BEGIN
    INSERT INTO public.ft (funcionario_id, data_ft, motivo, lancado_por, posto_falta)
    VALUES ('d1000000-0000-0000-0000-000000000001', DATE '2026-05-01', 'Falta', 'c1000000-0000-0000-0000-000000000002', 'P259 INEXISTENTE');
    RAISE EXCEPTION 'FALHA: posto inexistente aceito';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;

ROLLBACK;
