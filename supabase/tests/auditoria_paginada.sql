-- TESTE LOCAL — NÃO RODAR EM PRODUÇÃO. Execução: bash supabase/tests/rodar_local.sh (Postgres descartável; dados fictícios).
-- Auditoria paginada (20261118120000): percorre TODO o histórico por cursor, sem repetir nem pular (empates em created_at),
-- filtros no servidor (período no fuso de Brasília), CPF sempre mascarado, só Gestor ativo, nada é alterado.

BEGIN;

CREATE FUNCTION pg_temp.como(p_uid uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text; n bigint;
BEGIN
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    EXECUTE p_sql;
    GET DIAGNOSTICS n = ROW_COUNT;
    r := 'ok:' || n;
  EXCEPTION WHEN OTHERS THEN
    r := SQLSTATE || ' ' || SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN r;
END $$;

-- Uma página lida como o usuário (função roda como authenticated); devolve as linhas em JSON.
CREATE FUNCTION pg_temp.pagina(p_uid uuid, f jsonb, p_em timestamptz, p_id uuid, p_tam int) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE j jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC, x.id DESC), '[]'::jsonb) INTO j
    FROM public.auditoria_pagina((f->>'de')::date, (f->>'ate')::date, (f->>'user_id')::uuid, f->>'role', f->>'action', f->>'entity_type',
                                 p_em, p_id, p_tam) x;
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN j;
END $$;

-- Percorre todas as páginas (como a tela faz com "Carregar mais") e devolve as linhas na ordem recebida.
CREATE FUNCTION pg_temp.todas(p_uid uuid, f jsonb, p_tam int) RETURNS SETOF jsonb LANGUAGE plpgsql AS $$
DECLARE pg jsonb; em timestamptz; id_ uuid; n int := 0;
BEGIN
  LOOP
    pg := pg_temp.pagina(p_uid, f, em, id_, p_tam);
    RETURN QUERY SELECT e FROM jsonb_array_elements(pg) e;
    EXIT WHEN jsonb_array_length(pg) < p_tam;
    em := (pg->-1->>'created_at')::timestamptz; id_ := (pg->-1->>'id')::uuid;
    n := n + 1; IF n > 10000 THEN RAISE EXCEPTION 'laço sem fim'; END IF;
  END LOOP;
END $$;

INSERT INTO auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
SELECT '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.n || '@teste.local', jsonb_build_object('username', u.n, 'nome', u.n, 'role', u.r), now(), now()
FROM (VALUES
 ('cf000000-0000-0000-0000-000000000001'::uuid, 'pg_g', 'gestor'), ('cf000000-0000-0000-0000-000000000002'::uuid, 'pg_s', 'supervisor'),
 ('cf000000-0000-0000-0000-000000000003'::uuid, 'pg_a', 'admin'), ('cf000000-0000-0000-0000-000000000004'::uuid, 'pg_p', 'apontamento'),
 ('cf000000-0000-0000-0000-000000000005'::uuid, 'pg_r', 'rh'), ('cf000000-0000-0000-0000-000000000006'::uuid, 'pg_d', 'gestor')) u(id, n, r);
UPDATE public.profiles SET ativo = (username <> 'pg_d') WHERE username LIKE 'pg\__' ESCAPE '\';

-- 2500 registros fictícios: 1250 com o MESMO created_at (empate), 1250 espalhados; alguns com CPF aberto (JSON, texto, usuário).
INSERT INTO public.audit_logs (id, user_id, username, role, action, entity_type, entity_id, description, old_data, new_data, observacao, created_at)
SELECT gen_random_uuid(),
       CASE WHEN i % 3 = 0 THEN NULL WHEN i % 3 = 1 THEN 'cf000000-0000-0000-0000-000000000001'::uuid ELSE 'cf000000-0000-0000-0000-000000000002'::uuid END,
       CASE WHEN i % 3 = 1 THEN 'pg_g' WHEN i % 3 = 2 THEN 'pg_s' END,
       CASE WHEN i % 3 = 1 THEN 'gestor' WHEN i % 3 = 2 THEN 'supervisor' END,
       (ARRAY['INSERT', 'UPDATE', 'DELETE', 'CPF_ALTERADO'])[1 + i % 4],
       (ARRAY['ft', 'funcionarios', 'profiles'])[1 + i % 3],
       'pg-' || i,
       CASE WHEN i % 50 = 0 THEN 'Conferido pelo CPF 613.' || lpad((i % 1000)::text, 3, '0') || '.013-34' ELSE 'Registro ' || i END,
       CASE WHEN i % 7 = 0 THEN jsonb_build_object('cpf', '61300' || lpad((i % 1000000)::text, 6, '0')) END,
       jsonb_build_object('n', i, 'aninhado', jsonb_build_object('cpf', '613.' || lpad((i % 1000)::text, 3, '0') || '.039-80')),
       NULL,
       CASE WHEN i <= 1250 THEN '2026-06-01 12:00:00+00'::timestamptz ELSE '2026-01-01 00:00:00+00'::timestamptz + (i * interval '97 minutes') END
  FROM generate_series(1, 2500) i;
-- Limites do dia em Brasília (UTC-3): 09/03 23:59:59 local e 10/03 00:00:00 local.
INSERT INTO public.audit_logs (id, username, action, entity_type, created_at) VALUES
 ('af000000-0000-0000-0000-000000000001', '61300101334', 'LIMITE', 'teste_limite', '2026-03-10 02:59:59.999999+00'),
 ('af000000-0000-0000-0000-000000000002', 'pg_limite', 'LIMITE', 'teste_limite', '2026-03-10 03:00:00+00');

CREATE TEMP TABLE _antes ON COMMIT DROP AS SELECT md5(string_agg(to_jsonb(a)::text, '|' ORDER BY id)) m, count(*) n FROM public.audit_logs a;
GRANT SELECT ON _antes TO PUBLIC;

DO $$
DECLARE
  g CONSTANT uuid := 'cf000000-0000-0000-0000-000000000001';
  total int; lidos int; distintos int; fora_ordem int; tudo text; r text; u uuid; j jsonb; pg1 jsonb; tam int;
BEGIN
  SELECT count(*) INTO total FROM public.audit_logs;
  ASSERT total >= 2502, 'massa';

  -- 1. todas as páginas = todos os registros, uma única vez, na ordem (vários tamanhos, incluindo os que cortam empates)
  FOREACH tam IN ARRAY ARRAY[100, 7, 500, 1] LOOP
    CREATE TEMP TABLE _lido ON COMMIT DROP AS SELECT row_number() OVER () ord, e FROM pg_temp.todas(g, '{}', tam) e;
    SELECT count(*), count(DISTINCT e->>'id') INTO lidos, distintos FROM _lido;
    ASSERT lidos = total AND distintos = total, format('tam %s: lidos %s, distintos %s, total %s', tam, lidos, distintos, total);
    SELECT count(*) INTO fora_ordem FROM (
      SELECT (e->>'created_at')::timestamptz c, (e->>'id')::uuid i, lag((e->>'created_at')::timestamptz) OVER (ORDER BY ord) pc, lag((e->>'id')::uuid) OVER (ORDER BY ord) pi FROM _lido) x
     WHERE pc IS NOT NULL AND NOT ((c, i) < (pc, pi));
    ASSERT fora_ordem = 0, format('tam %s: %s fora de ordem', tam, fora_ordem);
    ASSERT (SELECT count(*) FROM _lido l JOIN public.audit_logs a ON a.id = (l.e->>'id')::uuid) = total, 'id inexistente';
    DROP TABLE _lido;
  END LOOP;

  -- 2. tamanho limitado a 1..500 (sempre abaixo das 1000 linhas da API)
  ASSERT jsonb_array_length(pg_temp.pagina(g, '{}', NULL, NULL, 100000)) = 500, 'tamanho máximo';
  ASSERT jsonb_array_length(pg_temp.pagina(g, '{}', NULL, NULL, 0)) = 1, 'tamanho mínimo';
  ASSERT jsonb_array_length(pg_temp.pagina(g, '{}', NULL, NULL, NULL)) = 100, 'tamanho padrão';

  -- 3. filtros no servidor = contagem direta
  ASSERT (SELECT count(*) FROM pg_temp.todas(g, jsonb_build_object('user_id', g), 500)) = (SELECT count(*) FROM public.audit_logs WHERE user_id = g), 'usuário';
  ASSERT (SELECT count(*) FROM pg_temp.todas(g, '{"role":"supervisor"}', 500)) = (SELECT count(*) FROM public.audit_logs WHERE role = 'supervisor'), 'perfil';
  ASSERT (SELECT count(*) FROM pg_temp.todas(g, '{"action":"CPF_ALTERADO"}', 500)) = (SELECT count(*) FROM public.audit_logs WHERE action = 'CPF_ALTERADO'), 'ação';
  ASSERT (SELECT count(*) FROM pg_temp.todas(g, '{"entity_type":"ft"}', 500)) = (SELECT count(*) FROM public.audit_logs WHERE entity_type = 'ft'), 'módulo';
  ASSERT (SELECT count(*) FROM pg_temp.todas(g, '{"role":"supervisor","action":"DELETE","entity_type":"profiles"}', 37))
       = (SELECT count(*) FROM public.audit_logs WHERE role = 'supervisor' AND action = 'DELETE' AND entity_type = 'profiles'), 'filtros combinados';
  ASSERT (SELECT count(*) FROM pg_temp.todas(g, '{"de":"2026-06-01","ate":"2026-06-01"}', 100))
       = (SELECT count(*) FROM public.audit_logs WHERE created_at >= '2026-06-01 03:00+00' AND created_at < '2026-06-02 03:00+00'), 'período com empate';
  ASSERT (SELECT count(*) FROM pg_temp.todas(g, '{"de":"2026-06-01","ate":"2026-06-01"}', 100)) >= 1250, 'empate inteiro no período';

  -- 4. limites do dia no fuso de Brasília
  ASSERT (SELECT string_agg(e->>'id', ',') FROM pg_temp.todas(g, '{"de":"2026-03-10","ate":"2026-03-10","action":"LIMITE"}', 10) e) = 'af000000-0000-0000-0000-000000000002', '10/03 local';
  ASSERT (SELECT string_agg(e->>'id', ',') FROM pg_temp.todas(g, '{"de":"2026-03-09","ate":"2026-03-09","action":"LIMITE"}', 10) e) = 'af000000-0000-0000-0000-000000000001', '09/03 23:59:59 local';
  ASSERT (SELECT count(*) FROM pg_temp.todas(g, '{"ate":"2026-03-09","action":"LIMITE"}', 10)) = 1 AND (SELECT count(*) FROM pg_temp.todas(g, '{"de":"2026-03-10","action":"LIMITE"}', 10)) = 1, 'só um limite';

  -- 5. cursor estável: registro novo durante a leitura não desloca nem repete páginas seguintes
  pg1 := pg_temp.pagina(g, '{}', NULL, NULL, 100);
  INSERT INTO public.audit_logs (id, action, entity_type, created_at) VALUES ('af000000-0000-0000-0000-0000000000ff', 'NOVO', 'teste_limite', now());
  -- a página seguinte (500) continua exatamente de onde a primeira parou: 600 registros distintos
  SELECT count(*), count(DISTINCT x) INTO lidos, distintos FROM (
    SELECT e->>'id' x FROM jsonb_array_elements(pg1) e
    UNION ALL
    SELECT e->>'id' FROM jsonb_array_elements(pg_temp.pagina(g, '{}', (pg1->-1->>'created_at')::timestamptz, (pg1->-1->>'id')::uuid, 500)) e) y;
  ASSERT lidos = distintos AND lidos = 600, format('cursor: lidos %s distintos %s', lidos, distintos);
  ASSERT NOT EXISTS (SELECT 1 FROM jsonb_array_elements(pg_temp.pagina(g, '{}', (pg1->-1->>'created_at')::timestamptz, (pg1->-1->>'id')::uuid, 500)) e
                      WHERE e->>'id' = 'af000000-0000-0000-0000-0000000000ff'), 'registro novo apareceu depois do cursor';
  DELETE FROM public.audit_logs WHERE id = 'af000000-0000-0000-0000-0000000000ff';

  -- 6. entradas inválidas
  r := pg_temp.como(g, $q$SELECT * FROM public.auditoria_pagina(NULL, NULL, NULL, NULL, NULL, NULL, now(), NULL, 10)$q$);
  ASSERT r LIKE 'P0001 AUDITORIA_CURSOR%', 'cursor pela metade: ' || r;
  r := pg_temp.como(g, $q$SELECT * FROM public.auditoria_pagina('2026-03-10', '2026-03-09')$q$);
  ASSERT r LIKE 'P0001 AUDITORIA_PERIODO%', 'período invertido: ' || r;

  -- 7. permissões: só o Gestor ativo; sem sessão, anon e service_role não executam
  FOREACH u IN ARRAY ARRAY['cf000000-0000-0000-0000-000000000002', 'cf000000-0000-0000-0000-000000000003', 'cf000000-0000-0000-0000-000000000004',
                           'cf000000-0000-0000-0000-000000000005', 'cf000000-0000-0000-0000-000000000006']::uuid[] LOOP
    ASSERT pg_temp.como(u, 'SELECT * FROM public.auditoria_pagina()') LIKE 'P0001 PERMISSAO%', 'outro perfil ou Gestor inativo leu a página: ' || u;
    ASSERT pg_temp.como(u, 'SELECT public.auditoria_filtros()') LIKE 'P0001 PERMISSAO%', 'outro perfil ou Gestor inativo leu os filtros: ' || u;
  END LOOP;
  ASSERT pg_temp.como(NULL, 'SELECT * FROM public.auditoria_pagina()') LIKE 'P0001 PERMISSAO%', 'sem sessão';
  ASSERT NOT has_function_privilege('anon', 'public.auditoria_pagina(date, date, uuid, text, text, text, timestamptz, uuid, integer)', 'EXECUTE')
     AND NOT has_function_privilege('anon', 'public.auditoria_filtros()', 'EXECUTE')
     AND NOT has_function_privilege('service_role', 'public.auditoria_pagina(date, date, uuid, text, text, text, timestamptz, uuid, integer)', 'EXECUTE')
     AND NOT has_function_privilege('service_role', 'public.auditoria_filtros()', 'EXECUTE'), 'EXECUTE para anon/service_role';
  ASSERT has_function_privilege('authenticated', 'public.auditoria_pagina(date, date, uuid, text, text, text, timestamptz, uuid, integer)', 'EXECUTE'), 'authenticated';

  -- 8. SECURITY DEFINER com search_path vazio (tudo qualificado; sem sequestro por objeto temporário ou de outro schema)
  ASSERT (SELECT bool_and(p.prosecdef) AND bool_and(p.proconfig = ARRAY['search_path=""']) FROM pg_proc p
           WHERE p.oid IN ('public.auditoria_pagina(date, date, uuid, text, text, text, timestamptz, uuid, integer)'::regprocedure, 'public.auditoria_filtros()'::regprocedure)),
         'SECURITY DEFINER / search_path';
  -- tabela temporária com o mesmo nome não é usada pela função
  CREATE TEMP TABLE audit_logs (id uuid) ON COMMIT DROP;
  ASSERT jsonb_array_length(pg_temp.pagina(g, '{}', NULL, NULL, 5)) = 5, 'função usou tabela temporária';
  DROP TABLE pg_temp.audit_logs;

  -- 9. máscara em TODAS as páginas: nenhum CPF completo; chaves cpf mascaradas
  SELECT string_agg(e::text, '|') INTO tudo FROM pg_temp.todas(g, '{}', 500) e;
  ASSERT tudo !~ '(?<![0-9A-Za-z])[0-9]{3}[ ./-]?[0-9]{3}[ ./-]?[0-9]{3}[ ./-]?[0-9]{2}(?![0-9A-Za-z])', 'CPF completo na leitura paginada';
  SELECT e INTO j FROM pg_temp.todas(g, '{"action":"LIMITE"}', 10) e WHERE e->>'id' = 'af000000-0000-0000-0000-000000000001';
  ASSERT j->>'username' = '***.001.013-**', 'usuário mascarado: ' || j::text;
  ASSERT (SELECT count(*) FROM pg_temp.todas(g, '{}', 500) e WHERE e->'new_data'->'aninhado'->>'cpf' LIKE '***.%') >= 2500, 'cpf aninhado mascarado';
  j := NULL;
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', g, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT public.auditoria_filtros() INTO j;
  PERFORM set_config('role', 'postgres', true);
  ASSERT j::text !~ '(?<![0-9A-Za-z])[0-9]{3}[ ./-]?[0-9]{3}[ ./-]?[0-9]{3}[ ./-]?[0-9]{2}(?![0-9A-Za-z])', 'CPF completo nos filtros';
  ASSERT j->'acoes' ? 'CPF_ALTERADO' AND j->'perfis' ? 'supervisor' AND j->'modulos' ? 'ft', 'opções: ' || left(j::text, 200);
  ASSERT EXISTS (SELECT 1 FROM jsonb_array_elements(j->'usuarios') x WHERE x->>'id' = g::text AND x->>'username' = 'pg_g'), 'usuário nas opções';

  -- 10. leitura não altera nada; auditoria_listar continua como antes
  ASSERT (SELECT md5(string_agg(to_jsonb(a)::text, '|' ORDER BY id)) FROM public.audit_logs a) = (SELECT m FROM _antes), 'audit_logs alterado pela leitura';
  ASSERT pg_temp.como(g, 'SELECT * FROM public.auditoria_listar(3)') = 'ok:3', 'auditoria_listar';
  ASSERT pg_temp.como(g, 'SELECT * FROM public.audit_logs') LIKE '42501%', 'leitura direta liberada';

  -- 11. o índice do cursor existe
  ASSERT to_regclass('public.idx_audit_logs_created_id') IS NOT NULL, 'índice';
END $$;

ROLLBACK;
