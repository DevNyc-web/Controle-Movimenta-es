-- TESTE LOCAL — NÃO RODAR EM PRODUÇÃO. Execução: bash supabase/tests/rodar_local.sh (Postgres descartável; dados fictícios).
-- Auditoria (opção B): sem leitura direta de audit_logs; Gestor lê por auditoria_listar() com CPF mascarado; registros intactos.

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
-- Lê como o Gestor e devolve o resultado para conferir (a função roda como authenticated)
CREATE FUNCTION pg_temp.lista(p_uid uuid) RETURNS SETOF jsonb LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  RETURN QUERY SELECT to_jsonb(x) FROM public.auditoria_listar(5000) x;
  PERFORM set_config('role', 'postgres', true);
END $$;

INSERT INTO auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
SELECT '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.n || '@teste.local', jsonb_build_object('username', u.n, 'nome', u.n, 'role', u.r), now(), now()
FROM (VALUES
 ('ce000000-0000-0000-0000-000000000001'::uuid, 'ag', 'gestor'), ('ce000000-0000-0000-0000-000000000002'::uuid, 'as', 'supervisor'),
 ('ce000000-0000-0000-0000-000000000003'::uuid, 'aa', 'admin'), ('ce000000-0000-0000-0000-000000000004'::uuid, 'ap', 'apontamento'),
 ('ce000000-0000-0000-0000-000000000005'::uuid, 'ar', 'rh'), ('ce000000-0000-0000-0000-000000000006'::uuid, 'ad', 'gestor')) u(id, n, r);
UPDATE public.profiles SET ativo = (username <> 'ad') WHERE username IN ('ag', 'as', 'aa', 'ap', 'ar', 'ad');

-- Registros ANTIGOS, como os de produção antes da 20261110: CPF aberto no JSON e em texto livre (fictícios).
INSERT INTO public.audit_logs (id, user_id, username, role, action, entity_type, entity_id, description, old_data, new_data, observacao) VALUES
 ('ad000000-0000-0000-0000-000000000001', 'ce000000-0000-0000-0000-000000000001', 'ag', 'gestor', 'UPDATE', 'funcionarios', 'ca000000-0000-0000-0000-000000000001',
  'Atualizou registro', '{"id":"ca000000-0000-0000-0000-000000000001","nome":"ANTIGO","cpf":"61300101334","banco_horas":0}',
  '{"id":"ca000000-0000-0000-0000-000000000001","nome":"ANTIGO NOVO","cpf":"613.001.013-34","extra":{"cpf":"61300202602","lista":["texto 613.003.039-80 livre"]}}',
  'Conferido pelo CPF 61300405201 no RH'),
 ('ad000000-0000-0000-0000-000000000002', 'ce000000-0000-0000-0000-000000000001', 'ag', 'gestor', 'INSERT', 'funcionarios', 'ca000000-0000-0000-0000-000000000002',
  'Criou registro', NULL, '{"nome":"SEM CPF","cpf":null,"cnpj":"12.345.678/0001-95","outro":"12345678000195","telefone_ddd":"(11) 98765-4321"}', NULL),
 ('ad000000-0000-0000-0000-000000000003', 'ce000000-0000-0000-0000-000000000001', 'ag', 'gestor', 'CPF_ALTERADO', 'funcionarios', 'ca000000-0000-0000-0000-000000000003',
  'CPF do funcionário alterado', '{"cpf":"***.001.013-**"}', '{"cpf":"***.002.026-**"}', 'Documento conferido'),
 ('ad000000-0000-0000-0000-000000000004', 'ce000000-0000-0000-0000-000000000001', 'ag', 'gestor', 'UPDATE', 'funcionarios', 'ca000000-0000-0000-0000-000000000004',
  'Atualizou registro', NULL, '{"cpf":61300506580,"numero_grande":123456789012,"data":"2026-11-09T22:18:27.419079+00"}', NULL);
INSERT INTO public.audit_logs (id, username, action, entity_type, entity_id, description, old_data, new_data, observacao) VALUES
 ('ad000000-0000-0000-0000-000000000005', '61300101334', 'UPDATE', 'funcionarios', '61300202602', 'com espacos 613 003 039 80 e barras 613/004/052/01',
  '{"documento": 61300506580, "valor": 12345678901234}', '{"a":{"b":[{"cpf_novo":"61300607858"}]}}', 'cnpj 12.345.678/0001-95 data 09/11/2026 hora 22:18:27 valor 123.456.789,01');
-- UUID e hash com 11 dígitos seguidos (corrompidos pela regra de 20261111; 20261112 corrige)
INSERT INTO public.audit_logs (id, action, entity_type, entity_id, description, new_data) VALUES
 ('ad000000-0000-0000-0000-000000000006', 'UPDATE', 'funcionarios', 'ad000000-0000-4000-8000-12345678901a',
  'Atualizou registro em funcionarios (id ad000000-0000-4000-8000-12345678901a)', '{"id":"ad000000-0000-4000-8000-a12345678901","hash":"0123456789012f","cpf_colado":"CPF61300101334"}');
-- concessão por coluna criada "por engano": a migration já rodou; o teste confere que a guarda a detectaria
CREATE TEMP TABLE _antes ON COMMIT DROP AS SELECT md5(string_agg(to_jsonb(a)::text, '|' ORDER BY id)) m, count(*) n FROM public.audit_logs a;
GRANT SELECT ON _antes TO PUBLIC;

DO $$
DECLARE r text; u uuid; j jsonb; tudo text;
BEGIN
  -- 1. ninguém lê a tabela diretamente
  FOREACH u IN ARRAY ARRAY['ce000000-0000-0000-0000-000000000001', 'ce000000-0000-0000-0000-000000000002', 'ce000000-0000-0000-0000-000000000003',
                           'ce000000-0000-0000-0000-000000000004', 'ce000000-0000-0000-0000-000000000005']::uuid[] LOOP
    ASSERT pg_temp.como(u, 'SELECT * FROM public.audit_logs') LIKE '42501%', 'select * em audit_logs: ' || u;
    ASSERT pg_temp.como(u, 'SELECT new_data FROM public.audit_logs WHERE entity_type = ''funcionarios''') LIKE '42501%', 'select coluna: ' || u;
    ASSERT pg_temp.como(u, $q$SELECT count(*) FROM public.audit_logs WHERE new_data->>'cpf' = '61300101334'$q$) LIKE '42501%', 'filtro por CPF: ' || u;
  END LOOP;
  -- 2. só o Gestor ativo usa a função
  FOREACH u IN ARRAY ARRAY['ce000000-0000-0000-0000-000000000002', 'ce000000-0000-0000-0000-000000000003', 'ce000000-0000-0000-0000-000000000004',
                           'ce000000-0000-0000-0000-000000000005', 'ce000000-0000-0000-0000-000000000006']::uuid[] LOOP
    r := pg_temp.como(u, 'SELECT * FROM public.auditoria_listar(10)');
    ASSERT r LIKE 'P0001 PERMISSAO%', 'outro perfil ou Gestor inativo leu: ' || u || ' ' || r;
  END LOOP;
  r := pg_temp.como(NULL, 'SELECT * FROM public.auditoria_listar(10)');
  ASSERT r LIKE 'P0001 PERMISSAO%', 'sem sessão: ' || r;
  ASSERT pg_temp.como('ce000000-0000-0000-0000-000000000001', 'SELECT * FROM public.auditoria_listar(3)') = 'ok:3', 'limite';
  ASSERT pg_temp.como('ce000000-0000-0000-0000-000000000001', 'SELECT public.audit_mascarar(''{}''::jsonb)') LIKE '42501%', 'helper exposto';

  -- 3. máscara: nada de CPF completo; o resto intacto
  SELECT string_agg(x::text, '|') INTO tudo FROM pg_temp.lista('ce000000-0000-0000-0000-000000000001') x;
  ASSERT tudo !~ '(?<![0-9A-Za-z])[0-9]{3}[ ./-]?[0-9]{3}[ ./-]?[0-9]{3}[ ./-]?[0-9]{2}(?![0-9A-Za-z])', 'CPF completo na leitura do Gestor';
  SELECT x INTO j FROM pg_temp.lista('ce000000-0000-0000-0000-000000000001') x WHERE x->>'id' = 'ad000000-0000-0000-0000-000000000001';
  ASSERT j->'old_data'->>'cpf' = '***.001.013-**' AND j->'new_data'->>'cpf' = '***.001.013-**', 'chave cpf: ' || j::text;
  ASSERT j->'new_data'->'extra'->>'cpf' = '***.002.026-**', 'cpf aninhado';
  ASSERT j->'new_data'->'extra'->'lista'->>0 = 'texto ***.003.039-** livre', 'cpf em texto dentro do JSON';
  ASSERT j->>'observacao' = 'Conferido pelo CPF ***.004.052-** no RH', 'cpf na observação: ' || (j->>'observacao');
  ASSERT j->'old_data'->>'id' = 'ca000000-0000-0000-0000-000000000001' AND j->'old_data'->>'nome' = 'ANTIGO' AND (j->'old_data'->>'banco_horas')::int = 0, 'demais campos';
  SELECT x INTO j FROM pg_temp.lista('ce000000-0000-0000-0000-000000000001') x WHERE x->>'id' = 'ad000000-0000-0000-0000-000000000002';
  ASSERT j->'new_data'->'cpf' = 'null'::jsonb, 'cpf nulo';
  ASSERT j->'new_data'->>'cnpj' = '12.345.678/0001-95' AND j->'new_data'->>'outro' = '12345678000195', 'CNPJ não é CPF';
  ASSERT j->'new_data'->>'telefone_ddd' = '(11) 98765-4321', 'telefone formatado intacto';
  SELECT x INTO j FROM pg_temp.lista('ce000000-0000-0000-0000-000000000001') x WHERE x->>'id' = 'ad000000-0000-0000-0000-000000000003';
  ASSERT j->'old_data'->>'cpf' = '***.001.013-**' AND j->>'observacao' = 'Documento conferido', 'já mascarado passa direto';
  SELECT x INTO j FROM pg_temp.lista('ce000000-0000-0000-0000-000000000001') x WHERE x->>'id' = 'ad000000-0000-0000-0000-000000000004';
  ASSERT j->'new_data'->>'cpf' = '***.005.065-**', 'cpf numérico: ' || j::text;
  ASSERT (j->'new_data'->>'numero_grande')::bigint = 123456789012 AND j->'new_data'->>'data' = '2026-11-09T22:18:27.419079+00', 'número e data intactos';

  SELECT x INTO j FROM pg_temp.lista('ce000000-0000-0000-0000-000000000001') x WHERE x->>'id' = 'ad000000-0000-0000-0000-000000000005';
  ASSERT j->>'username' = '***.001.013-**' AND j->>'entity_id' = '***.002.026-**', 'usuário e registro: ' || j::text;
  ASSERT j->>'description' = 'com espacos ***.003.039-** e barras ***.004.052-**', 'separadores: ' || (j->>'description');
  ASSERT j->'old_data'->>'documento' = '***.005.065-**' AND (j->'old_data'->>'valor')::bigint = 12345678901234, 'número de 11 dígitos em outra chave: ' || j::text;
  ASSERT j->'new_data'->'a'->'b'->0->>'cpf_novo' = '***.006.078-**', 'chave diferente de cpf';
  ASSERT j->>'observacao' = 'cnpj 12.345.678/0001-95 data 09/11/2026 hora 22:18:27 valor 123.456.789,01', 'falso positivo: ' || (j->>'observacao');

  SELECT x INTO j FROM pg_temp.lista('ce000000-0000-0000-0000-000000000001') x WHERE x->>'id' = 'ad000000-0000-0000-0000-000000000006';
  ASSERT j->>'entity_id' = 'ad000000-0000-4000-8000-12345678901a' AND j->>'description' = 'Atualizou registro em funcionarios (id ad000000-0000-4000-8000-12345678901a)', 'UUID corrompido: ' || j::text;
  ASSERT j->'new_data'->>'id' = 'ad000000-0000-4000-8000-a12345678901' AND j->'new_data'->>'hash' = '0123456789012f', 'UUID/hash no JSON corrompido: ' || j::text;
  ASSERT j->'new_data'->>'cpf_colado' = 'CPF ***.001.013-**', 'CPF logo após a palavra CPF: ' || (j->'new_data'->>'cpf_colado');

  -- 4. registros intactos: a leitura não altera nada; o CPF completo segue gravado
  ASSERT (SELECT md5(string_agg(to_jsonb(a)::text, '|' ORDER BY id)) FROM public.audit_logs a) = (SELECT m FROM _antes), 'audit_logs alterado pela leitura';
  ASSERT (SELECT new_data->'extra'->>'cpf' FROM public.audit_logs WHERE id = 'ad000000-0000-0000-0000-000000000001') = '61300202602', 'registro original mudou';

  -- 5. a guarda vê concessão por coluna (has_table_privilege não vê)
  GRANT SELECT (new_data) ON public.audit_logs TO authenticated;
  ASSERT has_any_column_privilege('authenticated', 'public.audit_logs', 'SELECT') AND NOT has_table_privilege('authenticated', 'public.audit_logs', 'SELECT'), 'premissa da guarda';
  REVOKE SELECT (new_data) ON public.audit_logs FROM authenticated;
  ASSERT NOT has_any_column_privilege('authenticated', 'public.audit_logs', 'SELECT') AND NOT has_any_column_privilege('anon', 'public.audit_logs', 'SELECT'), 'leitura por coluna restou';

  -- 6. escrita continua bloqueada
  ASSERT pg_temp.como('ce000000-0000-0000-0000-000000000001', $q$UPDATE public.audit_logs SET observacao = 'x'$q$) LIKE '42501%', 'update';
  ASSERT pg_temp.como('ce000000-0000-0000-0000-000000000001', 'DELETE FROM public.audit_logs') LIKE '42501%', 'delete';
END $$;

ROLLBACK;
