-- TESTE LOCAL — NÃO RODAR EM PRODUÇÃO. Execução: bash supabase/tests/rodar_local.sh (Postgres descartável; dados fictícios).
-- Importação oficial: CPF restrito por perfil, primeira importação, quadro completo, inativação em lote, novas ações, revisão e expiração.

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
CREATE FUNCTION pg_temp.f(i int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT ('ca000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.atual(p_f uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('nome', nome, 'cpf', cpf, 'status', status, 're', re, 'cargo', cargo, 'empresa', empresa) FROM public.funcionarios WHERE id = p_f $$;
CREATE FUNCTION pg_temp.item(p_tipo text, p_f uuid, p_folha jsonb, p_acao text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('tipo', p_tipo, 'funcionario_id', p_f, 'folha', p_folha, 'atual', CASE WHEN p_f IS NULL THEN NULL ELSE pg_temp.atual(p_f) END,
    'acao', p_acao, 'opcoes', CASE WHEN p_acao IS NULL THEN '[]'::jsonb ELSE jsonb_build_array(p_acao) END, 'motivo', 'teste', 'origens', jsonb_build_array('Relacao:7'))
$$;
CREATE FUNCTION pg_temp.cria(p_empresa text, p_itens jsonb) RETURNS text LANGUAGE sql AS $$
  SELECT format('SELECT public.conferencia_criar(%L::jsonb, %L::jsonb, %L::jsonb)', jsonb_build_object('nome', 'relacao.xlsx', 'empresa', p_empresa), '{"total_folha":1}', p_itens)
$$;
CREATE FUNCTION pg_temp.aberta() RETURNS uuid LANGUAGE sql AS $$ SELECT id FROM public.conferencias WHERE status = 'ABERTA' $$;
CREATE FUNCTION pg_temp.rev() RETURNS int LANGUAGE sql AS $$ SELECT revisao FROM public.conferencias WHERE status = 'ABERTA' $$;
CREATE FUNCTION pg_temp.it(p_f uuid, p_acao text) RETURNS uuid LANGUAGE sql AS $$
  SELECT id FROM public.conferencia_itens WHERE conferencia_id = pg_temp.aberta() AND funcionario_id IS NOT DISTINCT FROM p_f AND p_acao = ANY (opcoes) $$;

INSERT INTO auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
SELECT '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.n || '@teste.local', jsonb_build_object('username', u.n, 'nome', u.n, 'role', u.r), now(), now()
FROM (VALUES
 ('cb000000-0000-0000-0000-000000000001'::uuid, 'ig', 'gestor'), ('cb000000-0000-0000-0000-000000000002'::uuid, 'is', 'supervisor'),
 ('cb000000-0000-0000-0000-000000000003'::uuid, 'ia', 'admin'), ('cb000000-0000-0000-0000-000000000004'::uuid, 'ip', 'apontamento'),
 ('cb000000-0000-0000-0000-000000000005'::uuid, 'id', 'gestor')) u(id, n, r);
UPDATE public.profiles SET ativo = (username <> 'id') WHERE username IN ('ig', 'is', 'ia', 'ip', 'id');
CREATE TEMP TABLE _u ON COMMIT DROP AS SELECT 'cb000000-0000-0000-0000-000000000001'::uuid g, 'cb000000-0000-0000-0000-000000000002'::uuid s,
  'cb000000-0000-0000-0000-000000000003'::uuid ad, 'cb000000-0000-0000-0000-000000000004'::uuid ap, 'cb000000-0000-0000-0000-000000000005'::uuid gd;
GRANT SELECT ON _u TO PUBLIC;

INSERT INTO public.funcionarios (id, nome, re, cpf, cargo, turno, empresa) VALUES
 (pg_temp.f(1), 'ATIVO UM',      'R1', '61300101334', 'Porteiro',   'Integral', 'MC REMOTA LTDA'),
 (pg_temp.f(2), 'AUSENTE COM FT','R2', '61300202602', 'Porteiro',   'Integral', 'MC REMOTA LTDA'),
 (pg_temp.f(3), 'FREELA AUSENTE','R3', '61300303980', 'Freelancer', 'Integral', 'MC REMOTA LTDA'),
 (pg_temp.f(4), 'OUTRA EMPRESA', 'R4', '61300405201', 'Porteiro',   'Integral', 'M C SERVICOS GERAIS LTDA'),
 (pg_temp.f(5), 'RE OCUPADO',    'R5', '61300506580', 'Porteiro',   'Integral', 'MC REMOTA LTDA'),
 (pg_temp.f(6), 'DONO R6',       'R6', '61300607858', 'Porteiro',   'Integral', 'MC REMOTA LTDA'),
 (pg_temp.f(7), 'TROCA RE',      'R7', '61300709189', 'Porteiro',   'Integral', 'MC REMOTA LTDA'),
 (pg_temp.f(8), 'TRANSFERIDO',   'G8', '61300810491', 'Porteiro',   'Integral', 'M C SERVICOS GERAIS LTDA'),
 (pg_temp.f(9), 'NOME E CARGO',  'R9', '61300911760', 'ASG',        'Integral', 'MC REMOTA LTDA');
INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por, status, aprovado_por) VALUES
 ('cc000000-0000-0000-0000-000000000001', pg_temp.f(2), DATE '2026-01-05', 'Falta', 'cb000000-0000-0000-0000-000000000001', 'APROVADA', 'cb000000-0000-0000-0000-000000000001');
CREATE TEMP TABLE _foto ON COMMIT DROP AS
  SELECT (SELECT md5(string_agg(t::text, '|' ORDER BY id)) FROM public.ft t) ft, (SELECT md5(string_agg(h::text, '|' ORDER BY id)) FROM public.ft_historico h) hist;
GRANT SELECT ON _foto TO PUBLIC;

-- ---------------------------------------------------------------- CPF restrito por perfil
DO $$
DECLARE u record; r text; p uuid;
BEGIN
  SELECT * INTO u FROM _u;
  FOREACH p IN ARRAY ARRAY[u.g, u.s, u.ad, u.ap, u.gd] LOOP
    ASSERT pg_temp.como(p, 'SELECT cpf FROM public.funcionarios') LIKE '42501%', 'leu a coluna cpf: ' || p;
    ASSERT pg_temp.como(p, 'SELECT * FROM public.funcionarios') LIKE '42501%', 'select * leu cpf: ' || p;
    ASSERT pg_temp.como(p, 'SELECT f.cpf FROM public.ft t JOIN public.funcionarios f ON f.id = t.funcionario_id') LIKE '42501%', 'embed leu cpf: ' || p;
    ASSERT pg_temp.como(p, 'SELECT count(*) FROM public.funcionarios WHERE cpf IS NOT NULL') LIKE '42501%', 'filtro por cpf: ' || p;
    ASSERT pg_temp.como(p, format($q$UPDATE public.funcionarios SET cpf = '61301013099' WHERE id = %L$q$, pg_temp.f(1))) LIKE '42501%', 'update direto do cpf: ' || p;
  END LOOP;
  ASSERT pg_temp.como(u.s, 'SELECT id, nome, re, empresa, status FROM public.funcionarios') LIKE 'ok:%', 'demais colunas seguem legíveis';
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.funcionarios SET supervisor = 'X' WHERE id = %L$q$, pg_temp.f(1))) = 'ok:1', 'gestor segue editando o resto';

  FOREACH p IN ARRAY ARRAY[u.s, u.ad, u.ap, u.gd] LOOP
    ASSERT pg_temp.como(p, format('SELECT public.funcionario_cpf(%L)', pg_temp.f(1))) LIKE 'P0001 PERMISSAO%', 'funcionario_cpf: ' || p;
    ASSERT pg_temp.como(p, 'SELECT * FROM public.funcionarios_cpfs()') LIKE 'P0001 PERMISSAO%', 'funcionarios_cpfs: ' || p;
    ASSERT pg_temp.como(p, format($q$SELECT public.funcionario_alterar_cpf(%L, '61301013099', 'tentativa sem perfil de gestor')$q$, pg_temp.f(1))) LIKE 'P0001 PERMISSAO%', 'alterar: ' || p;
  END LOOP;
  ASSERT pg_temp.como(u.g, format('SELECT public.funcionario_cpf(%L)', pg_temp.f(1))) = 'ok:1', 'gestor lê pela função';
  ASSERT pg_temp.como(u.g, 'SELECT * FROM public.funcionarios_cpfs()') LIKE 'ok:%', 'gestor lista';

  r := pg_temp.como(u.g, format($q$SELECT public.funcionario_alterar_cpf(%L, '61301013099', 'curto')$q$, pg_temp.f(1)));
  ASSERT r LIKE 'P0001 CPF_JUSTIFICATIVA%', 'sem justificativa: ' || r;
  r := pg_temp.como(u.g, format($q$SELECT public.funcionario_alterar_cpf(%L, '61301013098', 'Corrigido conforme documento')$q$, pg_temp.f(1)));
  ASSERT r LIKE 'P0001 CPF_INVALIDO%', 'inválido: ' || r;
  r := pg_temp.como(u.g, format($q$SELECT public.funcionario_alterar_cpf(%L, '613.002.026-02', 'Corrigido conforme documento')$q$, pg_temp.f(1)));
  ASSERT r LIKE 'P0001 CPF_DUPLICADO%', 'duplicado mesmo com pontuação: ' || r;
  ASSERT pg_temp.como(u.g, format($q$SELECT public.funcionario_alterar_cpf(%L, '613.010.130-99', 'Corrigido conforme documento')$q$, pg_temp.f(1))) = 'ok:1', 'altera';
  ASSERT (SELECT cpf FROM public.funcionarios WHERE id = pg_temp.f(1)) = '61301013099', 'gravado só com dígitos';
  ASSERT (SELECT observacao = 'Corrigido conforme documento' AND new_data->>'cpf' = '***.010.130-**' AND old_data->>'cpf' = '***.001.013-**'
            FROM public.audit_logs WHERE action = 'CPF_ALTERADO' AND entity_id = pg_temp.f(1)::text AND user_id = u.g), 'auditoria mascarada com justificativa';

  -- inserir com CPF: normaliza e valida; caminhos de serviço também exigem justificativa para alterar
  ASSERT pg_temp.como(u.g, $q$INSERT INTO public.funcionarios (nome, re, cpf, cargo, turno) VALUES ('NOVO PONTUADO', 'N1', '613.012.156-35', 'ASG', 'Integral')$q$) = 'ok:1', 'insert';
  ASSERT (SELECT cpf FROM public.funcionarios WHERE re = 'N1') = '61301215635', 'insert normalizado';
  r := pg_temp.como(u.g, $q$INSERT INTO public.funcionarios (nome, re, cpf, cargo, turno) VALUES ('NOVO RUIM', 'N2', '12345678900', 'ASG', 'Integral')$q$);
  ASSERT r LIKE 'P0001 CPF_INVALIDO%', 'insert inválido: ' || r;
  BEGIN
    UPDATE public.funcionarios SET cpf = '61301316903' WHERE id = pg_temp.f(9);
    RAISE EXCEPTION 'FALHA: postgres alterou CPF sem justificativa';
  EXCEPTION WHEN raise_exception THEN ASSERT SQLERRM LIKE 'CPF_JUSTIFICATIVA%', SQLERRM; END;
END $$;

-- ---------------------------------------------------------------- empresa obrigatória e primeira importação
DO $$
DECLARE u record; r text; v uuid;
BEGIN
  SELECT * INTO u FROM _u;
  r := pg_temp.como(u.g, format('SELECT public.conferencia_criar(%L::jsonb, %L::jsonb, %L::jsonb)', '{"nome":"x.xlsx"}', '{}', '[]'));
  ASSERT r LIKE 'P0001 CONFERENCIA_EMPRESA%', 'sem empresa: ' || r;
  r := pg_temp.como(u.g, pg_temp.cria('EMPRESA INVENTADA', '[]'));
  ASSERT r LIKE 'P0001 CONFERENCIA_EMPRESA%', 'empresa fora da lista: ' || r;
  r := pg_temp.como(u.g, pg_temp.cria('MC REMOTA LTDA', jsonb_build_array(pg_temp.item('AUSENTE', pg_temp.f(2), NULL, 'INATIVAR'))));
  ASSERT r LIKE 'P0001 CONFERENCIA_PRIMEIRA%', 'inativar na primeira: ' || r;

  ASSERT pg_temp.como(u.g, pg_temp.cria('MC REMOTA LTDA', jsonb_build_array(
    pg_temp.item('AUSENTE', pg_temp.f(2), NULL, NULL),
    pg_temp.item('NOVO', NULL, '{"nome":"PRIMEIRO NOVO","cpf":"61301114367","re":"R50"}', 'CADASTRAR')))) = 'ok:1', 'criar primeira';
  v := pg_temp.aberta();
  ASSERT (SELECT primeira_da_empresa FROM public.conferencias WHERE id = v), 'marcada como primeira';
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_confirmar_quadro(%L, 'QUADRO COMPLETO MC REMOTA LTDA')$q$, v));
  ASSERT r LIKE 'P0001 CONFERENCIA_PRIMEIRA%', 'quadro na primeira: ' || r;
  BEGIN
    UPDATE public.conferencia_itens SET opcoes = '{INATIVAR}' WHERE conferencia_id = v AND tipo = 'AUSENTE';
    UPDATE public.conferencias SET quadro_completo_em = now() WHERE id = v;
    RAISE EXCEPTION 'FALHA: quadro completo gravado na primeira';
  EXCEPTION WHEN check_violation THEN NULL; END;

  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'APROVADA', 'CADASTRAR', NULL, '{"re":"R50","cargo":"ASG","empresa":"MC SOLUCOES E SERVICOS LTDA"}')$q$,
    pg_temp.it(NULL, 'CADASTRAR'))) = 'ok:1', 'decidir';
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_aplicar(%L, 'APLICAR 1', %s)$q$, v, pg_temp.rev() - 1));
  ASSERT r LIKE 'P0001 CONFERENCIA_ALTERADA%', 'revisão antiga: ' || r;
  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_aplicar(%L, 'APLICAR 1', %s)$q$, v, pg_temp.rev())) = 'ok:1', 'aplicar';
  ASSERT (SELECT empresa = 'MC REMOTA LTDA' FROM public.funcionarios WHERE re = 'R50'), 'empresa vem da importação, não do pedido';
  ASSERT (SELECT conferencia_id = v AND validada_por = u.g FROM public.importacao_empresas WHERE empresa = 'MC REMOTA LTDA'), 'primeira registrada';
  ASSERT (SELECT status FROM public.funcionarios WHERE id = pg_temp.f(2)) = 'ativo', 'ausente da primeira continua ativo';

  -- concluir sem alterações também valida a primeira importação
  ASSERT pg_temp.como(u.g, pg_temp.cria('M C SERVICOS GERAIS LTDA', jsonb_build_array(pg_temp.item('AUSENTE', pg_temp.f(4), NULL, NULL)))) = 'ok:1', 'criar outra';
  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_aplicar(%L, 'APLICAR 0', %s)$q$, pg_temp.aberta(), pg_temp.rev())) = 'ok:1', 'aplicar zero';
  ASSERT EXISTS (SELECT 1 FROM public.importacao_empresas WHERE empresa = 'M C SERVICOS GERAIS LTDA'), 'primeira registrada sem alterações';

  -- registro protegido
  ASSERT pg_temp.como(u.g, $q$INSERT INTO public.importacao_empresas (empresa, conferencia_id, validada_por) VALUES ('MC SOLUCOES E SERVICOS LTDA', gen_random_uuid(), gen_random_uuid())$q$) LIKE '42501%', 'gestor insere registro';
  ASSERT pg_temp.como(u.g, 'DELETE FROM public.importacao_empresas') LIKE '42501%', 'gestor apaga registro';
  ASSERT pg_temp.como(u.s, 'SELECT * FROM public.importacao_empresas') = 'ok:0', 'supervisor não lê registro';
  BEGIN
    DELETE FROM public.importacao_empresas;
    RAISE EXCEPTION 'FALHA: registro apagado';
  EXCEPTION WHEN raise_exception THEN ASSERT SQLERRM LIKE 'EXCLUSAO_PROIBIDA%', SQLERRM; END;
END $$;

-- ---------------------------------------------------------------- importação posterior: quadro completo, lote, ações novas
DO $$
DECLARE u record; r text; v uuid; lote uuid[]; rev int; per int;
BEGIN
  SELECT * INTO u FROM _u;
  per := (SELECT count(*) FROM public.funcionario_inatividades);
  ASSERT pg_temp.como(u.g, pg_temp.cria('MC REMOTA LTDA', jsonb_build_array(
    pg_temp.item('AUSENTE', pg_temp.f(2), NULL, 'INATIVAR'),
    pg_temp.item('AUSENTE', pg_temp.f(3), NULL, 'INATIVAR'),           -- freelancer forjado: o banco recusa na aplicação
    pg_temp.item('AUSENTE', pg_temp.f(4), NULL, 'INATIVAR'),           -- outra empresa forjada
    pg_temp.item('DIVERGENCIA_RE', pg_temp.f(5), '{"nome":"RE OCUPADO","cpf":"***","re":"R6"}', 'CORRIGIR_RE'),
    pg_temp.item('DIVERGENCIA_RE', pg_temp.f(7), '{"nome":"TROCA RE","cpf":"***","re":"R70"}', 'CORRIGIR_RE'),
    pg_temp.item('DIVERGENCIA_EMPRESA', pg_temp.f(8), '{"nome":"TRANSFERIDO","cpf":"***","re":"R80"}', 'CORRIGIR_EMPRESA'),
    pg_temp.item('DIVERGENCIA_NOME', pg_temp.f(9), '{"nome":"NOME E CARGO SILVA","cpf":"***","re":"R9"}', 'ATUALIZAR_NOME'),
    pg_temp.item('DIVERGENCIA_CARGO', pg_temp.f(9), '{"nome":"NOME E CARGO","cpf":"***","re":"R9","cargo_sistema":"Porteiro"}', 'ATUALIZAR_CARGO')))) = 'ok:1', 'criar posterior';
  v := pg_temp.aberta();
  ASSERT (SELECT NOT primeira_da_empresa FROM public.conferencias WHERE id = v), 'posterior';
  INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por) VALUES
   ('cc000000-0000-0000-0000-000000000002', pg_temp.f(2), current_date + 5, 'Falta', 'cb000000-0000-0000-0000-000000000001');
  UPDATE _foto SET ft = (SELECT md5(string_agg(t::text, '|' ORDER BY id)) FROM public.ft t), hist = (SELECT md5(string_agg(h::text, '|' ORDER BY id)) FROM public.ft_historico h);

  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'APROVADA', 'INATIVAR', 'Desligado conforme relacao oficial')$q$, pg_temp.it(pg_temp.f(2), 'INATIVAR')));
  ASSERT r LIKE 'P0001 CONFERENCIA_QUADRO%', 'inativar sem quadro: ' || r;
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_inativar_lote(%L, %L, 'Desligados conforme relacao oficial', 'INATIVAR 1 MC REMOTA LTDA')$q$, v, ARRAY[pg_temp.it(pg_temp.f(2), 'INATIVAR')]));
  ASSERT r LIKE 'P0001 CONFERENCIA_QUADRO%', 'lote sem quadro: ' || r;
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_confirmar_quadro(%L, 'QUADRO COMPLETO')$q$, v));
  ASSERT r LIKE 'P0001 CONFERENCIA_CONFIRMACAO%', 'quadro sem empresa: ' || r;
  r := pg_temp.como(u.s, format($q$SELECT public.conferencia_confirmar_quadro(%L, 'QUADRO COMPLETO MC REMOTA LTDA')$q$, v));
  ASSERT r LIKE 'P0001 PERMISSAO%', 'supervisor confirma: ' || r;
  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_confirmar_quadro(%L, 'QUADRO COMPLETO MC REMOTA LTDA')$q$, v)) = 'ok:1', 'quadro';
  ASSERT (SELECT quadro_completo_por = u.g FROM public.conferencias WHERE id = v), 'quem confirmou';
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'APROVADA', 'INATIVAR', 'curto')$q$, pg_temp.it(pg_temp.f(2), 'INATIVAR')));
  ASSERT r LIKE 'P0001 CONFERENCIA_JUSTIFICATIVA%', 'inativar sem justificativa: ' || r;

  lote := ARRAY[pg_temp.it(pg_temp.f(2), 'INATIVAR'), pg_temp.it(pg_temp.f(3), 'INATIVAR'), pg_temp.it(pg_temp.f(4), 'INATIVAR')];
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_inativar_lote(%L, %L, 'Desligados conforme relacao oficial', 'INATIVAR 3')$q$, v, lote));
  ASSERT r LIKE 'P0001 CONFERENCIA_CONFIRMACAO%', 'lote sem empresa: ' || r;
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_inativar_lote(%L, %L, 'Desligados conforme relacao oficial', 'INATIVAR 4 MC REMOTA LTDA')$q$, v,
    lote || pg_temp.it(pg_temp.f(9), 'ATUALIZAR_NOME')));
  ASSERT r LIKE 'P0001 CONFERENCIA_ACAO%', 'lote com item que não é ausente: ' || r;
  r := pg_temp.como(u.s, format($q$SELECT public.conferencia_inativar_lote(%L, %L, 'Desligados conforme relacao oficial', 'INATIVAR 3 MC REMOTA LTDA')$q$, v, lote));
  ASSERT r LIKE 'P0001 PERMISSAO%', 'supervisor em lote: ' || r;
  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_inativar_lote(%L, %L, 'Desligados conforme relacao oficial', 'INATIVAR 3 MC REMOTA LTDA')$q$, v, lote)) = 'ok:1', 'lote';
  ASSERT (SELECT count(*) FROM public.audit_logs WHERE action = 'CONFERENCIA_DECISAO' AND entity_id = ANY (SELECT unnest(lote)::text) AND (new_data->>'lote')::int = 3) = 3, 'auditoria por item';
  ASSERT (SELECT count(*) FROM public.funcionarios WHERE status = 'inativo' AND id IN (pg_temp.f(2), pg_temp.f(3), pg_temp.f(4))) = 0, 'lote não aplica';

  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'APROVADA', 'CORRIGIR_RE')$q$, pg_temp.it(pg_temp.f(5), 'CORRIGIR_RE')));
  ASSERT r LIKE 'P0001 CONFERENCIA_JUSTIFICATIVA%', 'corrigir RE sem justificativa: ' || r;
  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'APROVADA', 'CORRIGIR_RE', 'RE alterado pelo departamento pessoal')$q$, pg_temp.it(pg_temp.f(5), 'CORRIGIR_RE'))) = 'ok:1', 'RE ocupado';
  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'APROVADA', 'CORRIGIR_RE', 'RE alterado pelo departamento pessoal')$q$, pg_temp.it(pg_temp.f(7), 'CORRIGIR_RE'))) = 'ok:1', 'RE livre';
  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'APROVADA', 'CORRIGIR_EMPRESA', 'Transferido entre empresas do grupo')$q$, pg_temp.it(pg_temp.f(8), 'CORRIGIR_EMPRESA'))) = 'ok:1', 'empresa';
  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'APROVADA', 'ATUALIZAR_NOME')$q$, pg_temp.it(pg_temp.f(9), 'ATUALIZAR_NOME'))) = 'ok:1', 'nome';
  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'APROVADA', 'ATUALIZAR_CARGO')$q$, pg_temp.it(pg_temp.f(9), 'ATUALIZAR_CARGO'))) = 'ok:1', 'cargo';

  rev := pg_temp.rev();
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_aplicar(%L, 'APLICAR 8', %s)$q$, v, rev));
  ASSERT r = 'ok:1', 'aplicar: ' || r;
  ASSERT (SELECT status = 'inativo' AND data_inativacao IS NOT NULL FROM public.funcionarios WHERE id = pg_temp.f(2)), 'ausente inativado';
  ASSERT (SELECT count(*) FROM public.funcionario_inatividades) = per + 1, 'regra 1A: um período criado';
  ASSERT (SELECT resultado_detalhe FROM public.conferencia_itens WHERE conferencia_id = v AND funcionario_id = pg_temp.f(3)) LIKE 'Freelancer%', 'freelancer recusado';
  ASSERT (SELECT resultado_detalhe FROM public.conferencia_itens WHERE conferencia_id = v AND funcionario_id = pg_temp.f(4)) LIKE '%não pertence%', 'outra empresa recusada';
  ASSERT (SELECT status FROM public.funcionarios WHERE id = pg_temp.f(3)) = 'ativo' AND (SELECT status FROM public.funcionarios WHERE id = pg_temp.f(4)) = 'ativo', 'não inativados';
  ASSERT (SELECT re FROM public.funcionarios WHERE id = pg_temp.f(5)) = 'R5', 'RE ocupado não aplicado';
  ASSERT (SELECT resultado_detalhe FROM public.conferencia_itens WHERE conferencia_id = v AND funcionario_id = pg_temp.f(5)) LIKE 'RE já usado%', 'conflito de RE';
  ASSERT (SELECT re FROM public.funcionarios WHERE id = pg_temp.f(7)) = 'R70', 'RE corrigido';
  ASSERT (SELECT re = 'R80' AND empresa = 'MC REMOTA LTDA' FROM public.funcionarios WHERE id = pg_temp.f(8)), 'transferência';
  ASSERT (SELECT nome = 'NOME E CARGO SILVA' AND cargo = 'Porteiro' FROM public.funcionarios WHERE id = pg_temp.f(9)), 'dois itens do mesmo cadastro aplicados';
  ASSERT (SELECT ft FROM _foto) = (SELECT md5(string_agg(t::text, '|' ORDER BY id)) FROM public.ft t), 'FTs idênticas';
  ASSERT (SELECT hist FROM _foto) = (SELECT md5(string_agg(h::text, '|' ORDER BY id)) FROM public.ft_historico h), 'histórico idêntico';
  ASSERT (SELECT count(*) FROM public.audit_logs WHERE action = 'CONFERENCIA_ITEM_APLICADO' AND new_data->>'conferencia_id' = v::text) = 5, 'itens aplicados auditados';
END $$;

-- ---------------------------------------------------------------- revisão: decisão mudada depois da tela carregada
DO $$
DECLARE u record; r text; v uuid; rev int;
BEGIN
  SELECT * INTO u FROM _u;
  ASSERT pg_temp.como(u.g, pg_temp.cria('MC REMOTA LTDA', jsonb_build_array(
    pg_temp.item('DIVERGENCIA_NOME', pg_temp.f(6), '{"nome":"DONO R6 NETO","cpf":"***","re":"R6"}', 'ATUALIZAR_NOME')))) = 'ok:1', 'criar';
  v := pg_temp.aberta(); rev := pg_temp.rev();
  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'APROVADA', 'ATUALIZAR_NOME')$q$, pg_temp.it(pg_temp.f(6), 'ATUALIZAR_NOME'))) = 'ok:1', 'outra aba aprova';
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_aplicar(%L, 'APLICAR 0', %s)$q$, v, rev));
  ASSERT r LIKE 'P0001 CONFERENCIA_ALTERADA%', 'aplicação com tela antiga: ' || r;
  ASSERT (SELECT nome FROM public.funcionarios WHERE id = pg_temp.f(6)) = 'DONO R6', 'nada aplicado';

  -- expiração: aberta há mais de 7 dias não aceita nenhuma ação, mesmo sem outra importação ser criada
  UPDATE public.conferencias SET criada_em = now() - interval '8 days' WHERE id = v;
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'REJEITADA')$q$, pg_temp.it(pg_temp.f(6), 'ATUALIZAR_NOME')));
  ASSERT r LIKE 'P0001 CONFERENCIA_EXPIRADA%', 'decidir expirada: ' || r;
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_confirmar_quadro(%L, 'QUADRO COMPLETO MC REMOTA LTDA')$q$, v));
  ASSERT r LIKE 'P0001 CONFERENCIA_EXPIRADA%', 'quadro expirada: ' || r;
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_inativar_lote(%L, %L, 'Desligados conforme relacao oficial', 'INATIVAR 1 MC REMOTA LTDA')$q$, v, ARRAY[gen_random_uuid()]));
  ASSERT r LIKE 'P0001 CONFERENCIA_EXPIRADA%', 'lote expirada: ' || r;
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_aplicar(%L, 'APLICAR 1', %s)$q$, v, pg_temp.rev()));
  ASSERT r LIKE 'P0001 CONFERENCIA_EXPIRADA%', 'aplicar expirada: ' || r;
  ASSERT (SELECT nome FROM public.funcionarios WHERE id = pg_temp.f(6)) = 'DONO R6', 'expirada não aplicou';
  -- e é descartada e mascarada ao criar a próxima
  UPDATE public.conferencia_itens SET folha = jsonb_set(folha, '{cpf}', '"61300607858"') WHERE conferencia_id = v;
  ASSERT pg_temp.como(u.g, pg_temp.cria('MC REMOTA LTDA', '[]')) = 'ok:1', 'nova após expirar';
  ASSERT (SELECT status = 'DESCARTADA' AND motivo_descarte LIKE 'Expirada%' FROM public.conferencias WHERE id = v), 'expirada';
  ASSERT NOT EXISTS (SELECT 1 FROM public.conferencia_itens WHERE conferencia_id = v AND folha->>'cpf' ~ '^[0-9]{11}$'), 'expirada mascarada';
  ASSERT EXISTS (SELECT 1 FROM public.audit_logs WHERE action = 'CONFERENCIA_EXPIRADA' AND entity_id = v::text), 'expiração auditada';
END $$;

-- ---------------------------------------------------------------- cargo alterado depois da leitura vira conflito
DO $$
DECLARE u record; r text; v uuid;
BEGIN
  SELECT * INTO u FROM _u;
  UPDATE public.conferencias SET status = 'DESCARTADA', encerrada_em = now() WHERE status = 'ABERTA';
  ASSERT pg_temp.como(u.g, pg_temp.cria('MC REMOTA LTDA', jsonb_build_array(
    pg_temp.item('DIVERGENCIA_CARGO', pg_temp.f(6), '{"nome":"DONO R6","cpf":"***","re":"R6","cargo_sistema":"Vigilante"}', 'ATUALIZAR_CARGO')))) = 'ok:1', 'criar';
  v := pg_temp.aberta();
  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'APROVADA', 'ATUALIZAR_CARGO')$q$, pg_temp.it(pg_temp.f(6), 'ATUALIZAR_CARGO'))) = 'ok:1', 'decidir';
  UPDATE public.funcionarios SET cargo = 'ASG' WHERE id = pg_temp.f(6);
  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_aplicar(%L, 'APLICAR 1', %s)$q$, v, pg_temp.rev())) = 'ok:1', 'aplicar';
  ASSERT (SELECT cargo FROM public.funcionarios WHERE id = pg_temp.f(6)) = 'ASG', 'cargo alterado por fora não pode ser sobrescrito';
  ASSERT (SELECT resultado FROM public.conferencia_itens WHERE conferencia_id = v) = 'CONFLITO', 'conflito de cargo';
END $$;

-- ---------------------------------------------------------------- freelancer: cargo mudado depois da leitura não inativa; troca de/para Freelancer exige justificativa
DO $$
DECLARE u record; r text; v uuid;
BEGIN
  SELECT * INTO u FROM _u;
  UPDATE public.conferencias SET status = 'DESCARTADA', encerrada_em = now() WHERE status = 'ABERTA';
  ASSERT pg_temp.como(u.g, pg_temp.cria('MC REMOTA LTDA', jsonb_build_array(
    pg_temp.item('AUSENTE', pg_temp.f(1), NULL, 'INATIVAR'),
    pg_temp.item('AUSENTE', pg_temp.f(6), NULL, 'INATIVAR'),
    pg_temp.item('DIVERGENCIA_CARGO', pg_temp.f(5), '{"nome":"RE OCUPADO","cpf":"***","re":"R5","cargo_sistema":"Freelancer"}', 'ATUALIZAR_CARGO')))) = 'ok:1', 'criar';
  v := pg_temp.aberta();
  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_confirmar_quadro(%L, 'QUADRO COMPLETO MC REMOTA LTDA')$q$, v)) = 'ok:1', 'quadro';
  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_inativar_lote(%L, %L, 'Desligados conforme relacao oficial', 'INATIVAR 2 MC REMOTA LTDA')$q$, v,
    ARRAY[pg_temp.it(pg_temp.f(1), 'INATIVAR'), pg_temp.it(pg_temp.f(6), 'INATIVAR')])) = 'ok:1', 'lote';
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'APROVADA', 'ATUALIZAR_CARGO')$q$, pg_temp.it(pg_temp.f(5), 'ATUALIZAR_CARGO')));
  ASSERT r LIKE 'P0001 CONFERENCIA_JUSTIFICATIVA%', 'virar Freelancer sem justificativa: ' || r;
  -- depois da revisão, o cadastro muda: um vira Freelancer, outro muda de cargo
  UPDATE public.funcionarios SET cargo = 'Freelancer' WHERE id = pg_temp.f(1);
  UPDATE public.funcionarios SET cargo = 'Vigilante' WHERE id = pg_temp.f(6);
  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_aplicar(%L, 'APLICAR 2', %s)$q$, v, pg_temp.rev())) = 'ok:1', 'aplicar';
  ASSERT (SELECT count(*) FROM public.funcionarios WHERE id IN (pg_temp.f(1), pg_temp.f(6)) AND status = 'ativo') = 2, 'nenhum inativado';
  ASSERT (SELECT count(*) FROM public.conferencia_itens WHERE conferencia_id = v AND resultado = 'CONFLITO') = 2, 'dois conflitos';
END $$;

-- ---------------------------------------------------------------- auditoria genérica: CPF mascarado, troca rastreável
DO $$
DECLARE u record; v_id uuid;
BEGIN
  SELECT * INTO u FROM _u;
  ASSERT pg_temp.como(u.g, $q$INSERT INTO public.funcionarios (nome, re, cpf, cargo, turno) VALUES ('AUDITADO', 'AU1', '61301417343', 'ASG', 'Integral')$q$) = 'ok:1', 'insert';
  v_id := (SELECT id FROM public.funcionarios WHERE re = 'AU1');
  ASSERT pg_temp.como(u.g, format($q$SELECT public.funcionario_alterar_cpf(%L, '61301518450', 'Corrigido conforme documento')$q$, v_id)) = 'ok:1', 'alterar';
  ASSERT pg_temp.como(u.g, format($q$UPDATE public.funcionarios SET nome = 'AUDITADO SILVA' WHERE id = %L$q$, v_id)) = 'ok:1', 'nome';
  ASSERT NOT EXISTS (SELECT 1 FROM public.audit_logs WHERE entity_type = 'funcionarios' AND (old_data->>'cpf' ~ '[0-9]{11}' OR new_data->>'cpf' ~ '[0-9]{11}')),
    'CPF aberto em audit_logs de funcionarios';
  ASSERT (SELECT new_data->>'cpf' = '***.014.173-**' FROM public.audit_logs WHERE action = 'INSERT' AND entity_id = v_id::text), 'insert mascarado';
  ASSERT (SELECT (new_data->>'cpf_alterado')::boolean AND old_data->>'cpf' = '***.014.173-**' AND new_data->>'cpf' = '***.015.184-**'
            FROM public.audit_logs WHERE action = 'UPDATE' AND entity_id = v_id::text AND new_data ? 'cpf_alterado'), 'troca rastreável';
  ASSERT (SELECT count(*) FROM public.audit_logs WHERE action = 'UPDATE' AND entity_id = v_id::text AND NOT new_data ? 'cpf_alterado') = 1, 'troca de nome sem marca de CPF';
END $$;

ROLLBACK;
