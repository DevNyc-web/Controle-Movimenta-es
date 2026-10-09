-- TESTE DE STAGING/LOCAL — NÃO RODAR EM PRODUÇÃO. Requer as migrations 20261006120000 e 20261009120000 já aplicada no banco de teste.
-- Como executar: SQL Editor do projeto de STAGING (role postgres) ou `psql "$STAGING_DB_URL" -f supabase/tests/limite_mensal.sql`
-- (ou PGlite local, com as migrations aplicadas em ordem). Tudo roda em transação com ROLLBACK final: nada persiste.
-- Cobre: o limite mensal deixou de BLOQUEAR (5ª, 6ª, 7ª... FT aceitas) e o restante de tg_ft_before_insert() foi preservado
-- (valor_pago por cargo, PERMISSAO_FERIAS, UNIQUE funcionario/data, SECURITY DEFINER, grants, trigger) + janela do supervisor.
-- Fixtures (UUIDs fixos): usuários c0..01 supervisor, c0..02 gestor.

BEGIN;

INSERT INTO auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
SELECT '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
       jsonb_build_object('username', u.uname, 'nome', u.uname, 'role', u.role), now(), now()
FROM (VALUES
  ('c0000000-0000-0000-0000-000000000001'::uuid, 'lim_sup@teste.local',    'lim_sup',    'supervisor'),
  ('c0000000-0000-0000-0000-000000000002'::uuid, 'lim_gestor@teste.local', 'lim_gestor', 'gestor')
) AS u(id, email, uname, role);

-- F1 e F2 têm o MESMO nome (IDs/REs diferentes); F3 está de férias.
INSERT INTO public.funcionarios (id, nome, re, cargo, setor, turno, status) VALUES
  ('d0000000-0000-0000-0000-000000000001', 'JOAO TESTE', 'LIM-1', 'Vigilante', 'teste', 'dia', 'ativo'),
  ('d0000000-0000-0000-0000-000000000002', 'JOAO TESTE', 'LIM-2', 'Porteiro',  'teste', 'dia', 'ativo'),
  ('d0000000-0000-0000-0000-000000000003', 'MARIA FERIAS', 'LIM-3', 'ASG',     'teste', 'dia', 'ferias');

-- ---------------------------------------------------------------- 1) definição da função: bloqueio saiu, o resto ficou
DO $$
DECLARE def text := pg_get_functiondef('public.tg_ft_before_insert()'::regprocedure);
BEGIN
  ASSERT position('LIMITE_MENSAL' in def) = 0,              'o bloqueio LIMITE_MENSAL deve ter sido removido';
  ASSERT position('v_count' in def) = 0,                    'v_count não deveria sobrar sem uso';
  ASSERT position('PERMISSAO_FERIAS' in def) > 0,           'regra de férias deve ser preservada';
  ASSERT position('valor_folga_por_cargo' in def) > 0,      'atribuição de valor_pago deve ser preservada';
  ASSERT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.tg_ft_before_insert()'::regprocedure), 'SECURITY DEFINER preservado';
  ASSERT (SELECT 'search_path=public' = ANY (proconfig) FROM pg_proc WHERE oid = 'public.tg_ft_before_insert()'::regprocedure), 'search_path preservado';
  ASSERT NOT has_function_privilege('authenticated', 'public.tg_ft_before_insert()', 'EXECUTE'), 'grants preservados (authenticated sem EXECUTE)';
  ASSERT NOT has_function_privilege('anon', 'public.tg_ft_before_insert()', 'EXECUTE'),          'grants preservados (anon sem EXECUTE)';
  ASSERT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_ft_before_insert' AND tgrelid = 'public.ft'::regclass AND tgenabled = 'O'),
         'trigger trg_ft_before_insert deve continuar ativo em public.ft';
  ASSERT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'ft_funcionario_data_ativa_key'),
         'índice único parcial (funcionario_id, data_ft) deve existir (migration 20261009120000 aplicada)';
END $$;

-- ---------------------------------------------------------------- 2) 1ª..7ª FT do mesmo funcionário no mesmo mês: todas aceitas
-- (março/2026: todas fora da janela do supervisor; valor_pago informado como 1 deve ser sobrescrito pelo cargo)
DO $$
DECLARE i int;
BEGIN
  FOR i IN 1..7 LOOP
    BEGIN
      INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por, posto_falta, valor_pago)
      VALUES (('f1000000-0000-0000-0000-00000000000' || i)::uuid, 'd0000000-0000-0000-0000-000000000001',
              DATE '2026-03-01' + i, 'Falta', 'c0000000-0000-0000-0000-000000000002', NULL, 1);
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'FT % do mês foi recusada (%): %', i, SQLSTATE, SQLERRM;
    END;
  END LOOP;
  ASSERT (SELECT count(*) FROM public.ft WHERE funcionario_id = 'd0000000-0000-0000-0000-000000000001') = 7, 'as 7 FTs devem existir';
  ASSERT (SELECT bool_and(valor_pago = 200) FROM public.ft WHERE funcionario_id = 'd0000000-0000-0000-0000-000000000001'),
         'valor_pago deve vir do cargo (Vigilante = 200) em TODAS, inclusive 5ª, 6ª e 7ª';
END $$;

-- funcionário diferente (mesmo nome) e outro mês continuam livres
INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por, posto_falta)
VALUES ('f1000000-0000-0000-0000-0000000000a1', 'd0000000-0000-0000-0000-000000000002', DATE '2026-03-02', 'Falta', 'c0000000-0000-0000-0000-000000000002', NULL),
       ('f1000000-0000-0000-0000-0000000000a2', 'd0000000-0000-0000-0000-000000000001', DATE '2026-04-02', 'Falta', 'c0000000-0000-0000-0000-000000000002', NULL);
DO $$ BEGIN
  ASSERT (SELECT valor_pago FROM public.ft WHERE id = 'f1000000-0000-0000-0000-0000000000a1') = 150, 'valor_pago do Porteiro = 150';
END $$;

-- ---------------------------------------------------------------- 3) UNIQUE (funcionario_id, data_ft) continua valendo (agora é o único freio)
DO $$
DECLARE st text;
BEGIN
  BEGIN
    INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por, posto_falta)
    VALUES ('f1000000-0000-0000-0000-0000000000b1', 'd0000000-0000-0000-0000-000000000001', DATE '2026-03-02', 'Falta', 'c0000000-0000-0000-0000-000000000002', NULL);
    RAISE EXCEPTION 'FALHA: mesma data para o mesmo funcionário foi aceita';
  EXCEPTION WHEN unique_violation THEN st := SQLSTATE;
  END;
  ASSERT st = '23505', 'segunda FT do mesmo funcionário no mesmo dia deve dar 23505';
END $$;

-- ---------------------------------------------------------------- 4) regra de férias preservada
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"c0000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000001', true);
DO $$
DECLARE msg text;
BEGIN
  BEGIN  -- supervisor lançando para funcionário em férias: PERMISSAO_FERIAS
    INSERT INTO public.ft (funcionario_id, data_ft, motivo, lancado_por, posto_falta)
    VALUES ('d0000000-0000-0000-0000-000000000003', DATE '2026-03-10', 'Falta', 'c0000000-0000-0000-0000-000000000001', NULL);
    RAISE EXCEPTION 'FALHA: supervisor lançou FT para funcionário de férias';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT;
  END;
  ASSERT msg LIKE 'PERMISSAO_FERIAS:%', 'esperado PERMISSAO_FERIAS, veio: ' || coalesce(msg, 'nada');
END $$;

-- ---------------------------------------------------------------- 5) supervisor: 5ª e 6ª FT aceitas pela RLS+trigger; a janela -7/+7 continua valendo
DO $$
DECLARE i int; hoje date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
  FOR i IN 1..6 LOOP  -- F2 (mesmo nome de F1): 6 FTs em março, fora da janela
    INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por, posto_falta)
    VALUES (('f2000000-0000-0000-0000-00000000000' || i)::uuid, 'd0000000-0000-0000-0000-000000000002',
            DATE '2026-03-10' + i, 'Falta', 'c0000000-0000-0000-0000-000000000001', NULL);
  END LOOP;
  -- uma FT dentro da janela (hoje) do mesmo supervisor
  INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por, posto_falta)
  VALUES ('f2000000-0000-0000-0000-0000000000aa', 'd0000000-0000-0000-0000-000000000001', hoje, 'Falta', 'c0000000-0000-0000-0000-000000000001', NULL);
  ASSERT (SELECT count(*) FROM public.ft WHERE id::text LIKE 'f2000000-%' ) = 1,
         'supervisor só enxerga a FT dentro da janela (as 6 de março ficam invisíveis)';
  ASSERT NOT EXISTS (SELECT 1 FROM public.ft WHERE id = 'f2000000-0000-0000-0000-000000000005'), 'a 5ª FT (fora da janela) não pode ser lida pelo supervisor';
  ASSERT (SELECT count(*) FROM public.ft WHERE funcionario_id = 'd0000000-0000-0000-0000-000000000001' AND data_ft < DATE '2026-12-31' AND data_ft >= DATE '2026-03-01' AND data_ft <= DATE '2026-04-30') = 0,
         'FTs antigas do F1 também continuam invisíveis ao supervisor';
END $$;

-- ---------------------------------------------------------------- 6) gestor: acesso irrestrito e 5ª FT aceita
SELECT set_config('request.jwt.claims', '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000002', true);
DO $$
BEGIN
  ASSERT (SELECT count(*) FROM public.ft WHERE id::text LIKE 'f2000000-%') = 7, 'gestor vê as 7 FTs (sem janela)';
  ASSERT (SELECT count(*) FROM public.ft WHERE funcionario_id = 'd0000000-0000-0000-0000-000000000002' AND data_ft BETWEEN DATE '2026-03-01' AND DATE '2026-03-31') = 7,
         'gestor vê as 7 FTs de março do F2 (1 de F2 do passo 2 + 6 do supervisor)';
  -- gestor lança a 8ª FT de março do F1 (já tem 7) e para funcionário em férias (permitido a gestor)
  INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por, posto_falta)
  VALUES ('f3000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', DATE '2026-03-20', 'Falta', 'c0000000-0000-0000-0000-000000000002', NULL),
         ('f3000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000003', DATE '2026-03-10', 'Falta', 'c0000000-0000-0000-0000-000000000002', NULL);
  ASSERT (SELECT count(*) FROM public.ft WHERE funcionario_id = 'd0000000-0000-0000-0000-000000000001' AND data_ft BETWEEN DATE '2026-03-01' AND DATE '2026-03-31') = 8,
         'a 8ª FT do F1 em março foi aceita';
END $$;

RESET ROLE;
ROLLBACK;
