-- TESTE DE STAGING — NÃO RODAR EM PRODUÇÃO. Requer a migration 20260930203233 já aplicada no banco de teste.
-- Como executar: SQL Editor do projeto de STAGING (role postgres) ou `psql "$STAGING_DB_URL" -f supabase/tests/supervisor_window.sql`.
-- Tudo roda em transação com ROLLBACK final: nada persiste. Qualquer ASSERT falho aborta com a mensagem do caso.
-- Fixtures (UUIDs fixos): usuários a0..01 sup1, a0..02 sup2, a0..03 gestor, a0..04 admin, a0..05 apontamento.
-- "hoje" = data civil em America/Sao_Paulo (mesma regra da migration).
-- STATUS: validado localmente em PGlite (harness com shim de auth/roles do Supabase), inclusive com 20261030120000.

BEGIN;

-- ---------------------------------------------------------------- 0) limites da função (puro, sem fixtures)
DO $$
DECLARE h DATE := DATE '2026-09-20';
BEGIN
  ASSERT public.ft_na_janela_supervisor(h, h),                  'hoje deve ser visível';
  ASSERT public.ft_na_janela_supervisor(h - 7, h),              'hoje-7 deve ser visível (inclusivo)';
  ASSERT public.ft_na_janela_supervisor(h + 7, h),              'hoje+7 deve ser visível (inclusivo)';
  ASSERT NOT public.ft_na_janela_supervisor(h - 8, h),          'hoje-8 deve ser bloqueado';
  ASSERT NOT public.ft_na_janela_supervisor(h + 8, h),          'hoje+8 deve ser bloqueado';
  ASSERT public.ft_na_janela_supervisor(DATE '2027-01-03', DATE '2026-12-27'),     'virada de ano +7';
  ASSERT NOT public.ft_na_janela_supervisor(DATE '2027-01-04', DATE '2026-12-27'), 'virada de ano +8';
END $$;

-- 0b) fuso: o DEFAULT de _hoje deve usar America/Sao_Paulo e NÃO o fuso da sessão/servidor.
--     Com sessão em UTC+14 e UTC-11, current_date difere da data civil de São Paulo em qualquer horário (ao menos um dos dois).
DO $$
DECLARE tz text; hoje_sp date;
BEGIN
  FOREACH tz IN ARRAY ARRAY['Pacific/Kiritimati', 'Pacific/Pago_Pago', 'UTC'] LOOP
    PERFORM set_config('TimeZone', tz, true);
    hoje_sp := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
    ASSERT public.ft_na_janela_supervisor(hoje_sp - 7),     '[tz ' || tz || '] hoje-7 (SP) deve ser visível';
    ASSERT public.ft_na_janela_supervisor(hoje_sp + 7),     '[tz ' || tz || '] hoje+7 (SP) deve ser visível';
    ASSERT NOT public.ft_na_janela_supervisor(hoje_sp - 8), '[tz ' || tz || '] hoje-8 (SP) deve ser bloqueado';
    ASSERT NOT public.ft_na_janela_supervisor(hoje_sp + 8), '[tz ' || tz || '] hoje+8 (SP) deve ser bloqueado';
  END LOOP;
  PERFORM set_config('TimeZone', 'UTC', true);
END $$;

-- ---------------------------------------------------------------- 1) fixtures (como postgres, bypass de RLS)
-- handle_new_user cria profile + role a partir de raw_user_meta_data.role
INSERT INTO auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
SELECT '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
       jsonb_build_object('username', u.uname, 'nome', u.uname, 'role', u.role), now(), now()
FROM (VALUES
  ('a0000000-0000-0000-0000-000000000001'::uuid, 'sup1@teste.local',   'tst_sup1',   'supervisor'),
  ('a0000000-0000-0000-0000-000000000002'::uuid, 'sup2@teste.local',   'tst_sup2',   'supervisor'),
  ('a0000000-0000-0000-0000-000000000003'::uuid, 'gestor@teste.local', 'tst_gestor', 'gestor'),
  ('a0000000-0000-0000-0000-000000000004'::uuid, 'admin@teste.local',  'tst_admin',  'admin'),
  ('a0000000-0000-0000-0000-000000000005'::uuid, 'apont@teste.local',  'tst_apont',  'apontamento')
) AS u(id, email, uname, role);

-- Um funcionário por FT (evita o limite mensal de 4 FTs por funcionário).
-- FTs: n=1..6 sup1 (hoje, -7, +7, -8, +8, -400 [própria fora da janela]); n=7 sup2 hoje+3 (outro supervisor, dentro);
--      n=8 sup2 hoje-8 (outro supervisor, fora); n=9 sup1 hoje+400 (muito futura).
CREATE TEMP TABLE _fx (n int, dias int, lanc uuid) ON COMMIT DROP;
INSERT INTO _fx VALUES
  (1, 0,    'a0000000-0000-0000-0000-000000000001'),
  (2, -7,   'a0000000-0000-0000-0000-000000000001'),
  (3, 7,    'a0000000-0000-0000-0000-000000000001'),
  (4, -8,   'a0000000-0000-0000-0000-000000000001'),
  (5, 8,    'a0000000-0000-0000-0000-000000000001'),
  (6, -400, 'a0000000-0000-0000-0000-000000000001'),
  (7, 3,    'a0000000-0000-0000-0000-000000000002'),
  (8, -8,   'a0000000-0000-0000-0000-000000000002'),
  (9, 400,  'a0000000-0000-0000-0000-000000000001');

INSERT INTO public.funcionarios (id, nome, re, cargo, setor, turno)
SELECT ('e0000000-0000-0000-0000-00000000000' || n)::uuid, 'Func teste ' || n, 'TST-WIN-' || n, 'Vigilante', 'teste', 'dia'
FROM _fx;

INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por, posto_falta)
SELECT ('f0000000-0000-0000-0000-00000000000' || n)::uuid,
       ('e0000000-0000-0000-0000-00000000000' || n)::uuid,
       (now() AT TIME ZONE 'America/Sao_Paulo')::date + dias, 'Falta', lanc, NULL
FROM _fx;

-- Status distintos nas FTs próprias FORA da janela, para provar que o status não vaza:
--   ft4 (-8) PENDENTE | ft5 (+8) APROVADA | ft6 (-400) CANCELADA
UPDATE public.ft SET status = 'APROVADA'  WHERE id = 'f0000000-0000-0000-0000-000000000005';
UPDATE public.ft SET status = 'CANCELADA' WHERE id = 'f0000000-0000-0000-0000-000000000006';

-- Conjunto visível esperado por persona (IDs de FT f0..0N):
--   supervisor (sup1 OU sup2): {1,2,3,7}  -> hoje, -7, +7 e FT de OUTRO supervisor dentro da janela
--   admin / gestor / apontamento: {1..9}

-- Guarda de catálogo: nenhuma função pública chamável por authenticated pode agregar/expor FT sem revisão.
-- Se este ASSERT falhar, alguém criou uma RPC nova (ou a plataforma adicionou uma): revisar se respeita a janela.
DO $$
DECLARE extra text;
BEGIN
  SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO extra
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.prorettype <> 'trigger'::regtype
    AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
    AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e') -- ignora funções de extensões (ex.: pgcrypto em public)
    AND p.proname NOT IN ('has_role', 'valor_folga_por_cargo', 'aprovar_cancelamento', 'rejeitar_cancelamento',
                          'ft_na_janela_supervisor', 'pode_ver_ft_data', 'supervisor_restrito');
  ASSERT extra IS NULL, 'RPC/função nova executável por authenticated, revisar vazamento de FT: ' || extra;
END $$;

-- ---------------------------------------------------------------- 2) SUPERVISOR (sup1): leitura e agregações
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', true);

DO $$
DECLARE v int[];
BEGIN
  SELECT array_agg(right(id::text, 1)::int ORDER BY id) INTO v FROM public.ft WHERE id::text LIKE 'f0000000-0000-0000-0000-00000000000_';
  ASSERT v = ARRAY[1,2,3,7], 'SUPERVISOR sup1 deve ver exatamente {hoje,-7,+7,FT de outro supervisor}; viu ' || coalesce(v::text, 'nada');
  -- agregações (o que o dashboard/relatório fazem via PostgREST) passam pela RLS: só a janela entra
  ASSERT (SELECT count(*) FROM public.ft WHERE id::text LIKE 'f0000000-0000-0000-0000-00000000000_') = 4, 'count(*) do supervisor deve ser 4';
  ASSERT (SELECT sum(valor_pago) FROM public.ft WHERE id::text LIKE 'f0000000-0000-0000-0000-00000000000_') = 800, 'sum(valor_pago) do supervisor deve ser 800 (4 FTs x 200)';
  ASSERT (SELECT count(DISTINCT funcionario_id) FROM public.ft WHERE id::text LIKE 'f0000000-0000-0000-0000-00000000000_') = 4, 'funcionários distintos do supervisor devem ser 4';
  -- FT de sup2 dentro da janela visível => SELECT não filtra por lancado_por
  ASSERT EXISTS (SELECT 1 FROM public.ft WHERE id = 'f0000000-0000-0000-0000-000000000007'), 'FT de outro supervisor dentro da janela deve ser visível';
  -- acesso direto por ID fora da janela (própria -8, +8, -400, +400 e de outro -8)
  ASSERT NOT EXISTS (SELECT 1 FROM public.ft WHERE id IN ('f0000000-0000-0000-0000-000000000004','f0000000-0000-0000-0000-000000000005',
                     'f0000000-0000-0000-0000-000000000006','f0000000-0000-0000-0000-000000000008','f0000000-0000-0000-0000-000000000009')),
         'acesso direto por ID fora da janela deve ser bloqueado';
  -- tabelas dependentes não vazam FT fora da janela
  ASSERT NOT EXISTS (SELECT 1 FROM public.ft_historico WHERE ft_id IN ('f0000000-0000-0000-0000-000000000004','f0000000-0000-0000-0000-000000000006')),
         'ft_historico de FT fora da janela deve ser invisível';
  ASSERT EXISTS (SELECT 1 FROM public.ft_historico WHERE ft_id = 'f0000000-0000-0000-0000-000000000001'), 'ft_historico de FT na janela deve ser visível';
END $$;

-- ---------------------------------------------------------------- 3) SUPERVISOR (sup1): solicitação de cancelamento
-- Cada tentativa negada deve devolver EXATAMENTE o mesmo (SQLSTATE, mensagem) da negação real da RLS (caso C).
-- Desde 20261030120000 qualquer supervisor solicita cancelamento de FT PENDENTE de outro supervisor (caso F).
DO $$
DECLARE
  generic_state text; generic_msg text;
  r record; st text; msg text; sol uuid;
BEGIN
  -- C) solicitado_por forjado (sup2) em FT PENDENTE na janela: o trigger passa e a RLS (solicitado_por = auth.uid()) nega.
  --    É a referência da negação genérica. A FT não pode ficar alterada (o UPDATE do trigger é desfeito junto).
  BEGIN
    INSERT INTO public.ft_cancelamento_solicitacoes (ft_id, solicitado_por, motivo)
    VALUES ('f0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000002', 'teste solicitante forjado');
    RAISE EXCEPTION 'FALHA(C): supervisor registrou solicitação em nome de outro usuário';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS generic_msg = MESSAGE_TEXT; generic_state := SQLSTATE;
  END;
  ASSERT generic_state = '42501', 'C: esperado 42501, veio ' || coalesce(generic_state, 'nada');
  ASSERT (SELECT status FROM public.ft WHERE id = 'f0000000-0000-0000-0000-000000000002') = 'PENDENTE',
         'C: negação da RLS deve desfazer a mudança de status feita pelo trigger';

  -- F) FT de OUTRO supervisor (sup2), dentro da janela, PENDENTE: agora permitido. Solicitante = sup1, lançador continua sup2.
  INSERT INTO public.ft_cancelamento_solicitacoes (ft_id, solicitado_por, motivo)
  VALUES ('f0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000001', 'sup1 pede FT de sup2')
  RETURNING id INTO sol;
  ASSERT (SELECT status FROM public.ft WHERE id = 'f0000000-0000-0000-0000-000000000007') = 'CANCELAMENTO_SOLICITADO',
         'F: FT de outro supervisor deve virar CANCELAMENTO_SOLICITADO';
  ASSERT (SELECT solicitado_por FROM public.ft_cancelamento_solicitacoes WHERE id = sol) = 'a0000000-0000-0000-0000-000000000001',
         'F: solicitado_por deve ser o supervisor autenticado (sup1)';
  ASSERT (SELECT lancado_por FROM public.ft WHERE id = 'f0000000-0000-0000-0000-000000000007') = 'a0000000-0000-0000-0000-000000000002',
         'F: lancado_por deve continuar sendo sup2';
  ASSERT (SELECT motivo || '|' || status FROM public.ft_cancelamento_solicitacoes WHERE id = sol) = 'sup1 pede FT de sup2|PENDENTE',
         'F: motivo e status PENDENTE preservados';
  ASSERT (SELECT alterado_por FROM public.ft_historico
           WHERE ft_id = 'f0000000-0000-0000-0000-000000000007' AND status_novo = 'CANCELAMENTO_SOLICITADO') = 'a0000000-0000-0000-0000-000000000001',
         'F: histórico da FT deve registrar sup1 como autor da solicitação';

  -- G) supervisor não aprova nem rejeita (nem a própria solicitação): RPCs exigem gestor/admin.
  BEGIN
    PERFORM public.aprovar_cancelamento(sol, 'auto-aprovação');
    RAISE EXCEPTION 'FALHA(G): supervisor aprovou cancelamento';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT;
    ASSERT msg LIKE 'PERMISSAO:%', 'G: aprovar por supervisor deve dar PERMISSAO; veio: ' || msg;
  END;
  BEGIN
    PERFORM public.rejeitar_cancelamento(sol, 'auto-rejeição');
    RAISE EXCEPTION 'FALHA(G): supervisor rejeitou cancelamento';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT;
    ASSERT msg LIKE 'PERMISSAO:%', 'G: rejeitar por supervisor deve dar PERMISSAO; veio: ' || msg;
  END;
  -- G2) sem policy de UPDATE: tentativa direta não altera nada (nem a solicitação, nem a FT)
  UPDATE public.ft_cancelamento_solicitacoes SET status = 'APROVADO', decidido_por = 'a0000000-0000-0000-0000-000000000001' WHERE id = sol;
  UPDATE public.ft SET status = 'CANCELADA' WHERE id = 'f0000000-0000-0000-0000-000000000007';
  ASSERT (SELECT status FROM public.ft_cancelamento_solicitacoes WHERE id = sol) = 'PENDENTE', 'G2: UPDATE direto na solicitação não pode ter efeito';
  ASSERT (SELECT status FROM public.ft WHERE id = 'f0000000-0000-0000-0000-000000000007') = 'CANCELAMENTO_SOLICITADO',
         'G2: supervisor não cancela FT diretamente';

  -- B/E/D) fora da janela com status distintos (PENDENTE, APROVADA, CANCELADA), FT de outro supervisor fora da janela
  -- e ID inexistente: todas devem ser indistinguíveis da negação genérica acima.
  FOR r IN
    SELECT * FROM (VALUES
      ('B ft4 -8 PENDENTE própria',   'f0000000-0000-0000-0000-000000000004'::uuid),
      ('E ft5 +8 APROVADA própria',   'f0000000-0000-0000-0000-000000000005'::uuid),
      ('E ft6 -400 CANCELADA própria','f0000000-0000-0000-0000-000000000006'::uuid),
      ('B ft8 -8 de outro supervisor','f0000000-0000-0000-0000-000000000008'::uuid),
      ('D ID inexistente',            'f0000000-0000-0000-0000-0000000000ff'::uuid)
    ) AS t(caso, ft_id)
  LOOP
    st := NULL; msg := NULL;
    BEGIN
      INSERT INTO public.ft_cancelamento_solicitacoes (ft_id, solicitado_por, motivo)
      VALUES (r.ft_id, 'a0000000-0000-0000-0000-000000000001', 'teste fora da janela');
      RAISE EXCEPTION 'FALHA(%): solicitação foi aceita', r.caso;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; st := SQLSTATE;
    END;
    ASSERT st = generic_state AND msg = generic_msg,
      format('caso %s vazou informação: SQLSTATE %s / "%s" (esperado %s / "%s")', r.caso, st, msg, generic_state, generic_msg);
  END LOOP;

  -- A) FT própria, dentro da janela (hoje) e PENDENTE: solicitação normal
  INSERT INTO public.ft_cancelamento_solicitacoes (ft_id, solicitado_por, motivo)
  VALUES ('f0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'teste dentro da janela');
  ASSERT (SELECT status FROM public.ft WHERE id = 'f0000000-0000-0000-0000-000000000001') = 'CANCELAMENTO_SOLICITADO',
         'A: FT própria na janela deve virar CANCELAMENTO_SOLICITADO';
END $$;

-- ---------------------------------------------------------------- 4) SUPERVISOR (sup2): visão simétrica + próprio dentro da janela
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
DO $$
DECLARE v int[];
BEGIN
  SELECT array_agg(right(id::text, 1)::int ORDER BY id) INTO v FROM public.ft WHERE id::text LIKE 'f0000000-0000-0000-0000-00000000000_';
  ASSERT v = ARRAY[1,2,3,7], 'SUPERVISOR sup2 deve ver as mesmas FTs da janela (inclusive as de sup1); viu ' || coalesce(v::text, 'nada');
  -- Duplicidade: ft7 já tem solicitação PENDENTE (de sup1); o lançador sup2 não cria outra.
  BEGIN
    INSERT INTO public.ft_cancelamento_solicitacoes (ft_id, solicitado_por, motivo)
    VALUES ('f0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000002', 'duplicada');
    RAISE EXCEPTION 'FALHA: solicitação duplicada aceita';
  EXCEPTION WHEN OTHERS THEN
    ASSERT SQLERRM LIKE 'ESTADO_INVALIDO:%', 'duplicada: esperado ESTADO_INVALIDO; veio: ' || SQLERRM;
  END;
  ASSERT (SELECT count(*) FROM public.ft_cancelamento_solicitacoes
           WHERE ft_id = 'f0000000-0000-0000-0000-000000000007' AND status = 'PENDENTE') = 1, 'deve existir só 1 solicitação PENDENTE para ft7';
  -- O que o detalhe da FT lê com o cliente do usuário (getSolicitacaoCancelamentoFt): o lançador sup2 vê quem pediu (sup1).
  ASSERT (SELECT solicitado_por FROM public.ft_cancelamento_solicitacoes
           WHERE ft_id = 'f0000000-0000-0000-0000-000000000007' AND status = 'PENDENTE') = 'a0000000-0000-0000-0000-000000000001',
         'sup2 deve ler a solicitação de ft7 com solicitado_por = sup1';
  -- sup2 solicita a FT de sup1 na janela (ft3): simétrico ao caso F
  INSERT INTO public.ft_cancelamento_solicitacoes (ft_id, solicitado_por, motivo)
  VALUES ('f0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000002', 'sup2 pede FT de sup1');
END $$;

-- ---------------------------------------------------------------- 5) ADMIN / GESTOR / APONTAMENTO — leitura sem janela
DO $$
DECLARE u uuid; v int[];
BEGIN
  FOREACH u IN ARRAY ARRAY['a0000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000005']::uuid[] LOOP
    PERFORM set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.sub', u::text, true);
    SELECT array_agg(right(id::text, 1)::int ORDER BY id) INTO v FROM public.ft WHERE id::text LIKE 'f0000000-0000-0000-0000-00000000000_';
    ASSERT v = ARRAY[1,2,3,4,5,6,7,8,9],
      'usuário ' || u || ' (admin/gestor/apontamento) deve ver TODAS as FTs (-8,+8,-400,+400, qualquer supervisor); viu ' || coalesce(v::text, 'nada');
    ASSERT (SELECT count(*) FROM public.ft WHERE id::text LIKE 'f0000000-0000-0000-0000-00000000000_') = 9, 'count(*) completo (9) para ' || u;
    ASSERT (SELECT sum(valor_pago) FROM public.ft WHERE id::text LIKE 'f0000000-0000-0000-0000-00000000000_') = 1800, 'sum(valor_pago) completo (1800) para ' || u;
  END LOOP;
END $$;

-- ---------------------------------------------------------------- 6) GESTOR / ADMIN — cancelamento: comportamento anterior preservado
-- (a) gestor NÃO cria solicitação (policy exige role supervisor): para FT existente, erro de RLS 42501 (como antes);
-- (b) para ID inexistente o trigger mantém a mensagem original "Movimentação não encontrada" (gestor não é supervisor restrito);
-- (c) gestor aprova e admin rejeita solicitações via RPC (comportamento original).
DO $$
DECLARE sol_sup1 uuid; sol_sup2 uuid; msg text; st text;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
  PERFORM set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', true);

  BEGIN
    INSERT INTO public.ft_cancelamento_solicitacoes (ft_id, solicitado_por, motivo)
    VALUES ('f0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000003', 'gestor tenta (FT fora da janela)');
    RAISE EXCEPTION 'FALHA: gestor criou solicitação';
  EXCEPTION WHEN insufficient_privilege THEN NULL; -- 42501, como antes
  END;

  BEGIN
    INSERT INTO public.ft_cancelamento_solicitacoes (ft_id, solicitado_por, motivo)
    VALUES ('f0000000-0000-0000-0000-0000000000ff', 'a0000000-0000-0000-0000-000000000003', 'gestor tenta (ID inexistente)');
    RAISE EXCEPTION 'FALHA: gestor criou solicitação';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; st := SQLSTATE;
    ASSERT msg = 'Movimentação não encontrada', 'gestor: mensagem original preservada para ID inexistente; veio: ' || msg;
  END;

  SELECT id INTO sol_sup1 FROM public.ft_cancelamento_solicitacoes WHERE ft_id = 'f0000000-0000-0000-0000-000000000001';
  SELECT id INTO sol_sup2 FROM public.ft_cancelamento_solicitacoes WHERE ft_id = 'f0000000-0000-0000-0000-000000000007';
  ASSERT sol_sup1 IS NOT NULL AND sol_sup2 IS NOT NULL, 'gestor deve enxergar as solicitações (FTs visíveis a ele)';

  PERFORM public.aprovar_cancelamento(sol_sup1, 'ok gestor');
  ASSERT (SELECT status FROM public.ft WHERE id = 'f0000000-0000-0000-0000-000000000001') = 'CANCELADA', 'gestor aprova => FT CANCELADA';

  PERFORM set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-000000000004","role":"authenticated"}', true);
  PERFORM set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', true);
  PERFORM public.rejeitar_cancelamento(sol_sup2, 'ok admin');
  ASSERT (SELECT status FROM public.ft WHERE id = 'f0000000-0000-0000-0000-000000000007') = 'PENDENTE', 'admin rejeita => FT volta a PENDENTE';
  ASSERT (SELECT solicitado_por::text || '|' || decidido_por::text || '|' || status FROM public.ft_cancelamento_solicitacoes WHERE id = sol_sup2)
         = 'a0000000-0000-0000-0000-000000000001|a0000000-0000-0000-0000-000000000004|REJEITADO',
         'rejeição preserva o solicitante (sup1) e registra o decisor (admin)';

  -- FT já CANCELADA (ft1, dentro da janela): nenhum supervisor solicita, nem quem não lançou.
  PERFORM set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
  PERFORM set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
  BEGIN
    INSERT INTO public.ft_cancelamento_solicitacoes (ft_id, solicitado_por, motivo)
    VALUES ('f0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002', 'FT já cancelada');
    RAISE EXCEPTION 'FALHA: solicitação para FT cancelada aceita';
  EXCEPTION WHEN OTHERS THEN
    ASSERT SQLERRM LIKE 'ESTADO_INVALIDO:%', 'FT cancelada: esperado ESTADO_INVALIDO; veio: ' || SQLERRM;
  END;
  -- Após rejeição, nova solicitação para a mesma FT é aceita (histórico mantém a anterior REJEITADO).
  INSERT INTO public.ft_cancelamento_solicitacoes (ft_id, solicitado_por, motivo)
  VALUES ('f0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000002', 'nova após rejeição');
  ASSERT (SELECT count(*) FROM public.ft_cancelamento_solicitacoes WHERE ft_id = 'f0000000-0000-0000-0000-000000000007') = 2,
         'ft7 deve manter a solicitação REJEITADO e ter 1 nova PENDENTE';

  -- Apontamento (não supervisor) continua sem poder solicitar, mesmo em FT PENDENTE visível.
  PERFORM set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-000000000005","role":"authenticated"}', true);
  PERFORM set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000005', true);
  BEGIN
    INSERT INTO public.ft_cancelamento_solicitacoes (ft_id, solicitado_por, motivo)
    VALUES ('f0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000005', 'apontamento tenta');
    RAISE EXCEPTION 'FALHA: apontamento criou solicitação';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  -- Gestor também não (policy exige role supervisor), mesmo em FT PENDENTE dentro da janela.
  PERFORM set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
  PERFORM set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', true);
  BEGIN
    INSERT INTO public.ft_cancelamento_solicitacoes (ft_id, solicitado_por, motivo)
    VALUES ('f0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000003', 'gestor tenta (na janela)');
    RAISE EXCEPTION 'FALHA: gestor criou solicitação';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  ASSERT (SELECT status FROM public.ft WHERE id = 'f0000000-0000-0000-0000-000000000002') = 'PENDENTE', 'tentativas negadas não alteram a FT';
END $$;

-- ---------------------------------------------------------------- 7) anônimo continua sem acesso
RESET ROLE;
SET LOCAL ROLE anon;
DO $$
BEGIN
  INSERT INTO public.ft_cancelamento_solicitacoes (ft_id, solicitado_por, motivo)
  VALUES ('f0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'anon tenta');
  RAISE EXCEPTION 'FALHA: anon criou solicitação';
EXCEPTION WHEN insufficient_privilege THEN NULL;
END $$;

RESET ROLE;
ROLLBACK;
