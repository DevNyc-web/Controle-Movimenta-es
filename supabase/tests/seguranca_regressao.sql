-- TESTE LOCAL — NÃO RODAR EM PRODUÇÃO. Execução: bash supabase/tests/rodar_local.sh (Postgres descartável; dados fictícios).
-- Uma regressão por achado da revisão adversarial da Fase 1A (C1, A1–A7, M1–M4, FT em período inativo).
-- Tudo em transação com ROLLBACK final. pg_temp.como() executa como role authenticated com JWT simulado, sob RLS real.

BEGIN;

CREATE FUNCTION pg_temp.como(p_uid uuid, p_sql text, p_meta jsonb DEFAULT '{}') RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text; n bigint;
BEGIN
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'user_metadata', p_meta)::text, true);
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

CREATE FUNCTION pg_temp.ins(u uuid, f uuid, d date, falt uuid DEFAULT NULL, j text DEFAULT NULL, st text DEFAULT 'PENDENTE') RETURNS text LANGUAGE sql AS $$
  SELECT format('INSERT INTO public.ft (funcionario_id, funcionario_faltante_id, data_ft, motivo, lancado_por, posto_falta, retroativa_justificativa, status) VALUES (%L,%L,%L,''Falta'',%L,''BASE'',%L,%L)', f, falt, d, u, j, st)
$$;
CREATE FUNCTION pg_temp.hoje() RETURNS date LANGUAGE sql STABLE AS $$ SELECT (now() AT TIME ZONE 'America/Sao_Paulo')::date $$;
CREATE FUNCTION pg_temp.f(i int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT ('b1000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.inativar(i int) RETURNS void LANGUAGE sql AS $$ UPDATE public.funcionarios SET status = 'inativo' WHERE id = pg_temp.f(i) $$;

INSERT INTO auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
SELECT '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.n || '@teste.local',
       jsonb_build_object('username', u.n, 'nome', u.n, 'role', u.r), now(), now()
FROM (VALUES
 ('a1000000-0000-0000-0000-000000000001'::uuid, 'sg',  'gestor'),
 ('a1000000-0000-0000-0000-000000000002'::uuid, 'ss',  'supervisor'),
 ('a1000000-0000-0000-0000-000000000003'::uuid, 'sap', 'apontamento'),
 ('a1000000-0000-0000-0000-000000000004'::uuid, 'sad', 'admin'),
 ('a1000000-0000-0000-0000-000000000005'::uuid, 'sgd', 'gestor'),
 ('a1000000-0000-0000-0000-000000000006'::uuid, 'ssd', 'supervisor')) u(id, n, r);
UPDATE public.profiles SET ativo = false WHERE username IN ('sgd', 'ssd');

INSERT INTO public.funcionarios (id, nome, re, cargo, turno)
SELECT pg_temp.f(i), 'SEG ' || i, 'S-' || i, 'Vigilante', 'Integral' FROM generate_series(1, 40) i;

CREATE TEMP TABLE _u ON COMMIT DROP AS SELECT
  'a1000000-0000-0000-0000-000000000001'::uuid g, 'a1000000-0000-0000-0000-000000000002'::uuid s,
  'a1000000-0000-0000-0000-000000000003'::uuid ap, 'a1000000-0000-0000-0000-000000000004'::uuid ad,
  'a1000000-0000-0000-0000-000000000005'::uuid gd, 'a1000000-0000-0000-0000-000000000006'::uuid sd;
GRANT SELECT ON _u TO PUBLIC;

-- ---------------------------------------------------------------- C1 cadastro público
ALTER TABLE auth.users DISABLE TRIGGER zz_fixture_conta_admin;
DO $$
DECLARE r text; novo uuid := 'a1000000-0000-0000-0000-000000000099'; u record;
BEGIN
  SELECT * INTO u FROM _u;
  -- o que o serviço de login grava em auth.users no signUp, com options.data
  INSERT INTO auth.users (instance_id, id, aud, role, email, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000', novo, 'authenticated', 'authenticated', 'x@externo.test',
          '{"role":"gestor","username":"invasor"}', '{"role":"gestor"}', now(), now());
  ASSERT NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = novo), 'C1: metadata não concede perfil';
  ASSERT (SELECT NOT ativo FROM public.profiles WHERE id = novo), 'C1: conta nasce desativada';
  ASSERT NOT public.has_role(novo, 'gestor'), 'C1: has_role';

  ASSERT pg_temp.como(novo, 'SELECT id FROM public.funcionarios') = 'ok:0', 'C1: não lê funcionários';
  ASSERT pg_temp.como(u.g, pg_temp.ins(u.g, pg_temp.f(1), DATE '2026-02-01')) = 'ok:1', 'pressuposto: FT existe';
  ASSERT pg_temp.como(novo, 'SELECT id FROM public.ft') = 'ok:0', 'C1: não lê FTs';
  r := pg_temp.como(novo, pg_temp.ins(novo, pg_temp.f(2), DATE '2026-02-02'));
  ASSERT r LIKE '42501%', 'C1: não lança FT: ' || r;
  ASSERT pg_temp.como(novo, $q$UPDATE public.funcionarios SET status = 'inativo'$q$) = 'ok:0', 'C1: não inativa';

  -- fluxo legítimo de createUser: service role ativa e concede
  ASSERT pg_temp.como_role('service_role', format($q$INSERT INTO public.profiles (id, nome, email, username, ativo) VALUES (%L, 'n', 'x@externo.test', 'invasor', true) ON CONFLICT (id) DO UPDATE SET ativo = true$q$, novo)) = 'ok:1', 'createUser: profile';
  ASSERT pg_temp.como_role('service_role', format($q$INSERT INTO public.user_roles (user_id, role) VALUES (%L, 'apontamento') ON CONFLICT DO NOTHING$q$, novo)) = 'ok:1', 'createUser: perfil';
  ASSERT public.has_role(novo, 'apontamento'), 'createUser: perfil vale';
  ASSERT NOT public.has_role(novo, 'gestor'), 'createUser: só o perfil concedido';
END $$;
ALTER TABLE auth.users ENABLE TRIGGER zz_fixture_conta_admin;

-- ---------------------------------------------------------------- A1 autoconcessão de perfil
DO $$
DECLARE r text; u record;
BEGIN
  SELECT * INTO u FROM _u;
  r := pg_temp.como(u.ad, format($q$INSERT INTO public.user_roles (user_id, role) VALUES (%L, 'gestor')$q$, u.ad));
  ASSERT r LIKE '42501%', 'A1: admin não se concede gestor: ' || r;
  r := pg_temp.como(u.ad, format($q$UPDATE public.user_roles SET role = 'gestor' WHERE user_id = %L$q$, u.ad));
  ASSERT r LIKE '42501%', 'A1: admin não troca o próprio perfil: ' || r;
  r := pg_temp.como(u.ad, format('DELETE FROM public.user_roles WHERE user_id = %L', u.g));
  ASSERT r LIKE '42501%', 'A1: admin não remove perfis: ' || r;
  r := pg_temp.como(u.g, format($q$INSERT INTO public.user_roles (user_id, role) VALUES (%L, 'gestor')$q$, u.s));
  ASSERT r LIKE '42501%', 'A1: nem gestor escreve direto (só pelo servidor): ' || r;
  r := pg_temp.como(u.ad, pg_temp.ins(u.ad, pg_temp.f(3), DATE '2026-02-03'));
  ASSERT r LIKE '42501%', 'A1: admin segue sem lançar FT: ' || r;
  ASSERT pg_temp.como_role('service_role', format($q$INSERT INTO public.user_roles (user_id, role) VALUES (%L, 'rh') ON CONFLICT DO NOTHING$q$, u.ad)) = 'ok:1', 'A1: servidor mantém o fluxo legítimo';
END $$;

-- ---------------------------------------------------------------- A2 conta desativada
DO $$
DECLARE r text; u record;
BEGIN
  SELECT * INTO u FROM _u;
  r := pg_temp.como(u.gd, format('UPDATE public.profiles SET ativo = true WHERE id = %L', u.gd));
  ASSERT r LIKE '42501%', 'A2: não se reativa: ' || r;
  r := pg_temp.como(u.s, format($q$UPDATE public.profiles SET nome = 'outro', email = 'x@y.z' WHERE id = %L$q$, u.s));
  ASSERT r LIKE '42501%', 'A2: não altera o próprio profile: ' || r;
  ASSERT NOT public.has_role(u.gd, 'gestor'), 'A2: perfil de conta desativada não vale';
  ASSERT pg_temp.como(u.gd, 'SELECT id FROM public.ft') = 'ok:0', 'A2: gestor desativado não lê FT';
  ASSERT pg_temp.como(u.sd, 'SELECT id FROM public.ft') = 'ok:0', 'A2: supervisor desativado não vira irrestrito';
  ASSERT pg_temp.como(u.gd, 'SELECT id FROM public.funcionarios') = 'ok:0', 'A2: não lê funcionários';
  ASSERT pg_temp.como(u.gd, $q$UPDATE public.funcionarios SET status = 'inativo'$q$) = 'ok:0', 'A2: não inativa';
  ASSERT pg_temp.como(u.gd, format('SELECT ativo FROM public.profiles WHERE id = %L', u.gd)) = 'ok:1', 'A2: lê o próprio profile (o app faz logout por ele)';
  r := pg_temp.como(u.g, format('UPDATE public.profiles SET ativo = true WHERE id = %L', u.gd));
  ASSERT r LIKE '42501%', 'A2: nem gestor escreve direto: ' || r;
  ASSERT pg_temp.como(u.g, format('SELECT id, nome FROM public.profiles WHERE id = %L', u.s)) = 'ok:1', 'A2: gestor segue lendo profiles (aprovações)';
END $$;

-- ---------------------------------------------------------------- A3 períodos de inatividade
DO $$
DECLARE r text; u record; f5 uuid := pg_temp.f(5); hoje date := pg_temp.hoje();
  j text := 'Justificativa adequada do teste'; m text := 'Retorno combinado com o RH';
BEGIN
  SELECT * INTO u FROM _u;
  PERFORM pg_temp.inativar(5);
  -- simula saída há 30 dias
  ALTER TABLE public.funcionarios DISABLE TRIGGER trg_funcionarios_status;
  UPDATE public.funcionarios SET data_inativacao = hoje - 30 WHERE id = f5;
  ALTER TABLE public.funcionarios ENABLE TRIGGER trg_funcionarios_status;
  UPDATE public.funcionario_inatividades SET inicio = hoje - 30 WHERE funcionario_id = f5;

  r := pg_temp.como(u.g, pg_temp.ins(u.g, f5, hoje - 10, NULL, j));
  ASSERT r LIKE 'P0001 RETROATIVA_DATA%', 'A3: depois da saída: ' || r;

  ASSERT pg_temp.como(u.g, format($q$UPDATE public.funcionarios SET status = 'ativo', reativacao_motivo = %L WHERE id = %L$q$, m, f5)) = 'ok:1', 'A3: reativa';
  ASSERT (SELECT fim = hoje AND reativado_por = u.g AND motivo_reativacao = m FROM public.funcionario_inatividades WHERE funcionario_id = f5), 'A3: período encerrado, não apagado';
  ASSERT (SELECT data_inativacao IS NULL AND reativacao_motivo IS NULL FROM public.funcionarios WHERE id = f5), 'A3: motivo não fica no cadastro';

  r := pg_temp.como(u.g, pg_temp.ins(u.g, f5, hoje - 10));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%estava inativo%', 'A3: reativado não ganha datas do período: ' || r;
  r := pg_temp.como(u.s, pg_temp.ins(u.s, f5, hoje - 30));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%estava inativo%', 'A3: primeiro dia do período bloqueado: ' || r;
  ASSERT pg_temp.como(u.s, pg_temp.ins(u.s, f5, hoje)) = 'ok:1', 'A3: dia da reativação é permitido';
  ASSERT pg_temp.como(u.s, pg_temp.ins(u.s, f5, hoje - 31)) = 'ok:1', 'A3: véspera do período é permitida';

  ASSERT pg_temp.como(u.g, format($q$UPDATE public.funcionarios SET status = 'inativo' WHERE id = %L$q$, f5)) = 'ok:1', 'A3: inativa de novo';
  ASSERT (SELECT data_inativacao = hoje FROM public.funcionarios WHERE id = f5), 'A3: nova data';
  ASSERT (SELECT count(*) FROM public.funcionario_inatividades WHERE funcionario_id = f5) = 2, 'A3: os dois períodos preservados';

  -- a mesma retroativa do ataque continua barrada, mesmo com data_inativacao nova
  r := pg_temp.como(u.g, pg_temp.ins(u.g, f5, hoje - 10, NULL, j));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%estava inativo%', 'A3: mover a data não libera: ' || r;
  ASSERT pg_temp.como(u.g, pg_temp.ins(u.g, f5, hoje - 40, NULL, j)) = 'ok:1', 'A3: exceção legítima antes de todos os períodos';

  -- ninguém escreve nos períodos
  r := pg_temp.como(u.g, format($q$INSERT INTO public.funcionario_inatividades (funcionario_id, inicio) VALUES (%L, %L)$q$, f5, hoje));
  ASSERT r LIKE '42501%', 'A3: insert: ' || r;
  r := pg_temp.como(u.g, 'UPDATE public.funcionario_inatividades SET inicio = current_date');
  ASSERT r LIKE '42501%', 'A3: update: ' || r;
  r := pg_temp.como(u.g, 'DELETE FROM public.funcionario_inatividades');
  ASSERT r LIKE '42501%', 'A3: delete: ' || r;
  r := pg_temp.como_role('service_role', 'DELETE FROM public.funcionario_inatividades');
  ASSERT r LIKE '42501%', 'A3: service_role: ' || r;
  ASSERT pg_temp.como(u.g, 'SELECT id FROM public.funcionario_inatividades') LIKE 'ok:%', 'A3: gestor lê';
  ASSERT pg_temp.como(u.s, 'SELECT id FROM public.funcionario_inatividades') = 'ok:0', 'A3: supervisor não lê';
  ASSERT EXISTS (SELECT 1 FROM public.audit_logs WHERE entity_type = 'funcionario_inatividades' AND user_id = u.g), 'A3: período auditado';

  BEGIN
    DELETE FROM public.funcionario_inatividades WHERE funcionario_id = f5;
    RAISE EXCEPTION 'FALHA: período apagado';
  EXCEPTION WHEN raise_exception THEN
    ASSERT SQLERRM LIKE 'EXCLUSAO_PROIBIDA%', SQLERRM;
  END;
END $$;

-- ---------------------------------------------------------------- A4 reativação silenciosa
DO $$
DECLARE r text; u record; f6 uuid := pg_temp.f(6);
BEGIN
  SELECT * INTO u FROM _u;
  PERFORM pg_temp.inativar(6);
  -- exatamente o payload do formulário desatualizado
  r := pg_temp.como(u.g, format($q$UPDATE public.funcionarios SET nome = 'EDITADO', status = 'ativo' WHERE id = %L$q$, f6));
  ASSERT r LIKE 'P0001 REATIVACAO_MOTIVO%', 'A4: formulário antigo não reativa: ' || r;
  r := pg_temp.como(u.g, format($q$UPDATE public.funcionarios SET status = 'ferias' WHERE id = %L$q$, f6));
  ASSERT r LIKE 'P0001 REATIVACAO_MOTIVO%', 'A4: férias também é saída de inativo: ' || r;
  r := pg_temp.como(u.g, format($q$UPDATE public.funcionarios SET status = 'ativo', reativacao_motivo = %L WHERE id = %L$q$, E'\n\n\n . . . \n', f6));
  ASSERT r LIKE 'P0001 REATIVACAO_MOTIVO%', 'A4: motivo vazio: ' || r;
  ASSERT (SELECT status = 'inativo' AND data_inativacao IS NOT NULL AND nome = 'SEG 6' FROM public.funcionarios WHERE id = f6), 'A4: nada mudou';

  -- editar outros campos de inativo continua possível, sem tocar na inativação
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.funcionarios SET nome = 'NOVO NOME' WHERE id = %L$q$, f6)) = 'ok:1', 'A4: edição comum';
  ASSERT (SELECT status = 'inativo' AND data_inativacao IS NOT NULL FROM public.funcionarios WHERE id = f6), 'A4: segue inativo';

  -- motivo enviado sem reativar não fica gravado
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.funcionarios SET reativacao_motivo = 'qualquer motivo aqui' WHERE id = %L$q$, pg_temp.f(7))) = 'ok:1', 'A4: motivo ignorado';
  ASSERT (SELECT reativacao_motivo IS NULL FROM public.funcionarios WHERE id = pg_temp.f(7)), 'A4: coluna transitória';

  r := pg_temp.como(u.g, $q$INSERT INTO public.funcionarios (nome, re, cargo, turno, status) VALUES ('X', 'Z-1', 'ASG', 'Integral', 'inativo')$q$);
  ASSERT r LIKE 'P0001 CADASTRO_INATIVO%', 'A4: não nasce inativo, sem período: ' || r;
END $$;

-- ---------------------------------------------------------------- A5 exclusão de FT
DO $$
DECLARE r text; u record; v_ft uuid := 'c1000000-0000-0000-0000-000000000001'; n int;
BEGIN
  SELECT * INTO u FROM _u;
  INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por, status)
  VALUES (v_ft, pg_temp.f(9), DATE '2026-02-01', 'Falta', u.g, 'APROVADA');
  SELECT count(*) INTO n FROM public.ft_historico WHERE ft_id = v_ft;
  ASSERT n > 0, 'pressuposto: há histórico';

  r := pg_temp.como(u.g, format('DELETE FROM public.ft WHERE id = %L', v_ft));
  ASSERT r LIKE '42501%', 'A5: gestor: ' || r;
  r := pg_temp.como(u.ad, format('DELETE FROM public.ft WHERE id = %L', v_ft));
  ASSERT r LIKE '42501%', 'A5: admin: ' || r;
  r := pg_temp.como_role('service_role', format('DELETE FROM public.ft WHERE id = %L', v_ft));
  ASSERT r LIKE '42501%', 'A5: service_role: ' || r;
  r := pg_temp.como(u.g, 'TRUNCATE public.ft CASCADE');
  ASSERT r LIKE '42501%', 'A5: truncate: ' || r;
  r := pg_temp.como(u.g, format('DELETE FROM public.ft_historico WHERE ft_id = %L', v_ft));
  ASSERT r LIKE '42501%', 'A5: histórico: ' || r;

  BEGIN
    DELETE FROM public.ft WHERE id = v_ft;
    RAISE EXCEPTION 'FALHA: postgres apagou FT';
  EXCEPTION WHEN raise_exception THEN
    ASSERT SQLERRM LIKE 'EXCLUSAO_PROIBIDA%', SQLERRM;
  END;
  BEGIN
    DELETE FROM public.ft_historico WHERE ft_id = v_ft;
    RAISE EXCEPTION 'FALHA: postgres apagou histórico';
  EXCEPTION WHEN raise_exception THEN
    ASSERT SQLERRM LIKE 'EXCLUSAO_PROIBIDA%', SQLERRM;
  END;
  BEGIN
    TRUNCATE public.ft CASCADE;
    RAISE EXCEPTION 'FALHA: postgres truncou FT';
  EXCEPTION WHEN raise_exception THEN
    ASSERT SQLERRM LIKE 'EXCLUSAO_PROIBIDA%', SQLERRM;
  END;

  ASSERT NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'ft' AND cmd IN ('DELETE', 'ALL')), 'A5: sem policy';
  ASSERT NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE contype = 'f' AND confrelid IN ('public.ft'::regclass, 'public.funcionarios'::regclass) AND confdeltype <> 'r'
  ), 'A5: nenhuma FK em cascata para ft ou funcionarios';
END $$;

-- Com o trigger desligado de propósito, a FK ainda impede perder histórico
ALTER TABLE public.ft DISABLE TRIGGER trg_ft_bloquear_exclusao;
DO $$ BEGIN
  DELETE FROM public.ft WHERE id = 'c1000000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'FALHA: FK não segurou o histórico';
EXCEPTION WHEN foreign_key_violation OR restrict_violation THEN NULL;
END $$;
ALTER TABLE public.ft ENABLE TRIGGER trg_ft_bloquear_exclusao;

-- ---------------------------------------------------------------- A6 auditoria e histórico
DO $$
DECLARE r text; u record; v_ft uuid := 'c1000000-0000-0000-0000-000000000001'; v_id uuid := 'c1000000-0000-0000-0000-000000000002';
BEGIN
  SELECT * INTO u FROM _u;
  r := pg_temp.como(u.s, format($q$INSERT INTO public.ft_historico (ft_id, acao, alterado_por, observacao) VALUES (%L, 'LANCAMENTO_RETROATIVO', %L, 'forjado')$q$, v_ft, u.g));
  ASSERT r LIKE '42501%', 'A6: supervisor forja histórico: ' || r;
  r := pg_temp.como(u.g, format($q$INSERT INTO public.ft_historico (ft_id, acao, alterado_por, observacao) VALUES (%L, 'VALORES_CORRIGIDOS', %L, 'forjado')$q$, v_ft, u.g));
  ASSERT r LIKE '42501%', 'A6: nem gestor: ' || r;
  r := pg_temp.como(u.ap, format($q$INSERT INTO public.audit_logs (user_id, action, entity_type, entity_id) VALUES (%L, 'FT_RETROATIVA_EXCECAO', 'ft', %L)$q$, u.g, v_ft));
  ASSERT r LIKE '42501%', 'A6: apontamento forja audit_logs: ' || r;
  r := pg_temp.como(u.g, $q$UPDATE public.audit_logs SET observacao = 'x'$q$);
  ASSERT r LIKE '42501%', 'A6: update audit: ' || r;
  r := pg_temp.como(u.g, 'DELETE FROM public.audit_logs');
  ASSERT r LIKE '42501%', 'A6: delete audit: ' || r;
  r := pg_temp.como_role('service_role', $q$DELETE FROM public.audit_logs$q$);
  ASSERT r LIKE '42501%', 'A6: service_role não apaga audit: ' || r;
  ASSERT pg_temp.como_role('service_role', format($q$INSERT INTO public.audit_logs (user_id, username, role, action, entity_type, entity_id, description) VALUES (%L, 'sg', 'gestor', 'CRIAR_USUARIO', 'profiles', 'x', 'y')$q$, u.g)) = 'ok:1', 'A6: logAudit do servidor segue funcionando';

  -- correção de valores: registrada pelo banco, com o texto do frontend e o autor autenticado
  INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por) VALUES (v_id, pg_temp.f(10), DATE '2026-02-02', 'Falta', u.g);
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.ft SET valor_pago = 1250.5, pagamento_em_folha = true WHERE id = %L AND status = 'PENDENTE'$q$, v_id)) = 'ok:1', 'A6: correção';
  ASSERT (SELECT observacao FROM public.ft_historico WHERE ft_id = v_id AND acao = 'VALORES_CORRIGIDOS' AND alterado_por = u.g)
         = 'Valor: R$ 200,00 → R$ 1.250,50 · Pagamento em folha: Não → Sim', 'A6: texto igual a descreverCorrecao: ' ||
         coalesce((SELECT observacao FROM public.ft_historico WHERE ft_id = v_id AND acao = 'VALORES_CORRIGIDOS'), 'nada');
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.ft SET observacao = 'só observação' WHERE id = %L$q$, v_id)) = 'ok:1', 'A6: edição sem valor';
  ASSERT (SELECT count(*) FROM public.ft_historico WHERE ft_id = v_id AND acao = 'VALORES_CORRIGIDOS') = 1, 'A6: sem histórico indevido';
END $$;

-- ---------------------------------------------------------------- A7 FT nasce pendente
DO $$
DECLARE r text; u record; v record;
BEGIN
  SELECT * INTO u FROM _u;
  r := pg_temp.como(u.s, pg_temp.ins(u.s, pg_temp.f(11), DATE '2026-02-03', NULL, NULL, 'APROVADA'));
  ASSERT r LIKE 'P0001 FT_STATUS_INICIAL%', 'A7: supervisor: ' || r;
  r := pg_temp.como(u.g, pg_temp.ins(u.g, pg_temp.f(11), DATE '2026-02-03', NULL, NULL, 'APROVADA'));
  ASSERT r LIKE 'P0001 FT_STATUS_INICIAL%', 'A7: gestor também passa pela aprovação: ' || r;
  r := pg_temp.como(u.s, format($q$INSERT INTO public.ft (funcionario_id, data_ft, motivo, lancado_por, aprovado_por, numero_ft, created_at, data_lancamento, data_cancelamento) VALUES (%L, DATE '2026-02-04', 'Falta', %L, %L, 'FT-FORJADA', '2000-01-01', '2000-01-01', '2000-01-01')$q$, pg_temp.f(11), u.s, u.g));
  ASSERT r = 'ok:1', 'A7: insert comum: ' || r;
  SELECT * INTO v FROM public.ft WHERE funcionario_id = pg_temp.f(11);
  ASSERT v.aprovado_por IS NULL AND v.data_cancelamento IS NULL, 'A7: campos de decisão limpos';
  ASSERT v.numero_ft LIKE 'FT-20%-%', 'A7: número gerado pelo banco: ' || v.numero_ft;
  ASSERT v.created_at::date >= current_date - 1 AND v.data_lancamento::date >= current_date - 1, 'A7: datas de registro do banco';
END $$;

-- ---------------------------------------------------------------- M1 justificativa com conteúdo
DO $$
DECLARE r text; u record; t text; d date := pg_temp.hoje() - 20;
BEGIN
  SELECT * INTO u FROM _u;
  PERFORM pg_temp.inativar(12);
  FOREACH t IN ARRAY ARRAY[repeat(E'\n', 12), repeat(E'\t', 12), repeat(U&'\200B', 12), repeat(U&'\00A0', 12), repeat('.', 12), repeat('- ', 12), 'abc def gh'] LOOP
    r := pg_temp.como(u.g, pg_temp.ins(u.g, pg_temp.f(12), d, NULL, t));
    ASSERT r LIKE 'P0001 RETROATIVA_JUSTIFICATIVA%', 'M1: [' || t || ']: ' || r;
  END LOOP;
  ASSERT pg_temp.como(u.g, pg_temp.ins(u.g, pg_temp.f(12), d, NULL, 'Prestou serviço antes de sair')) = 'ok:1', 'M1: texto real';
END $$;

-- ---------------------------------------------------------------- M3 / M4 FT antiga
DO $$
DECLARE r text; u record; a uuid := 'c1000000-0000-0000-0000-000000000003'; b uuid := 'c1000000-0000-0000-0000-000000000004';
BEGIN
  SELECT * INTO u FROM _u;
  INSERT INTO public.ft (id, funcionario_id, funcionario_faltante_id, data_ft, motivo, lancado_por, status, aprovado_por) VALUES
    (a, pg_temp.f(13), pg_temp.f(14), DATE '2026-02-01', 'Falta', u.g, 'APROVADA', u.g),
    (b, pg_temp.f(15), pg_temp.f(16), DATE '2026-02-01', 'Falta', u.g, 'PENDENTE', NULL);

  -- FT decidida: vínculos e data congelados, mesmo só com ativos
  r := pg_temp.como(u.g, format('UPDATE public.ft SET funcionario_id = %L WHERE id = %L', pg_temp.f(17), a));
  ASSERT r LIKE 'P0001 FT_VINCULO_IMUTAVEL%', 'M3: aprovada, titular: ' || r;
  r := pg_temp.como(u.g, format('UPDATE public.ft SET funcionario_faltante_id = NULL WHERE id = %L', a));
  ASSERT r LIKE 'P0001 FT_VINCULO_IMUTAVEL%', 'M3: aprovada, faltante: ' || r;
  r := pg_temp.como(u.g, format($q$UPDATE public.ft SET data_ft = DATE '2026-02-20' WHERE id = %L$q$, a));
  ASSERT r LIKE 'P0001 FT_VINCULO_IMUTAVEL%', 'M3: aprovada, data: ' || r;

  -- FT pendente com inativo: não some do histórico
  PERFORM pg_temp.inativar(15);
  PERFORM pg_temp.inativar(16);
  r := pg_temp.como(u.g, format('UPDATE public.ft SET funcionario_faltante_id = NULL WHERE id = %L', b));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'M3: tirar faltante inativo: ' || r;
  r := pg_temp.como(u.g, format('UPDATE public.ft SET funcionario_id = %L WHERE id = %L', pg_temp.f(17), b));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'M3: trocar titular inativo: ' || r;

  -- operações legítimas da FT antiga
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.ft SET status = 'CANCELADA', data_cancelamento = now() WHERE id = %L$q$, a)) = 'ok:1', 'M3: aprovada segue cancelável';
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.ft SET status = 'APROVADA', aprovado_por = %L WHERE id = %L$q$, u.g, b)) = 'ok:1', 'M3: FT antiga de inativo aprova (data anterior)';

  -- M4 campos históricos
  r := pg_temp.como(u.g, format('UPDATE public.ft SET lancado_por = %L WHERE id = %L', u.s, b));
  ASSERT r LIKE 'P0001 FT_IMUTAVEL%', 'M4: lancado_por: ' || r;
  r := pg_temp.como(u.g, format($q$UPDATE public.ft SET numero_ft = 'FT-FALSO' WHERE id = %L$q$, b));
  ASSERT r LIKE 'P0001 FT_IMUTAVEL%', 'M4: numero_ft: ' || r;
  r := pg_temp.como(u.g, format($q$UPDATE public.ft SET created_at = '2020-01-01' WHERE id = %L$q$, b));
  ASSERT r LIKE 'P0001 FT_IMUTAVEL%', 'M4: created_at: ' || r;
  r := pg_temp.como(u.g, format($q$UPDATE public.ft SET data_lancamento = '2020-01-01' WHERE id = %L$q$, b));
  ASSERT r LIKE 'P0001 FT_IMUTAVEL%', 'M4: data_lancamento: ' || r;
  r := pg_temp.como(u.g, format('UPDATE public.ft SET id = gen_random_uuid() WHERE id = %L', b));
  ASSERT r LIKE 'P0001 FT_IMUTAVEL%', 'M4: id: ' || r;

  -- aprovado_por vem do autenticado
  INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por) VALUES ('c1000000-0000-0000-0000-000000000005', pg_temp.f(18), DATE '2026-02-05', 'Falta', u.s);
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.ft SET status = 'APROVADA', aprovado_por = %L WHERE id = 'c1000000-0000-0000-0000-000000000005'$q$, u.s)) = 'ok:1', 'M4: aprovação';
  ASSERT (SELECT aprovado_por = u.g FROM public.ft WHERE id = 'c1000000-0000-0000-0000-000000000005'), 'M4: aprovador forjado é trocado pelo autenticado';
  ASSERT pg_temp.como(u.g, $q$UPDATE public.ft SET aprovado_por = NULL WHERE id = 'c1000000-0000-0000-0000-000000000005'$q$) = 'ok:1', 'M4: limpar aprovador';
  ASSERT (SELECT aprovado_por = u.g FROM public.ft WHERE id = 'c1000000-0000-0000-0000-000000000005'), 'M4: aprovador não some';
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.ft SET aprovado_por = %L WHERE id = 'c1000000-0000-0000-0000-000000000005'$q$, u.s)) = 'ok:1', 'M4: trocar aprovador';
  ASSERT (SELECT aprovado_por = u.g FROM public.ft WHERE id = 'c1000000-0000-0000-0000-000000000005'), 'M4: aprovador não muda fora de decisão';
END $$;

-- ---------------------------------------------------------------- M3: um único vínculo inativo e FT reaberta
DO $$
DECLARE r text; u record;
  so_falt uuid := 'c1000000-0000-0000-0000-000000000041'; so_tit uuid := 'c1000000-0000-0000-0000-000000000042';
  reaberta uuid := 'c1000000-0000-0000-0000-000000000043'; negada uuid := 'c1000000-0000-0000-0000-000000000044';
BEGIN
  SELECT * INTO u FROM _u;
  INSERT INTO public.ft (id, funcionario_id, funcionario_faltante_id, data_ft, motivo, lancado_por) VALUES
    (so_falt, pg_temp.f(33), pg_temp.f(34), DATE '2026-02-10', 'Falta', u.g),
    (so_tit, pg_temp.f(35), NULL, DATE '2026-02-11', 'Falta', u.g),
    (reaberta, pg_temp.f(36), NULL, DATE '2026-02-12', 'Falta', u.g),
    (negada, pg_temp.f(37), NULL, DATE '2026-02-13', 'Falta', u.g);
  PERFORM pg_temp.inativar(34);
  PERFORM pg_temp.inativar(35);

  -- o vínculo novo é ativo; só o antigo é inativo
  r := pg_temp.como(u.g, format('UPDATE public.ft SET funcionario_faltante_id = NULL WHERE id = %L', so_falt));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'M3: tirar o único inativo (faltante): ' || r;
  r := pg_temp.como(u.g, format('UPDATE public.ft SET funcionario_id = %L WHERE id = %L', pg_temp.f(38), so_tit));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'M3: tirar o único inativo (titular): ' || r;

  -- aprovar, voltar para PENDENTE e trocar: a decisão anterior continua travando
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.ft SET status = 'APROVADA', aprovado_por = %L WHERE id = %L$q$, u.g, reaberta)) = 'ok:1', 'M3: aprova';
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.ft SET status = 'PENDENTE' WHERE id = %L$q$, reaberta)) = 'ok:1', 'M3: reabre';
  r := pg_temp.como(u.g, format('UPDATE public.ft SET funcionario_id = %L WHERE id = %L', pg_temp.f(38), reaberta));
  ASSERT r LIKE 'P0001 FT_VINCULO_IMUTAVEL%', 'M3: aprovada e reaberta: ' || r;
  r := pg_temp.como(u.g, format($q$UPDATE public.ft SET data_ft = DATE '2026-03-12' WHERE id = %L$q$, reaberta));
  ASSERT r LIKE 'P0001 FT_VINCULO_IMUTAVEL%', 'M3: data de FT reaberta: ' || r;
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.ft SET status = 'NEGADA', aprovado_por = %L WHERE id = %L$q$, u.g, negada)) = 'ok:1', 'M3: nega';
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.ft SET status = 'PENDENTE' WHERE id = %L$q$, negada)) = 'ok:1', 'M3: reabre negada';
  r := pg_temp.como(u.g, format('UPDATE public.ft SET funcionario_id = %L WHERE id = %L', pg_temp.f(38), negada));
  ASSERT r LIKE 'P0001 FT_VINCULO_IMUTAVEL%', 'M3: negada e reaberta: ' || r;
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.ft SET status = 'APROVADA', aprovado_por = %L WHERE id = %L$q$, u.g, negada)) = 'ok:1', 'M3: reaberta segue decidível';
END $$;

-- ---------------------------------------------------------------- variações de A3 contra período encerrado
DO $$
DECLARE r text; u record; hoje date := pg_temp.hoje(); f30 uuid := pg_temp.f(30); v_ft uuid := 'c1000000-0000-0000-0000-000000000031';
BEGIN
  SELECT * INTO u FROM _u;
  PERFORM pg_temp.inativar(30);
  UPDATE public.funcionario_inatividades SET inicio = hoje - 20 WHERE funcionario_id = f30;
  ALTER TABLE public.funcionarios DISABLE TRIGGER trg_funcionarios_status;
  UPDATE public.funcionarios SET data_inativacao = hoje - 20 WHERE id = f30;
  ALTER TABLE public.funcionarios ENABLE TRIGGER trg_funcionarios_status;
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.funcionarios SET status = 'ativo', reativacao_motivo = 'retorno combinado com o RH' WHERE id = %L$q$, f30)) = 'ok:1', 'reativa';

  r := pg_temp.como(u.s, pg_temp.ins(u.s, pg_temp.f(31), hoje - 10, f30));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%estava inativo%', 'faltante em período encerrado: ' || r;

  INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por) VALUES (v_ft, f30, hoje, 'Falta', u.s);
  r := pg_temp.como(u.g, format('UPDATE public.ft SET data_ft = %L WHERE id = %L', hoje - 10, v_ft));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%estava inativo%', 'mover data para dentro do período: ' || r;
  ASSERT pg_temp.como(u.g, format('UPDATE public.ft SET data_ft = %L WHERE id = %L', hoje + 1, v_ft)) = 'ok:1', 'data fora do período segue possível em FT pendente';

  INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por) VALUES ('c1000000-0000-0000-0000-000000000032', pg_temp.f(32), hoje - 10, 'Falta', u.s);
  r := pg_temp.como(u.g, format($q$UPDATE public.ft SET funcionario_id = %L WHERE id = 'c1000000-0000-0000-0000-000000000032'$q$, f30));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%estava inativo%', 'trocar para quem estava inativo na data: ' || r;
END $$;

-- ---------------------------------------------------------------- FT dentro de período de inatividade não é aprovada
DO $$
DECLARE r text; u record; hoje date := pg_temp.hoje();
  fut uuid := 'c1000000-0000-0000-0000-000000000011'; falt uuid := 'c1000000-0000-0000-0000-000000000012';
  ant uuid := 'c1000000-0000-0000-0000-000000000013'; fechado uuid := 'c1000000-0000-0000-0000-000000000014';
  neg uuid := 'c1000000-0000-0000-0000-000000000015';
BEGIN
  SELECT * INTO u FROM _u;
  INSERT INTO public.ft (id, funcionario_id, funcionario_faltante_id, data_ft, motivo, lancado_por) VALUES
    (fut, pg_temp.f(20), NULL, hoje + 5, 'Falta', u.s),
    (falt, pg_temp.f(21), pg_temp.f(22), hoje + 5, 'Falta', u.s),
    (ant, pg_temp.f(20), NULL, hoje - 2, 'Falta', u.s),
    (fechado, pg_temp.f(23), NULL, hoje, 'Falta', u.s),
    (neg, pg_temp.f(20), NULL, hoje + 6, 'Falta', u.s);
  PERFORM pg_temp.inativar(20);
  PERFORM pg_temp.inativar(22);
  PERFORM pg_temp.inativar(23);

  r := pg_temp.como(u.g, format($q$UPDATE public.ft SET status = 'APROVADA', aprovado_por = %L WHERE id = %L$q$, u.g, fut));
  ASSERT r LIKE 'P0001 FT_INATIVO_NA_DATA%', 'FT futura de inativo não aprova: ' || r;
  r := pg_temp.como(u.g, format($q$UPDATE public.ft SET status = 'APROVADA', aprovado_por = %L WHERE id = %L$q$, u.g, falt));
  ASSERT r LIKE 'P0001 FT_INATIVO_NA_DATA%', 'faltante inativo na data não aprova: ' || r;
  ASSERT (SELECT status FROM public.ft WHERE id = fut) = 'PENDENTE', 'registro preservado para análise';

  ASSERT pg_temp.como(u.g, format($q$UPDATE public.ft SET status = 'APROVADA', aprovado_por = %L WHERE id = %L$q$, u.g, ant)) = 'ok:1', 'data anterior à inativação aprova';
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.ft SET status = 'NEGADA', aprovado_por = %L WHERE id = %L$q$, u.g, fut)) = 'ok:1', 'pode ser negada';
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.ft SET status = 'CANCELADA', data_cancelamento = now() WHERE id = %L$q$, falt)) = 'ok:1', 'pode ser cancelada';

  -- reabrir NEGADA não fura a aprovação
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.ft SET status = 'PENDENTE' WHERE id = %L$q$, fut)) = 'ok:1', 'reabre';
  r := pg_temp.como(u.g, format($q$UPDATE public.ft SET status = 'APROVADA', aprovado_por = %L WHERE id = %L$q$, u.g, fut));
  ASSERT r LIKE 'P0001 FT_INATIVO_NA_DATA%', 'reaberta segue sem aprovar: ' || r;

  -- período encerrado continua valendo para FT pendente anterior à reativação, salvo no próprio dia (fim exclusivo)
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.funcionarios SET status = 'ativo', reativacao_motivo = 'erro de cadastro corrigido' WHERE id = %L$q$, pg_temp.f(23))) = 'ok:1', 'reativa no mesmo dia';
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.ft SET status = 'APROVADA', aprovado_por = %L WHERE id = %L$q$, u.g, fechado)) = 'ok:1', 'inativação desfeita no mesmo dia não bloqueia';
END $$;

-- ---------------------------------------------------------------- anulação de período
DO $$
DECLARE r text; u record; hoje date := pg_temp.hoje(); f uuid := pg_temp.f(39); p uuid; p2 uuid; a uuid := 'c1000000-0000-0000-0000-000000000051';
  b uuid := 'c1000000-0000-0000-0000-000000000052'; j text := 'Inativado por engano, seguiu trabalhando'; v record;
  sql_anula text;
BEGIN
  SELECT * INTO u FROM _u;
  -- FTs lançadas antes da inativação, com data dentro do período: uma aprovada, outra pendente
  INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por, status, aprovado_por) VALUES
    (a, f, hoje - 10, 'Falta', u.g, 'APROVADA', u.g), (b, f, hoje - 9, 'Falta', u.s, 'PENDENTE', NULL);
  PERFORM pg_temp.inativar(39);
  UPDATE public.funcionario_inatividades SET inicio = hoje - 20 WHERE funcionario_id = f RETURNING id INTO p;
  ALTER TABLE public.funcionarios DISABLE TRIGGER trg_funcionarios_status;
  UPDATE public.funcionarios SET data_inativacao = hoje - 20 WHERE id = f;
  ALTER TABLE public.funcionarios ENABLE TRIGGER trg_funcionarios_status;
  sql_anula := format('SELECT public.anular_inatividade(%L, %L)', p, j);

  -- período em curso não é anulável: primeiro reativar, com motivo
  r := pg_temp.como(u.g, sql_anula);
  ASSERT r LIKE 'P0001 ANULACAO_ESTADO%reative%', 'anulação: período em curso: ' || r;
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.funcionarios SET status = 'ativo', reativacao_motivo = 'inativado por engano no sistema' WHERE id = %L$q$, f)) = 'ok:1', 'anulação: reativa';

  -- antes de anular, o período bloqueia
  r := pg_temp.como(u.g, format($q$UPDATE public.ft SET status = 'APROVADA', aprovado_por = %L WHERE id = %L$q$, u.g, b));
  ASSERT r LIKE 'P0001 FT_INATIVO_NA_DATA%', 'anulação: bloqueado antes: ' || r;
  r := pg_temp.como(u.s, pg_temp.ins(u.s, f, hoje - 5));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'anulação: lançamento bloqueado antes: ' || r;

  -- autorização: só Gestor ativo, conferido no banco
  r := pg_temp.como(u.s, sql_anula);
  ASSERT r LIKE 'P0001 PERMISSAO%', 'anulação: supervisor: ' || r;
  r := pg_temp.como(u.ad, sql_anula);
  ASSERT r LIKE 'P0001 PERMISSAO%', 'anulação: admin: ' || r;
  r := pg_temp.como(u.ap, sql_anula);
  ASSERT r LIKE 'P0001 PERMISSAO%', 'anulação: apontamento: ' || r;
  r := pg_temp.como(u.gd, sql_anula);
  ASSERT r LIKE 'P0001 PERMISSAO%', 'anulação: gestor desativado: ' || r;
  r := pg_temp.como(u.s, sql_anula, '{"role":"gestor"}');
  ASSERT r LIKE 'P0001 PERMISSAO%', 'anulação: metadata: ' || r;
  r := pg_temp.como_role('anon', sql_anula);
  ASSERT r LIKE '42501%', 'anulação: anon: ' || r;
  r := pg_temp.como_role('service_role', sql_anula);
  ASSERT r LIKE '42501%', 'anulação: service_role: ' || r;

  -- justificativa
  r := pg_temp.como(u.g, format('SELECT public.anular_inatividade(%L, %L)', p, repeat(E'
', 20)));
  ASSERT r LIKE 'P0001 ANULACAO_JUSTIFICATIVA%', 'anulação: justificativa vazia: ' || r;
  r := pg_temp.como(u.g, format('SELECT public.anular_inatividade(%L, NULL)', p));
  ASSERT r LIKE 'P0001 ANULACAO_JUSTIFICATIVA%', 'anulação: sem justificativa: ' || r;

  -- escrita direta não existe
  r := pg_temp.como(u.g, format('UPDATE public.funcionario_inatividades SET anulada_em = now(), anulada_por = %L, anulacao_justificativa = %L, anulacao_fts = %L WHERE id = %L', u.g, j, '[]', p));
  ASSERT r LIKE '42501%', 'anulação: UPDATE direto: ' || r;
  r := pg_temp.como_role('service_role', format('UPDATE public.funcionario_inatividades SET fim = inicio WHERE id = %L', p));
  ASSERT r LIKE '42501%', 'anulação: UPDATE service_role: ' || r;
  ASSERT (SELECT anulada_em IS NULL FROM public.funcionario_inatividades WHERE id = p), 'anulação: nada mudou até aqui';

  -- caso válido
  ASSERT pg_temp.como(u.g, sql_anula) = 'ok:1', 'anulação: gestor';
  SELECT * INTO v FROM public.funcionario_inatividades WHERE id = p;
  ASSERT v.anulada_por = u.g AND v.anulada_em IS NOT NULL AND v.anulacao_justificativa = j, 'anulação: autoria, data e justificativa';
  ASSERT v.inicio = hoje - 20 AND v.fim = hoje AND v.motivo_reativacao IS NOT NULL, 'anulação: período original intacto';
  ASSERT jsonb_array_length(v.anulacao_fts) = 2, 'anulação: FTs do período registradas: ' || v.anulacao_fts::text;
  ASSERT EXISTS (SELECT 1 FROM public.audit_logs WHERE action = 'ANULAR_INATIVIDADE' AND entity_id = p::text AND user_id = u.g AND observacao = j), 'anulação: audit_logs';
  ASSERT EXISTS (SELECT 1 FROM public.audit_logs WHERE action = 'UPDATE' AND entity_type = 'funcionario_inatividades' AND entity_id = p::text AND new_data->>'anulada_por' = u.g::text), 'anulação: auditoria da linha';

  -- efeito: datas liberadas; FTs existentes intactas
  ASSERT (SELECT status = 'APROVADA' AND aprovado_por = u.g FROM public.ft WHERE id = a), 'anulação: FT aprovada intacta';
  ASSERT (SELECT status = 'PENDENTE' FROM public.ft WHERE id = b), 'anulação: FT pendente não muda sozinha';
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.ft SET status = 'APROVADA', aprovado_por = %L WHERE id = %L$q$, u.g, b)) = 'ok:1', 'anulação: agora aprova';
  ASSERT pg_temp.como(u.s, pg_temp.ins(u.s, f, hoje - 5)) = 'ok:1', 'anulação: agora lança';

  -- irreversível e sem repetição
  r := pg_temp.como(u.g, sql_anula);
  ASSERT r LIKE 'P0001 ANULACAO_ESTADO%já foi anulado%', 'anulação: repetida: ' || r;
  r := pg_temp.como(u.g, format('SELECT public.anular_inatividade(%L, %L)', gen_random_uuid(), j));
  ASSERT r LIKE 'P0001 ANULACAO_ESTADO%não encontrado%', 'anulação: período inexistente: ' || r;

  -- anular um período não libera outro, e inativo não anula período antigo
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.funcionarios SET status = 'inativo' WHERE id = %L$q$, f)) = 'ok:1', 'anulação: nova inativação';
  SELECT id INTO p2 FROM public.funcionario_inatividades WHERE funcionario_id = f AND fim IS NULL;
  r := pg_temp.como(u.g, format('SELECT public.anular_inatividade(%L, %L)', p2, j));
  ASSERT r LIKE 'P0001 ANULACAO_ESTADO%reative%', 'anulação: novo período em curso: ' || r;
  r := pg_temp.como(u.s, pg_temp.ins(u.s, f, hoje + 2));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'anulação: período novo segue valendo: ' || r;
  r := pg_temp.como(u.g, pg_temp.ins(u.g, f, hoje - 15, NULL, j));
  ASSERT r = 'ok:1', 'anulação: exceção retroativa segue pela regra: ' || r;
  ASSERT (SELECT retroativa_justificativa = j FROM public.ft WHERE funcionario_id = f AND data_ft = hoje - 15), 'anulação: exceção registrada';
END $$;

-- ---------------------------------------------------------------- ataques que precisam continuar falhando
DO $$
DECLARE r text; u record; v_id uuid := 'c1000000-0000-0000-0000-000000000021'; ontem date := pg_temp.hoje() - 1;
  j text := 'Justificativa adequada do teste';
BEGIN
  SELECT * INTO u FROM _u;
  PERFORM pg_temp.inativar(25);
  INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por) VALUES (v_id, pg_temp.f(26), DATE '2026-03-01', 'Falta', u.g);

  r := pg_temp.como(u.s, pg_temp.ins(u.s, pg_temp.f(25), ontem, NULL, j), '{"role":"gestor"}');
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'metadata no JWT: ' || r;
  r := pg_temp.como(u.g, format($q$INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por, retroativa_justificativa) VALUES (%L,%L,%L,'Falta',%L,%L) ON CONFLICT (id) DO UPDATE SET funcionario_id = EXCLUDED.funcionario_id, retroativa_justificativa = EXCLUDED.retroativa_justificativa, retroativa_autorizada_por = EXCLUDED.retroativa_autorizada_por, retroativa_autorizada_em = EXCLUDED.retroativa_autorizada_em$q$, v_id, pg_temp.f(25), ontem, u.g, j));
  ASSERT r LIKE 'P0001 RETROATIVA_IMUTAVEL%', 'upsert completo: ' || r;
  r := pg_temp.como(u.g, format($q$INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por, retroativa_justificativa) VALUES (%L,%L,%L,'Falta',%L,%L) ON CONFLICT (id) DO UPDATE SET funcionario_id = EXCLUDED.funcionario_id$q$, v_id, pg_temp.f(25), ontem, u.g, j));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'upsert parcial: ' || r;
  r := pg_temp.como(u.s, format($q$INSERT INTO public.ft (funcionario_id, data_ft, motivo, lancado_por) VALUES (%L, DATE '2026-03-05', 'Falta', %L), (%L, DATE '2026-03-05', 'Falta', %L)$q$, pg_temp.f(27), u.s, pg_temp.f(25), u.s));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'lote: ' || r;
  ASSERT NOT EXISTS (SELECT 1 FROM public.ft WHERE funcionario_id = pg_temp.f(27)), 'lote é atômico';

  -- funções internas não são chamáveis
  r := pg_temp.como(u.s, $q$SELECT public.log_audit('X', 'ft', '1')$q$);
  ASSERT r LIKE '42501%', 'log_audit: ' || r;
  r := pg_temp.como(u.s, $q$SELECT public.funcionario_em_inatividade('b1000000-0000-0000-0000-000000000001', current_date)$q$);
  ASSERT r LIKE '42501%', 'funcionario_em_inatividade: ' || r;
  r := pg_temp.como(u.s, $q$SELECT public.texto_justificativa_valido('x')$q$);
  ASSERT r LIKE '42501%', 'texto_justificativa_valido: ' || r;
END $$;

-- ---------------------------------------------------------------- catálogo
DO $$
DECLARE r text; t text; p text;
BEGIN
  FOREACH r IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    FOREACH t IN ARRAY ARRAY['public.profiles', 'public.user_roles', 'public.audit_logs', 'public.ft_historico'] LOOP
      FOREACH p IN ARRAY ARRAY['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'] LOOP
        ASSERT NOT has_table_privilege(r, t, p), format('%s com %s em %s', r, p, t);
      END LOOP;
    END LOOP;
    FOREACH t IN ARRAY ARRAY['public.funcionarios', 'public.ft', 'public.funcionario_inatividades'] LOOP
      ASSERT NOT has_table_privilege(r, t, 'DELETE') AND NOT has_table_privilege(r, t, 'TRUNCATE'), format('%s em %s', r, t);
    END LOOP;
  END LOOP;
  ASSERT NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname IN ('Users update own profile', 'Users insert own profile', 'Admins manage roles', 'Auth insert audit', 'Auth insert historico', 'Gestores delete ft', 'Gestores delete funcionarios')), 'policies antigas removidas';
  ASSERT pg_get_functiondef('public.handle_new_user'::regproc) NOT LIKE '%user_roles%', 'handle_new_user não concede perfil';
END $$;

ROLLBACK;
