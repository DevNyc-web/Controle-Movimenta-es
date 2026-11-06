-- TESTE LOCAL — NÃO RODAR EM PRODUÇÃO. Execução: bash supabase/tests/rodar_local.sh (Postgres descartável; dados fictícios).
-- Permissões, revisão, aplicação, conflito, retenção de CPF e, principalmente: a Conferência nunca inativa nem apaga.

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
DECLARE r text;
BEGIN
  PERFORM set_config('role', p_role, true);
  BEGIN EXECUTE p_sql; r := 'ok';
  EXCEPTION WHEN OTHERS THEN r := SQLSTATE || ' ' || SQLERRM; END;
  PERFORM set_config('role', 'postgres', true);
  RETURN r;
END $$;

CREATE FUNCTION pg_temp.f(i int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT ('c9000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid $$;
-- item no formato que o servidor envia
CREATE FUNCTION pg_temp.item(p_tipo text, p_f uuid, p_nome text, p_cpf text, p_atual jsonb, p_acao text, p_opcoes text[] DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('tipo', p_tipo, 'funcionario_id', p_f, 'folha', jsonb_build_object('nome', p_nome, 'cpf', p_cpf, 'admissao', '2024-02-01'),
    'atual', p_atual, 'acao', p_acao, 'opcoes', to_jsonb(coalesce(p_opcoes, CASE WHEN p_acao IS NULL THEN '{}'::text[] ELSE ARRAY[p_acao] END)), 'motivo', 'teste', 'origens', jsonb_build_array('Folha:2'))
$$;
CREATE FUNCTION pg_temp.atual(p_f uuid) RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_build_object('nome', nome, 'cpf', cpf, 'status', status) FROM public.funcionarios WHERE id = p_f $$;
CREATE FUNCTION pg_temp.cria(p_u uuid, p_itens jsonb) RETURNS text LANGUAGE sql AS $$
  SELECT format('SELECT public.conferencia_criar(%L::jsonb, %L::jsonb, %L::jsonb)', '{"nome":"folha.xlsx","abas":["Folha"],"ignoradas":3}', '{"total_folha":5}', p_itens)
$$;

INSERT INTO auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
SELECT '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.n || '@teste.local', jsonb_build_object('username', u.n, 'nome', u.n, 'role', u.r), now(), now()
FROM (VALUES
 ('c8000000-0000-0000-0000-000000000001'::uuid, 'cg', 'gestor'), ('c8000000-0000-0000-0000-000000000002'::uuid, 'cs', 'supervisor'),
 ('c8000000-0000-0000-0000-000000000003'::uuid, 'ca', 'admin'), ('c8000000-0000-0000-0000-000000000004'::uuid, 'cp', 'apontamento'),
 ('c8000000-0000-0000-0000-000000000005'::uuid, 'cd', 'gestor')) u(id, n, r);
UPDATE public.profiles SET ativo = false WHERE username = 'cd';

INSERT INTO public.funcionarios (id, nome, re, cpf, cargo, turno) VALUES
 (pg_temp.f(1), 'NOME ANTIGO SILVA', 'C-1', '11144477735', 'Porteiro', 'Integral'),   -- atualizar nome
 (pg_temp.f(2), 'SEM CPF AINDA',     'C-2', NULL,          'Porteiro', 'Integral'),   -- preencher
 (pg_temp.f(3), 'CPF ERRADO',        'C-3', '52998224725', 'Porteiro', 'Integral'),   -- corrigir
 (pg_temp.f(4), 'VOLTOU A FOLHA',    'C-4', '39053344705', 'Porteiro', 'Integral'),   -- reativar
 (pg_temp.f(5), 'AUSENTE DA FOLHA',  'C-5', '71428793860', 'Porteiro', 'Integral'),   -- ausente
 (pg_temp.f(6), 'MUDA ANTES',        'C-6', '45317828791', 'Porteiro', 'Integral'),   -- conflito
 (pg_temp.f(7), 'DONO DO CPF',       'C-7', '862.883.667-57', 'Porteiro', 'Integral');
UPDATE public.funcionarios SET status = 'inativo' WHERE id = pg_temp.f(4);
INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por, status, aprovado_por) VALUES
 ('c7000000-0000-0000-0000-000000000001', pg_temp.f(1), DATE '2026-01-05', 'Falta', 'c8000000-0000-0000-0000-000000000001', 'APROVADA', 'c8000000-0000-0000-0000-000000000001'),
 ('c7000000-0000-0000-0000-000000000002', pg_temp.f(3), DATE '2026-01-06', 'Falta', 'c8000000-0000-0000-0000-000000000001', 'APROVADA', 'c8000000-0000-0000-0000-000000000001');
CREATE TEMP TABLE _foto ON COMMIT DROP AS
  SELECT (SELECT md5(string_agg(t::text, '|' ORDER BY id)) FROM public.ft t) ft, (SELECT md5(string_agg(h::text, '|' ORDER BY id)) FROM public.ft_historico h) hist,
         (SELECT count(*) FROM public.funcionarios) funcs, (SELECT count(*) FROM public.funcionario_inatividades) periodos;
GRANT SELECT ON _foto TO PUBLIC;

CREATE TEMP TABLE _u ON COMMIT DROP AS SELECT 'c8000000-0000-0000-0000-000000000001'::uuid g, 'c8000000-0000-0000-0000-000000000002'::uuid s,
  'c8000000-0000-0000-0000-000000000003'::uuid ad, 'c8000000-0000-0000-0000-000000000004'::uuid ap, 'c8000000-0000-0000-0000-000000000005'::uuid gd;
GRANT SELECT ON _u TO PUBLIC;
CREATE TEMP TABLE _c (id uuid) ON COMMIT DROP;

-- ---------------------------------------------------------------- funções internas e cpf
DO $$ BEGIN
  ASSERT public.cpf_valido('11144477735'), 'cpf válido';
  ASSERT NOT public.cpf_valido('11144477736'), 'dígito';
  ASSERT NOT public.cpf_valido('11111111111'), 'repetido';
  ASSERT NOT public.cpf_valido(NULL), 'nulo';
  ASSERT public.cpf_mascarado('11144477735') = '***.444.777-**', 'máscara';
  ASSERT public.cpf_mascarado('111.444.777-35') = '***.444.777-**', 'máscara com pontuação';
  ASSERT public.cpf_mascarado('123') = '***', 'incompleto não sai aberto';
  ASSERT public.cpf_mascarado('***.444.777-**') = '***.444.777-**', 'já mascarado';
  ASSERT public.cpf_digitos('1234567890') = '01234567890' AND public.cpf_digitos('') IS NULL, 'dígitos';
  ASSERT public.cpf_digitos('123456789012') = '123456789012', 'mais de 11 dígitos não é cortado';
  ASSERT public.cpf_mascarado('***.444.777-**') = '***.444.777-**', 'máscara é idempotente';
END $$;

-- ---------------------------------------------------------------- permissões
DO $$
DECLARE u record; r text; x text; sql_cria text;
BEGIN
  SELECT * INTO u FROM _u;
  sql_cria := pg_temp.cria(u.g, '[]');
  FOREACH x IN ARRAY ARRAY[u.s::text, u.ad::text, u.ap::text, u.gd::text] LOOP
    r := pg_temp.como(x::uuid, sql_cria);
    ASSERT r LIKE 'P0001 PERMISSAO%', 'criar: ' || x || ' ' || r;
    r := pg_temp.como(x::uuid, $q$SELECT public.conferencia_aplicar('00000000-0000-0000-0000-000000000000', 'APLICAR 1')$q$);
    ASSERT r LIKE 'P0001 PERMISSAO%', 'aplicar: ' || r;
    r := pg_temp.como(x::uuid, $q$SELECT public.conferencia_decidir('00000000-0000-0000-0000-000000000000', 'APROVADA')$q$);
    ASSERT r LIKE 'P0001 PERMISSAO%', 'decidir: ' || r;
    r := pg_temp.como(x::uuid, $q$SELECT public.conferencia_descartar('00000000-0000-0000-0000-000000000000', 'motivo longo o bastante')$q$);
    ASSERT r LIKE 'P0001 PERMISSAO%', 'descartar: ' || r;
  END LOOP;
  r := pg_temp.como(u.s, sql_cria, '{"role":"gestor"}');
  ASSERT r LIKE 'P0001 PERMISSAO%', 'metadata não dá perfil: ' || r;
  r := pg_temp.como_role('anon', sql_cria);
  ASSERT r LIKE '42501%', 'anon: ' || r;
  r := pg_temp.como_role('service_role', sql_cria);
  ASSERT r LIKE '42501%', 'service_role: ' || r;
  r := pg_temp.como(u.g, $q$INSERT INTO public.conferencias (arquivo_nome, resumo, criada_por) VALUES ('x', '{}', gen_random_uuid())$q$);
  ASSERT r LIKE '42501%', 'insert direto: ' || r;
  r := pg_temp.como(u.g, $q$UPDATE public.conferencia_itens SET decisao = 'APROVADA'$q$);
  ASSERT r LIKE '42501%', 'update direto: ' || r;
  r := pg_temp.como(u.g, 'DELETE FROM public.conferencias');
  ASSERT r LIKE '42501%', 'delete: ' || r;
  r := pg_temp.como(u.g, $q$SELECT public.cpf_mascarado('11144477735')$q$);
  ASSERT r LIKE '42501%', 'função interna: ' || r;
  r := pg_temp.como(u.g, $q$SELECT public.conferencia_mascarar_itens('00000000-0000-0000-0000-000000000000')$q$);
  ASSERT r LIKE '42501%', 'mascarar interno: ' || r;
END $$;

-- ---------------------------------------------------------------- criar não toca em funcionários; uma aberta por vez
DO $$
DECLARE u record; r text; v_id uuid; itens jsonb; antes text;
BEGIN
  SELECT * INTO u FROM _u;
  itens := jsonb_build_array(
    pg_temp.item('DIVERGENCIA_NOME', pg_temp.f(1), 'NOME NOVO SILVA', '11144477735', pg_temp.atual(pg_temp.f(1)), 'ATUALIZAR_NOME'),
    pg_temp.item('PENDENCIA', pg_temp.f(2), 'SEM CPF AINDA', '98765432101', pg_temp.atual(pg_temp.f(2)), 'PREENCHER_CPF'),
    pg_temp.item('DIVERGENCIA_CPF', pg_temp.f(3), 'CPF ERRADO', '12345678909', pg_temp.atual(pg_temp.f(3)), 'CORRIGIR_CPF'),
    pg_temp.item('INATIVO', pg_temp.f(4), 'VOLTOU A FOLHA', '39053344705', pg_temp.atual(pg_temp.f(4)), 'REATIVAR'),
    pg_temp.item('AUSENTE', pg_temp.f(5), '', NULL, pg_temp.atual(pg_temp.f(5)), NULL),
    pg_temp.item('DIVERGENCIA_NOME', pg_temp.f(6), 'MUDA ANTES NETO', '45317828791', pg_temp.atual(pg_temp.f(6)), 'ATUALIZAR_NOME'),
    pg_temp.item('NOVO', NULL, 'PESSOA NOVA', '15350946056', NULL, 'CADASTRAR'),
    pg_temp.item('CORRESPONDENTE', pg_temp.f(7), 'DONO DO CPF', '***.883.667-**', NULL, NULL),
    pg_temp.item('NOVO', NULL, 'CPF JA TEM DONO', '86288366757', NULL, 'CADASTRAR')
  );
  antes := (SELECT md5(string_agg(x::text, '|' ORDER BY id)) FROM public.funcionarios x);
  r := pg_temp.como(u.g, pg_temp.cria(u.g, itens));
  ASSERT r = 'ok:1', 'criar: ' || r;
  SELECT id INTO v_id FROM public.conferencias WHERE status = 'ABERTA';
  INSERT INTO _c VALUES (v_id);
  ASSERT antes = (SELECT md5(string_agg(x::text, '|' ORDER BY id)) FROM public.funcionarios x), 'criar não altera funcionários';
  ASSERT (SELECT count(*) FROM public.conferencia_itens WHERE conferencia_id = v_id) = 9, 'itens';
  ASSERT (SELECT decisao FROM public.conferencia_itens WHERE conferencia_id = v_id AND tipo = 'CORRESPONDENTE') = 'SEM_ACAO', 'correspondente';
  ASSERT EXISTS (SELECT 1 FROM public.audit_logs WHERE action = 'CONFERENCIA_CRIADA' AND entity_id = v_id::text AND user_id = u.g), 'auditoria';

  r := pg_temp.como(u.g, pg_temp.cria(u.g, '[]'));
  ASSERT r LIKE 'P0001 CONFERENCIA_ABERTA%', 'uma por vez: ' || r;

  -- leitura só para Gestor
  ASSERT pg_temp.como(u.g, 'SELECT id FROM public.conferencia_itens') = 'ok:9', 'gestor lê';
  ASSERT pg_temp.como(u.s, 'SELECT id FROM public.conferencia_itens') = 'ok:0', 'supervisor não lê';
  ASSERT pg_temp.como(u.ad, 'SELECT id FROM public.conferencias') = 'ok:0', 'admin não lê';
  ASSERT pg_temp.como(u.gd, 'SELECT id FROM public.conferencias') = 'ok:0', 'gestor desativado não lê';

  -- ausente não aceita ação, nem forjada na criação
  BEGIN
    UPDATE public.conferencia_itens SET opcoes = '{REATIVAR}' WHERE conferencia_id = v_id AND tipo = 'AUSENTE';
    RAISE EXCEPTION 'FALHA: ausente com ação';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    UPDATE public.conferencia_itens SET opcoes = '{INATIVAR}' WHERE conferencia_id = v_id AND tipo = 'NOVO';
    RAISE EXCEPTION 'FALHA: ação inativar aceita';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;

-- ---------------------------------------------------------------- decidir
DO $$
DECLARE u record; r text; v_id uuid; n uuid; d uuid; c uuid; a uuid; aus uuid; re uuid; x uuid; dono uuid; corr uuid;
  decide text := 'SELECT public.conferencia_decidir(%L, %L, %L, %L, %L::jsonb)';
BEGIN
  SELECT * INTO u FROM _u; SELECT id INTO v_id FROM _c;
  SELECT id INTO n FROM public.conferencia_itens WHERE conferencia_id = v_id AND funcionario_id = pg_temp.f(1);
  SELECT id INTO d FROM public.conferencia_itens WHERE conferencia_id = v_id AND funcionario_id = pg_temp.f(2);
  SELECT id INTO c FROM public.conferencia_itens WHERE conferencia_id = v_id AND funcionario_id = pg_temp.f(3);
  SELECT id INTO re FROM public.conferencia_itens WHERE conferencia_id = v_id AND funcionario_id = pg_temp.f(4);
  SELECT id INTO aus FROM public.conferencia_itens WHERE conferencia_id = v_id AND funcionario_id = pg_temp.f(5);
  SELECT id INTO x FROM public.conferencia_itens WHERE conferencia_id = v_id AND funcionario_id = pg_temp.f(6);
  SELECT id INTO a FROM public.conferencia_itens WHERE conferencia_id = v_id AND folha->>'nome' = 'PESSOA NOVA';
  SELECT id INTO dono FROM public.conferencia_itens WHERE conferencia_id = v_id AND folha->>'nome' = 'CPF JA TEM DONO';
  SELECT id INTO corr FROM public.conferencia_itens WHERE conferencia_id = v_id AND tipo = 'CORRESPONDENTE';

  r := pg_temp.como(u.g, format(decide, aus, 'APROVADA', 'REATIVAR', 'motivo longo o bastante', NULL));
  ASSERT r LIKE 'P0001 CONFERENCIA_ACAO%', 'ausente não aprova ação: ' || r;
  r := pg_temp.como(u.g, format(decide, aus, 'APROVADA', 'INATIVAR', 'motivo longo o bastante', NULL));
  ASSERT r LIKE 'P0001 CONFERENCIA_ACAO%', 'inativar não existe: ' || r;
  ASSERT pg_temp.como(u.g, format(decide, aus, 'REVISADA', NULL, NULL, NULL)) = 'ok:1', 'ausente marcado como revisado';

  r := pg_temp.como(u.g, format(decide, corr, 'APROVADA', 'ATUALIZAR_NOME', NULL, NULL));
  ASSERT r LIKE 'P0001 CONFERENCIA_ESTADO%', 'correspondente: ' || r;
  r := pg_temp.como(u.g, format(decide, n, 'APROVADA', 'CORRIGIR_CPF', 'motivo longo o bastante', NULL));
  ASSERT r LIKE 'P0001 CONFERENCIA_ACAO%', 'ação de outro tipo: ' || r;
  r := pg_temp.como(u.g, format(decide, n, 'TALVEZ', NULL, NULL, NULL));
  ASSERT r LIKE 'P0001 CONFERENCIA_DADOS%', 'decisão inválida: ' || r;

  -- D2
  r := pg_temp.como(u.g, format(decide, c, 'APROVADA', 'CORRIGIR_CPF', NULL, NULL));
  ASSERT r LIKE 'P0001 CONFERENCIA_JUSTIFICATIVA%', 'corrigir CPF sem justificativa: ' || r;
  r := pg_temp.como(u.g, format(decide, c, 'APROVADA', 'CORRIGIR_CPF', E'\n\n\n . . . \n', NULL));
  ASSERT r LIKE 'P0001 CONFERENCIA_JUSTIFICATIVA%', 'justificativa vazia: ' || r;
  r := pg_temp.como(u.g, format(decide, d, 'APROVADA', 'PREENCHER_CPF', 'Confirmado com o RH do posto', NULL));
  ASSERT r LIKE 'P0001 CONFERENCIA_CPF%', 'CPF inválido recusado: ' || r;
  UPDATE public.conferencia_itens SET folha = jsonb_set(folha, '{cpf}', '"11144477735"') WHERE id = d; -- passa a ser CPF de outro funcionário

  r := pg_temp.como(u.g, format(decide, re, 'APROVADA', 'REATIVAR', 'curto', NULL));
  ASSERT r LIKE 'P0001 CONFERENCIA_JUSTIFICATIVA%', 'reativar exige motivo: ' || r;

  -- novo cadastro exige RE e cargo válido
  r := pg_temp.como(u.g, format(decide, a, 'APROVADA', 'CADASTRAR', NULL, '{"cargo":"Porteiro"}'));
  ASSERT r LIKE 'P0001 CONFERENCIA_DADOS%', 'sem RE: ' || r;
  r := pg_temp.como(u.g, format(decide, a, 'APROVADA', 'CADASTRAR', NULL, '{"re":"900","cargo":"Gerente"}'));
  ASSERT r LIKE 'P0001 CONFERENCIA_DADOS%', 'cargo inválido: ' || r;

  ASSERT pg_temp.como(u.g, format(decide, n, 'APROVADA', 'ATUALIZAR_NOME', NULL, NULL)) = 'ok:1', 'aprova nome';
  ASSERT pg_temp.como(u.g, format(decide, n, 'REJEITADA', NULL, NULL, NULL)) = 'ok:1', 'muda de ideia';
  ASSERT pg_temp.como(u.g, format(decide, n, 'APROVADA', 'ATUALIZAR_NOME', NULL, NULL)) = 'ok:1', 'aprova de novo';
  ASSERT (SELECT decidido_por = u.g FROM public.conferencia_itens WHERE id = n), 'autor';
  ASSERT (SELECT count(*) FROM public.audit_logs WHERE action = 'CONFERENCIA_DECISAO' AND entity_id = n::text) = 3, 'trilha de decisões';
  ASSERT pg_temp.como(u.g, format(decide, d, 'APROVADA', 'PREENCHER_CPF', 'Confirmado com o RH do posto', NULL)) = 'ok:1', 'preencher';
  ASSERT pg_temp.como(u.g, format(decide, c, 'APROVADA', 'CORRIGIR_CPF', 'CPF digitado errado na admissão', NULL)) = 'ok:1', 'corrigir';
  ASSERT pg_temp.como(u.g, format(decide, re, 'APROVADA', 'REATIVAR', 'Voltou ao quadro segundo a folha', NULL)) = 'ok:1', 'reativar';
  ASSERT pg_temp.como(u.g, format(decide, x, 'APROVADA', 'ATUALIZAR_NOME', NULL, NULL)) = 'ok:1', 'conflito futuro';
  ASSERT pg_temp.como(u.g, format(decide, a, 'APROVADA', 'CADASTRAR', NULL, '{"re":"900","cargo":"Porteiro","empresa":"MC REMOTA LTDA"}')) = 'ok:1', 'cadastrar';
  ASSERT pg_temp.como(u.g, format(decide, dono, 'APROVADA', 'CADASTRAR', NULL, '{"re":"901","cargo":"ASG"}')) = 'ok:1', 'cadastrar com CPF já usado';
  ASSERT (SELECT status FROM public.funcionarios WHERE id = pg_temp.f(4)) = 'inativo', 'decidir não aplica';
  ASSERT (SELECT nome FROM public.funcionarios WHERE id = pg_temp.f(1)) = 'NOME ANTIGO SILVA', 'decidir não aplica nome';
END $$;

-- cadastro muda depois da leitura
UPDATE public.funcionarios SET nome = 'ALTERADO POR OUTRO' WHERE id = pg_temp.f(6);

-- ---------------------------------------------------------------- aplicar
DO $$
DECLARE u record; r text; v_id uuid; res jsonb;
BEGIN
  SELECT * INTO u FROM _u; SELECT id INTO v_id FROM _c;
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_aplicar(%L, 'sim')$q$, v_id));
  ASSERT r LIKE 'P0001 CONFERENCIA_CONFIRMACAO%', 'confirmação errada: ' || r;
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_aplicar(%L, 'APLICAR 1')$q$, v_id));
  ASSERT r LIKE 'P0001 CONFERENCIA_CONFIRMACAO%', 'quantidade errada: ' || r;
  ASSERT (SELECT nome FROM public.funcionarios WHERE id = pg_temp.f(1)) = 'NOME ANTIGO SILVA', 'nada aplicado';

  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_aplicar(%L, 'APLICAR 7')$q$, v_id));
  ASSERT r = 'ok:1', 'aplicar: ' || r;
  SELECT resultado INTO res FROM public.conferencias WHERE id = v_id;
  ASSERT res = '{"aplicados": 4, "conflitos": 3}'::jsonb, 'resultado: ' || res::text;

  ASSERT (SELECT nome FROM public.funcionarios WHERE id = pg_temp.f(1)) = 'NOME NOVO SILVA', 'nome';
  ASSERT (SELECT cpf FROM public.funcionarios WHERE id = pg_temp.f(2)) IS NULL, 'CPF de outro funcionário não é gravado';
  ASSERT (SELECT cpf FROM public.funcionarios WHERE id = pg_temp.f(3)) = '12345678909', 'CPF corrigido';
  ASSERT (SELECT status = 'ativo' AND data_inativacao IS NULL FROM public.funcionarios WHERE id = pg_temp.f(4)), 'reativado';
  ASSERT (SELECT motivo_reativacao = 'Voltou ao quadro segundo a folha' AND fim IS NOT NULL FROM public.funcionario_inatividades WHERE funcionario_id = pg_temp.f(4)), 'regra da 1A: período encerrado com motivo';
  ASSERT (SELECT status FROM public.funcionarios WHERE id = pg_temp.f(5)) = 'ativo', 'AUSENTE CONTINUA ATIVO';
  ASSERT (SELECT nome FROM public.funcionarios WHERE id = pg_temp.f(6)) = 'ALTERADO POR OUTRO', 'conflito não sobrescreve';
  ASSERT (SELECT resultado = 'CONFLITO' AND resultado_detalhe LIKE 'Cadastro alterado%' FROM public.conferencia_itens WHERE funcionario_id = pg_temp.f(6) AND conferencia_id = v_id), 'conflito registrado';
  ASSERT (SELECT resultado_detalhe FROM public.conferencia_itens WHERE funcionario_id = pg_temp.f(2) AND conferencia_id = v_id) = 'CPF vinculado a outro funcionário', 'D2';
  ASSERT (SELECT resultado_detalhe FROM public.conferencia_itens WHERE folha->>'nome' = 'CPF JA TEM DONO') LIKE 'CPF já cadastrado%', 'novo com CPF existente';
  ASSERT (SELECT cargo = 'Porteiro' AND re = '900' AND status = 'ativo' AND empresa = 'MC REMOTA LTDA' AND data_admissao = DATE '2024-02-01' FROM public.funcionarios WHERE cpf = '15350946056'), 'cadastro novo';

  -- retenção
  ASSERT NOT EXISTS (SELECT 1 FROM public.conferencia_itens WHERE conferencia_id = v_id AND (folha->>'cpf' ~ '^\d{11}$' OR atual->>'cpf' ~ '^\d{11}$')), 'CPF completo removido';
  ASSERT (SELECT folha->>'cpf' FROM public.conferencia_itens WHERE folha->>'nome' = 'PESSOA NOVA') = '***.509.460-**', 'máscara';

  -- auditoria
  ASSERT (SELECT count(*) FROM public.audit_logs WHERE action = 'CONFERENCIA_ITEM_APLICADO' AND user_id = u.g) = 4, 'itens aplicados auditados';
  ASSERT EXISTS (SELECT 1 FROM public.audit_logs WHERE action = 'CONFERENCIA_APLICADA' AND entity_id = v_id::text AND user_id = u.g), 'aplicação auditada';
  -- procura os CPFs do cenário, e não 11 dígitos quaisquer: UUIDs terminam em dígitos e dariam falso positivo
  ASSERT NOT EXISTS (SELECT 1 FROM public.audit_logs l, unnest(ARRAY['11144477735', '98765432101', '12345678909', '39053344705', '45317828791', '15350946056', '86288366757']) c
    WHERE (l.action LIKE 'CONFERENCIA%' OR l.entity_type IN ('conferencias', 'conferencia_itens'))
      AND concat(l.old_data::text, l.new_data::text, l.description, l.observacao) LIKE '%' || c || '%'), 'sem CPF nos logs da conferência';

  -- idempotência
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_aplicar(%L, 'APLICAR 7')$q$, v_id));
  ASSERT r LIKE 'P0001 CONFERENCIA_ESTADO%', 'aplicar duas vezes: ' || r;
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'REJEITADA')$q$, (SELECT id FROM public.conferencia_itens WHERE conferencia_id = v_id AND tipo = 'AUSENTE' LIMIT 1)));
  ASSERT r LIKE 'P0001 CONFERENCIA_ESTADO%', 'decidir em conferência concluída: ' || r;
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_descartar(%L, 'motivo longo o bastante')$q$, v_id));
  ASSERT r LIKE 'P0001 CONFERENCIA_ESTADO%', 'descartar concluída: ' || r;

  -- FTs e períodos antigos intactos; ninguém foi apagado nem inativado
  ASSERT (SELECT ft FROM _foto) = (SELECT md5(string_agg(t::text, '|' ORDER BY id)) FROM public.ft t), 'FTs idênticas';
  ASSERT (SELECT hist FROM _foto) = (SELECT md5(string_agg(h::text, '|' ORDER BY id)) FROM public.ft_historico h), 'histórico idêntico';
  ASSERT (SELECT funcs FROM _foto) + 1 = (SELECT count(*) FROM public.funcionarios), 'só o novo cadastro a mais';
  ASSERT (SELECT periodos FROM _foto) = (SELECT count(*) FROM public.funcionario_inatividades), 'nenhum período criado';
  ASSERT NOT EXISTS (SELECT 1 FROM public.funcionarios WHERE status = 'inativo'), 'nenhum inativo novo';
END $$;

-- ---------------------------------------------------------------- nenhum caminho de inativação ou exclusão no código
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['conferencia_criar', 'conferencia_decidir', 'conferencia_aplicar', 'conferencia_descartar', 'conferencia_mascarar_itens'] LOOP
    ASSERT (SELECT prosrc FROM pg_proc WHERE proname = f) !~* $r$status\s*=\s*'inativo'$r$, f || ': caminho de inativação';
    ASSERT (SELECT prosrc FROM pg_proc WHERE proname = f) !~* $r$delete\s+from|truncate$r$, f || ': caminho de exclusão';
  END LOOP;
END $$;

-- ---------------------------------------------------------------- transação única: erro inesperado desfaz tudo
DO $$
DECLARE u record; r text; v_id uuid; i uuid;
BEGIN
  SELECT * INTO u FROM _u;
  r := pg_temp.como(u.g, pg_temp.cria(u.g, jsonb_build_array(
    pg_temp.item('DIVERGENCIA_NOME', pg_temp.f(5), 'AUSENTE DA FOLHA JUNIOR', '71428793860', pg_temp.atual(pg_temp.f(5)), 'ATUALIZAR_NOME'),
    pg_temp.item('NOVO', NULL, 'DATA RUIM', '60726481009', NULL, 'CADASTRAR'))));
  ASSERT r = 'ok:1', r;
  SELECT id INTO v_id FROM public.conferencias WHERE status = 'ABERTA';
  FOR i IN SELECT id FROM public.conferencia_itens WHERE conferencia_id = v_id AND tipo = 'DIVERGENCIA_NOME' LOOP
    ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'APROVADA', 'ATUALIZAR_NOME')$q$, i)) = 'ok:1', 'nome';
  END LOOP;
  UPDATE public.conferencia_itens SET folha = jsonb_set(folha, '{admissao}', '"data-invalida"') WHERE conferencia_id = v_id AND tipo = 'NOVO';
  SELECT id INTO i FROM public.conferencia_itens WHERE conferencia_id = v_id AND tipo = 'NOVO';
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'APROVADA', 'CADASTRAR', NULL, '{"re":"902","cargo":"ASG"}')$q$, i)); ASSERT r = 'ok:1', 'novo: ' || r;
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_aplicar(%L, 'APLICAR 2')$q$, v_id));
  ASSERT r LIKE '22007%' OR r LIKE '22008%', 'erro inesperado: ' || r;
  ASSERT (SELECT nome FROM public.funcionarios WHERE id = pg_temp.f(5)) = 'AUSENTE DA FOLHA', 'atômico: nada aplicado';
  ASSERT (SELECT status FROM public.conferencias WHERE id = v_id) = 'ABERTA', 'segue aberta';

  -- descartar encerra e mascara, sem aplicar
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_descartar(%L, 'curto')$q$, v_id));
  ASSERT r LIKE 'P0001 CONFERENCIA_JUSTIFICATIVA%', 'descartar exige motivo: ' || r;
  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_descartar(%L, 'Folha enviada com a competência errada')$q$, v_id)) = 'ok:1', 'descartar';
  ASSERT NOT EXISTS (SELECT 1 FROM public.conferencia_itens WHERE conferencia_id = v_id AND folha->>'cpf' ~ '^\d{11}$'), 'descartar mascara';
  ASSERT (SELECT nome FROM public.funcionarios WHERE id = pg_temp.f(5)) = 'AUSENTE DA FOLHA', 'descartar não aplica';
END $$;

-- ---------------------------------------------------------------- identidade: CPF mudou só nos dígitos que a máscara esconde
DO $$
DECLARE u record; r text; v_id uuid; i uuid; h uuid; res jsonb;
BEGIN
  SELECT * INTO u FROM _u;
  r := pg_temp.como(u.g, pg_temp.cria(u.g, jsonb_build_array(
    pg_temp.item('DIVERGENCIA_CPF', pg_temp.f(5), 'AUSENTE DA FOLHA', '60726481009', pg_temp.atual(pg_temp.f(5)), 'CORRIGIR_CPF'),
    jsonb_set(pg_temp.item('PENDENCIA', NULL, 'HOMONIMO DE ALGUEM', '70966798120', NULL, 'CADASTRAR'), '{funcionario_id}', to_jsonb(pg_temp.f(1)::text)),
    pg_temp.item('DIVERGENCIA_NOME', pg_temp.f(7), '   ', '86288366757', pg_temp.atual(pg_temp.f(7)), 'ATUALIZAR_NOME'))));
  ASSERT r = 'ok:1', r;
  SELECT id INTO v_id FROM public.conferencias WHERE status = 'ABERTA';
  SELECT id INTO i FROM public.conferencia_itens WHERE conferencia_id = v_id AND tipo = 'DIVERGENCIA_CPF';
  SELECT id INTO h FROM public.conferencia_itens WHERE conferencia_id = v_id AND tipo = 'PENDENCIA';

  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'APROVADA', 'CADASTRAR', NULL, '{"re":"950","cargo":"ASG"}')$q$, h));
  ASSERT r LIKE 'P0001 CONFERENCIA_JUSTIFICATIVA%', 'homônimo sem justificativa: ' || r;
  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'APROVADA', 'CADASTRAR', 'Outra pessoa, confirmado no RH', '{"re":"950","cargo":"ASG"}')$q$, h)) = 'ok:1', 'homônimo com justificativa';
  r := pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'APROVADA', 'ATUALIZAR_NOME')$q$, (SELECT id FROM public.conferencia_itens WHERE conferencia_id = v_id AND funcionario_id = pg_temp.f(7))));
  ASSERT r LIKE 'P0001 CONFERENCIA_DADOS%', 'nome em branco: ' || r;

  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_decidir(%L, 'APROVADA', 'CORRIGIR_CPF', 'Corrigido depois de conferir o RH')$q$, i)) = 'ok:1', 'corrigir';
  -- 71428793860 -> 01428793860: mesma máscara
  UPDATE public.funcionarios SET cpf = '01428793860' WHERE id = pg_temp.f(5);
  ASSERT pg_temp.como(u.g, format($q$SELECT public.conferencia_aplicar(%L, 'APLICAR 2')$q$, v_id)) = 'ok:1', 'aplicar';
  ASSERT (SELECT cpf FROM public.funcionarios WHERE id = pg_temp.f(5)) = '01428793860', 'mudança invisível na máscara não pode ser sobrescrita';
  ASSERT (SELECT resultado FROM public.conferencia_itens WHERE id = i) = 'CONFLITO', 'conflito de CPF';
END $$;

-- exclusão bloqueada mesmo para postgres
DO $$ BEGIN
  BEGIN
    DELETE FROM public.conferencias;
    RAISE EXCEPTION 'FALHA: conferência apagada';
  EXCEPTION WHEN raise_exception THEN ASSERT SQLERRM LIKE 'EXCLUSAO_PROIBIDA%', SQLERRM; END;
  BEGIN
    DELETE FROM public.conferencia_itens;
    RAISE EXCEPTION 'FALHA: item apagado';
  EXCEPTION WHEN raise_exception THEN ASSERT SQLERRM LIKE 'EXCLUSAO_PROIBIDA%', SQLERRM; END;
END $$;

ROLLBACK;
