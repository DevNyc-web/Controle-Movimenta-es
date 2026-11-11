-- TESTE LOCAL — NÃO RODAR EM PRODUÇÃO. Execução: bash supabase/tests/rodar_local.sh (Postgres descartável; dados fictícios).
-- 20261113120000 (segurança residual): audit_logs e ft_historico sem escrita por anon/authenticated, e os registros legítimos
-- (gatilhos, RPCs de cancelamento e chave de serviço) continuam gravados com o autor certo.
-- Vale nas duas ordens: depois de todas as migrations (repositório) e só sobre o hotfix (produção). Tudo em transação com ROLLBACK.

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

CREATE FUNCTION pg_temp.como_role(p_role text, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text; n bigint;
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', p_role, true);
  BEGIN
    EXECUTE p_sql;
    GET DIAGNOSTICS n = ROW_COUNT;
    r := 'ok:' || n;
  EXCEPTION WHEN OTHERS THEN
    r := SQLSTATE || ' ' || SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  RETURN r;
END $$;

CREATE FUNCTION pg_temp.hoje() RETURNS date LANGUAGE sql STABLE AS $$ SELECT (now() AT TIME ZONE 'America/Sao_Paulo')::date $$;
CREATE FUNCTION pg_temp.f(i int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT ('b7000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.ins_ft(u uuid, i int) RETURNS text LANGUAGE sql AS $$
  SELECT format('INSERT INTO public.ft (funcionario_id, data_ft, motivo, lancado_por, posto_falta) VALUES (%L, %L, ''Falta'', %L, ''BASE'')',
                pg_temp.f(i), pg_temp.hoje(), u)
$$;

-- Contas: Gestor, Supervisor e Admin ativos; Gestor desativado; conta sem perfil; JWT sem usuário (fantasma)
INSERT INTO auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
SELECT '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.n || '@teste.local',
       jsonb_build_object('username', u.n, 'nome', u.n), now(), now()
FROM (VALUES
 ('a7000000-0000-0000-0000-000000000001'::uuid, 'rg'),
 ('a7000000-0000-0000-0000-000000000002'::uuid, 'rs'),
 ('a7000000-0000-0000-0000-000000000003'::uuid, 'rad'),
 ('a7000000-0000-0000-0000-000000000004'::uuid, 'rgi'),
 ('a7000000-0000-0000-0000-000000000005'::uuid, 'rsp')) u(id, n);
-- o que createUser faz pelo servidor (independe do fixture local)
UPDATE public.profiles SET ativo = (username <> 'rgi') WHERE username IN ('rg', 'rs', 'rad', 'rgi');
DELETE FROM public.user_roles WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE 'r%@teste.local');
INSERT INTO public.user_roles (user_id, role) VALUES
 ('a7000000-0000-0000-0000-000000000001', 'gestor'), ('a7000000-0000-0000-0000-000000000002', 'supervisor'),
 ('a7000000-0000-0000-0000-000000000003', 'admin'), ('a7000000-0000-0000-0000-000000000004', 'gestor');
DELETE FROM public.profiles WHERE username = 'rsp';

INSERT INTO public.funcionarios (id, nome, re, cargo, turno)
SELECT pg_temp.f(i), 'RES ' || i, 'R-' || i, 'Vigilante', 'Integral' FROM generate_series(1, 4) i;

CREATE TEMP TABLE _r ON COMMIT DROP AS SELECT
  'a7000000-0000-0000-0000-000000000001'::uuid g, 'a7000000-0000-0000-0000-000000000002'::uuid s,
  'a7000000-0000-0000-0000-000000000003'::uuid ad, 'a7000000-0000-0000-0000-000000000004'::uuid gi,
  'a7000000-0000-0000-0000-000000000005'::uuid sp, 'a7000000-0000-0000-0000-0000000000ff'::uuid fantasma,
  NULL::uuid ft1, NULL::uuid ft2, NULL::uuid ft3;
GRANT SELECT ON _r TO PUBLIC;

-- ---------------------------------------------------------------- L: fluxos legítimos gravam com o autor certo
DO $$
DECLARE u record; r text; v_ft uuid; v_sol uuid;
BEGIN
  SELECT * INTO u FROM _r;

  -- L1 Supervisor lança FT: histórico CRIADA e auditoria INSERT, ambos com o Supervisor
  r := pg_temp.como(u.s, pg_temp.ins_ft(u.s, 1));
  ASSERT r = 'ok:1', 'L1 lançamento: ' || r;
  SELECT id INTO v_ft FROM public.ft WHERE funcionario_id = pg_temp.f(1);
  UPDATE _r SET ft1 = v_ft;
  ASSERT (SELECT count(*) FROM public.ft_historico WHERE ft_id = v_ft AND acao = 'CRIADA' AND alterado_por = u.s) = 1, 'L1 histórico CRIADA';
  ASSERT (SELECT count(*) FROM public.audit_logs WHERE entity_type = 'ft' AND entity_id = v_ft::text AND action = 'INSERT' AND user_id = u.s) = 1, 'L1 auditoria INSERT';

  -- L2 Gestor aprova: STATUS_ALTERADO e auditoria UPDATE com o Gestor
  r := pg_temp.como(u.g, format('UPDATE public.ft SET status = ''APROVADA'', aprovado_por = %L WHERE id = %L', u.g, v_ft));
  ASSERT r = 'ok:1', 'L2 aprovação: ' || r;
  ASSERT (SELECT count(*) FROM public.ft_historico WHERE ft_id = v_ft AND acao = 'STATUS_ALTERADO' AND status_anterior = 'PENDENTE'
            AND status_novo = 'APROVADA' AND alterado_por = u.g) = 1, 'L2 histórico';
  ASSERT (SELECT count(*) FROM public.audit_logs WHERE entity_type = 'ft' AND entity_id = v_ft::text AND action = 'UPDATE' AND user_id = u.g) >= 1, 'L2 auditoria';

  -- L3 Supervisor pede cancelamento; Admin aprova pela RPC
  r := pg_temp.como(u.s, pg_temp.ins_ft(u.s, 2));
  ASSERT r = 'ok:1', 'L3 lançamento: ' || r;
  SELECT id INTO v_ft FROM public.ft WHERE funcionario_id = pg_temp.f(2);
  UPDATE _r SET ft2 = v_ft;
  r := pg_temp.como(u.s, format('INSERT INTO public.ft_cancelamento_solicitacoes (ft_id, solicitado_por, motivo) VALUES (%L, %L, ''teste residual'')', v_ft, u.s));
  ASSERT r = 'ok:1', 'L3 solicitação: ' || r;
  ASSERT (SELECT count(*) FROM public.ft_historico WHERE ft_id = v_ft AND status_novo = 'CANCELAMENTO_SOLICITADO' AND alterado_por = u.s) = 1, 'L3 histórico solicitação';
  ASSERT (SELECT count(*) FROM public.audit_logs WHERE entity_type = 'ft_cancelamento_solicitacoes' AND action = 'INSERT' AND user_id = u.s) = 1, 'L3 auditoria solicitação';
  SELECT id INTO v_sol FROM public.ft_cancelamento_solicitacoes WHERE ft_id = v_ft;
  r := pg_temp.como(u.ad, format('SELECT public.aprovar_cancelamento(%L, ''ok'')', v_sol));
  ASSERT r LIKE 'ok:%', 'L3 aprovação pelo Admin: ' || r;
  ASSERT (SELECT count(*) FROM public.ft_historico WHERE ft_id = v_ft AND status_novo = 'CANCELADA' AND alterado_por = u.ad) = 1, 'L3 histórico CANCELADA';
  ASSERT (SELECT count(*) FROM public.audit_logs WHERE entity_type = 'ft' AND entity_id = v_ft::text AND action = 'UPDATE' AND user_id = u.ad) >= 1, 'L3 auditoria Admin';

  -- L4 Gestor edita funcionário: auditoria com o Gestor
  r := pg_temp.como(u.g, format('UPDATE public.funcionarios SET nome = nome || '' X'' WHERE id = %L', pg_temp.f(3)));
  ASSERT r = 'ok:1', 'L4 edição: ' || r;
  ASSERT (SELECT count(*) FROM public.audit_logs WHERE entity_type = 'funcionarios' AND entity_id = pg_temp.f(3)::text AND action = 'UPDATE' AND user_id = u.g) = 1, 'L4 auditoria';

  -- L5 Servidor (chave de serviço, gestão de usuários): insere auditoria direta e o gatilho registra a edição de perfil
  r := pg_temp.como_role('service_role', format('INSERT INTO public.audit_logs (user_id, username, role, action, entity_type, entity_id, description)
         VALUES (%L, ''rad'', ''admin'', ''USUARIO_EDITADO'', ''profiles'', %L, ''teste residual'')', u.ad, u.g));
  ASSERT r = 'ok:1', 'L5 inserção pelo servidor: ' || r;
  r := pg_temp.como_role('service_role', format('UPDATE public.profiles SET nome = ''rg2'' WHERE id = %L', u.g));
  ASSERT r = 'ok:1', 'L5 edição de perfil pelo servidor: ' || r;
  ASSERT (SELECT count(*) FROM public.audit_logs WHERE entity_type = 'profiles' AND entity_id = u.g::text AND action = 'UPDATE' AND new_data->>'nome' = 'rg2') = 1, 'L5 auditoria do perfil';

  -- L6 Gestor corrige valores de FT pendente: o histórico VALORES_CORRIGIDOS continua sendo gravado com o Gestor.
  --    Produção atual (origin/main): o app grava o histórico num segundo comando, pela API. Depois de 20261105120100: gatilho.
  r := pg_temp.como(u.s, pg_temp.ins_ft(u.s, 4));
  ASSERT r = 'ok:1', 'L6 lançamento: ' || r;
  SELECT id INTO v_ft FROM public.ft WHERE funcionario_id = pg_temp.f(4);
  UPDATE _r SET ft3 = v_ft;
  r := pg_temp.como(u.g, format('UPDATE public.ft SET valor_pago = valor_pago + 10 WHERE id = %L AND status = ''PENDENTE''', v_ft));
  ASSERT r = 'ok:1', 'L6 correção: ' || r;
  IF has_table_privilege('authenticated', 'public.ft_historico', 'INSERT') THEN
    r := pg_temp.como(u.g, format('INSERT INTO public.ft_historico (ft_id, acao, alterado_por, observacao) VALUES (%L, ''VALORES_CORRIGIDOS'', %L, ''Valor: R$ 1 → R$ 11'')', v_ft, u.g));
    ASSERT r = 'ok:1', 'L6 histórico pelo app: ' || r;
  END IF;
  ASSERT (SELECT count(*) FROM public.ft_historico WHERE ft_id = v_ft AND acao = 'VALORES_CORRIGIDOS' AND alterado_por = u.g) >= 1, 'L6 histórico VALORES_CORRIGIDOS';
  ASSERT (SELECT count(*) FROM public.audit_logs WHERE entity_type = 'ft' AND entity_id = v_ft::text AND action = 'UPDATE' AND user_id = u.g) = 1, 'L6 auditoria';
END $$;

-- ---------------------------------------------------------------- D: tentativas indevidas, nada muda
CREATE TEMP TABLE _antes ON COMMIT DROP AS
SELECT (SELECT count(*) FROM public.audit_logs) a, (SELECT md5(string_agg(x::text, '|' ORDER BY x.id)) FROM public.audit_logs x) ha,
       (SELECT count(*) FROM public.ft_historico) h, (SELECT md5(string_agg(x::text, '|' ORDER BY x.id)) FROM public.ft_historico x) hh;

DO $$
DECLARE u record; r text; ator record; cmd text;
  cmds text[];
BEGIN
  SELECT * INTO u FROM _r;
  cmds := ARRAY[
    format('INSERT INTO public.audit_logs (user_id, username, role, action, entity_type, entity_id, created_at) VALUES (%L, ''rg'', ''gestor'', ''UPDATE'', ''ft'', %L, ''2020-01-01'')', u.g, u.ft1),
    format('INSERT INTO public.ft_historico (ft_id, acao, status_anterior, status_novo, alterado_por, created_at) VALUES (%L, ''STATUS_ALTERADO'', ''PENDENTE'', ''APROVADA'', %L, ''2020-01-01'')', u.ft1, u.g),
    'UPDATE public.audit_logs SET description = ''x''',
    'UPDATE public.ft_historico SET observacao = ''x''',
    'DELETE FROM public.audit_logs',
    'DELETE FROM public.ft_historico',
    'TRUNCATE public.audit_logs',
    'TRUNCATE public.ft_historico'];
  FOR ator IN SELECT * FROM (VALUES ('gestor', u.g), ('supervisor', u.s), ('admin', u.ad), ('gestor desativado', u.gi),
                                    ('conta sem perfil', u.sp), ('JWT sem usuário', u.fantasma)) a(nome, id) LOOP
    FOREACH cmd IN ARRAY cmds LOOP
      r := pg_temp.como(ator.id, cmd);
      ASSERT r LIKE '42501 %', format('D authenticated (%s) não pode: %s -> %s', ator.nome, left(cmd, 60), r);
    END LOOP;
  END LOOP;
  FOREACH cmd IN ARRAY cmds LOOP
    r := pg_temp.como_role('anon', cmd);
    ASSERT r LIKE '42501 %', format('D anon não pode: %s -> %s', left(cmd, 60), r);
  END LOOP;

  -- D2 imitações do registro VALORES_CORRIGIDOS: cada uma quebra UMA condição (FT pendente ft3, salvo onde indicado)
  FOR ator IN SELECT * FROM (VALUES
    ('outra ação',            u.g,  format('INSERT INTO public.ft_historico (ft_id, acao, alterado_por) VALUES (%L, ''STATUS_ALTERADO'', %L)', u.ft3, u.g)),
    ('autor de outra pessoa', u.g,  format('INSERT INTO public.ft_historico (ft_id, acao, alterado_por) VALUES (%L, ''VALORES_CORRIGIDOS'', %L)', u.ft3, u.s)),
    ('autor vazio',           u.g,  format('INSERT INTO public.ft_historico (ft_id, acao) VALUES (%L, ''VALORES_CORRIGIDOS'')', u.ft3)),
    ('com status',            u.g,  format('INSERT INTO public.ft_historico (ft_id, acao, alterado_por, status_novo) VALUES (%L, ''VALORES_CORRIGIDOS'', %L, ''APROVADA'')', u.ft3, u.g)),
    ('status anterior',       u.g,  format('INSERT INTO public.ft_historico (ft_id, acao, alterado_por, status_anterior) VALUES (%L, ''VALORES_CORRIGIDOS'', %L, ''PENDENTE'')', u.ft3, u.g)),
    ('data retroativa',       u.g,  format('INSERT INTO public.ft_historico (ft_id, acao, alterado_por, created_at) VALUES (%L, ''VALORES_CORRIGIDOS'', %L, now() - interval ''1 day'')', u.ft3, u.g)),
    ('data futura',           u.g,  format('INSERT INTO public.ft_historico (ft_id, acao, alterado_por, created_at) VALUES (%L, ''VALORES_CORRIGIDOS'', %L, now() + interval ''1 day'')', u.ft3, u.g)),
    ('FT não pendente',       u.g,  format('INSERT INTO public.ft_historico (ft_id, acao, alterado_por) VALUES (%L, ''VALORES_CORRIGIDOS'', %L)', u.ft1, u.g)),
    ('Supervisor',            u.s,  format('INSERT INTO public.ft_historico (ft_id, acao, alterado_por) VALUES (%L, ''VALORES_CORRIGIDOS'', %L)', u.ft3, u.s)),
    ('Admin',                 u.ad, format('INSERT INTO public.ft_historico (ft_id, acao, alterado_por) VALUES (%L, ''VALORES_CORRIGIDOS'', %L)', u.ft3, u.ad)),
    ('Gestor desativado',     u.gi, format('INSERT INTO public.ft_historico (ft_id, acao, alterado_por) VALUES (%L, ''VALORES_CORRIGIDOS'', %L)', u.ft3, u.gi)),
    ('conta sem perfil',      u.sp, format('INSERT INTO public.ft_historico (ft_id, acao, alterado_por) VALUES (%L, ''VALORES_CORRIGIDOS'', %L)', u.ft3, u.sp))
  ) a(nome, id, sql) LOOP
    r := pg_temp.como(ator.id, ator.sql);
    ASSERT r LIKE '42501 %', format('D2 histórico falso (%s) -> %s', ator.nome, r);
  END LOOP;
  r := pg_temp.como_role('anon', format('INSERT INTO public.ft_historico (ft_id, acao) VALUES (%L, ''VALORES_CORRIGIDOS'')', u.ft3));
  ASSERT r LIKE '42501 %', 'D2 anon: ' || r;

  -- D3 a inserção não serve de oráculo: FT existente ou inexistente dá o mesmo erro (a política é avaliada antes da FK)
  ASSERT pg_temp.como(u.g, 'INSERT INTO public.ft_historico (ft_id, acao, alterado_por) VALUES (''c7000000-0000-0000-0000-000000000000'', ''VALORES_CORRIGIDOS'', '
                           || quote_literal(u.g) || ')') LIKE '42501 %', 'D3 Gestor, FT inexistente: 42501 (não 23503)';
  ASSERT pg_temp.como(u.s, format('INSERT INTO public.ft_historico (ft_id, acao, alterado_por) VALUES (%L, ''VALORES_CORRIGIDOS'', %L)', u.ft3, u.s))
       = pg_temp.como(u.s, format('INSERT INTO public.ft_historico (ft_id, acao, alterado_por) VALUES (%L, ''VALORES_CORRIGIDOS'', %L)', 'c7000000-0000-0000-0000-000000000000', u.s)),
         'D3 Supervisor: mesma resposta para FT existente e inexistente';
  ASSERT (SELECT a = (SELECT count(*) FROM public.audit_logs) AND ha = (SELECT md5(string_agg(x::text, '|' ORDER BY x.id)) FROM public.audit_logs x)
            AND h = (SELECT count(*) FROM public.ft_historico) AND hh = (SELECT md5(string_agg(x::text, '|' ORDER BY x.id)) FROM public.ft_historico x)
          FROM _antes), 'D: tentativas indevidas não mudaram nenhum registro';
END $$;

-- ---------------------------------------------------------------- R: leituras sem mudança
DO $$
DECLARE u record; r text;
BEGIN
  SELECT * INTO u FROM _r;
  IF has_table_privilege('authenticated', 'public.audit_logs', 'SELECT') THEN  -- produção atual: Gestor lê a tabela
    r := pg_temp.como(u.g, 'SELECT 1 FROM public.audit_logs');
    ASSERT r ~ '^ok:[1-9]', 'R1 Gestor lê auditoria: ' || r;
    ASSERT pg_temp.como(u.s, 'SELECT 1 FROM public.audit_logs') = 'ok:0', 'R1 Supervisor não lê auditoria';
    ASSERT pg_temp.como(u.gi, 'SELECT 1 FROM public.audit_logs') = 'ok:0', 'R1 Gestor desativado não lê auditoria';
  ELSE  -- depois de 20261111: leitura só por auditoria_listar
    r := pg_temp.como(u.g, 'SELECT * FROM public.auditoria_listar(100)');
    ASSERT r ~ '^ok:[1-9]', 'R1 Gestor lê auditoria (função): ' || r;
    ASSERT pg_temp.como(u.s, 'SELECT * FROM public.auditoria_listar(100)') !~ '^ok:[1-9]', 'R1 Supervisor não lê auditoria';
  END IF;
  r := pg_temp.como(u.s, format('SELECT 1 FROM public.ft_historico WHERE ft_id = %L', u.ft1));
  ASSERT r ~ '^ok:[1-9]', 'R2 Supervisor lê histórico da FT da janela: ' || r;
  ASSERT pg_temp.como(u.gi, 'SELECT 1 FROM public.ft_historico') = 'ok:0', 'R2 Gestor desativado não lê histórico';
  ASSERT pg_temp.como(u.sp, 'SELECT 1 FROM public.ft_historico') = 'ok:0', 'R2 conta sem perfil não lê histórico';
END $$;

-- ---------------------------------------------------------------- C: catálogo
DO $$
DECLARE r text; f text;
BEGIN
  FOREACH r IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    FOREACH f IN ARRAY ARRAY['public.log_audit(text,text,text,text,jsonb,jsonb,text)', 'public.tg_audit_row()', 'public.tg_ft_log_history()'] LOOP
      ASSERT NOT has_function_privilege(r, f, 'EXECUTE'), format('C1 %s não executa %s', r, f);
    END LOOP;
  END LOOP;
  ASSERT (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal AND tgenabled = 'O' AND tgname IN
          ('audit_ft', 'audit_funcionarios', 'audit_profiles', 'audit_user_roles', 'audit_ft_cancelamento_solicitacoes', 'ft_log_history')) = 6,
         'C2 gatilhos de auditoria e histórico ativos';
  ASSERT NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND cmd IN ('INSERT', 'ALL') AND coalesce(with_check, qual, 'true') <> 'false'
                      AND (tablename = 'audit_logs' OR (tablename = 'ft_historico' AND coalesce(with_check, qual, 'true') !~ 'VALORES_CORRIGIDOS'))),
         'C3 nenhuma política de inserção aberta';
  ASSERT NOT has_table_privilege('authenticated', 'public.audit_logs', 'INSERT'), 'C5 authenticated sem INSERT em audit_logs';
  ASSERT has_table_privilege('service_role', 'public.audit_logs', 'INSERT'), 'C4 service_role mantém INSERT em audit_logs';
END $$;

ROLLBACK;
