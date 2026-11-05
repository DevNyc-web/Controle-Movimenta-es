-- TESTE LOCAL — NÃO RODAR EM PRODUÇÃO. Execução: bash supabase/tests/rodar_local.sh (Postgres descartável; dados fictícios).
-- Requer a migration 20261105120000. Tudo em transação com ROLLBACK final. ASSERT falho aborta com a mensagem do caso.
-- pg_temp.como(usuário, sql, metadata) executa como role authenticated com JWT simulado, sob RLS real,
-- e devolve 'ok:<linhas>' ou '<SQLSTATE> <mensagem>'.

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

-- Monta o INSERT que o frontend faz. p_just NULL = sem justificativa.
CREATE FUNCTION pg_temp.ins(p_lanc uuid, p_f uuid, p_data date, p_falt uuid DEFAULT NULL, p_just text DEFAULT NULL, p_extra text DEFAULT '') RETURNS text
LANGUAGE sql AS $$
  SELECT format(
    'INSERT INTO public.ft (funcionario_id, funcionario_faltante_id, data_ft, motivo, lancado_por, posto_falta, retroativa_justificativa %s) VALUES (%L, %L, %L, ''Falta'', %L, ''BASE'', %L %s)',
    CASE WHEN p_extra = '' THEN '' ELSE ', retroativa_autorizada_por, retroativa_autorizada_em' END,
    p_f, p_falt, p_data, p_lanc, p_just, p_extra)
$$;

CREATE FUNCTION pg_temp.hoje() RETURNS date LANGUAGE sql STABLE AS $$ SELECT (now() AT TIME ZONE 'America/Sao_Paulo')::date $$;

-- ---------------------------------------------------------------- fixtures (usuários via handle_new_user)
INSERT INTO auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
SELECT '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.uname || '@teste.local',
       jsonb_build_object('username', u.uname, 'nome', u.uname, 'role', u.role), now(), now()
FROM (VALUES
  ('e0000000-0000-0000-0000-000000000001'::uuid, 'tst_gestor',  'gestor'),
  ('e0000000-0000-0000-0000-000000000002'::uuid, 'tst_sup',     'supervisor'),
  ('e0000000-0000-0000-0000-000000000003'::uuid, 'tst_apont',   'apontamento'),
  ('e0000000-0000-0000-0000-000000000004'::uuid, 'tst_admin',   'admin'),
  ('e0000000-0000-0000-0000-000000000005'::uuid, 'tst_rh',      'rh'),
  ('e0000000-0000-0000-0000-000000000006'::uuid, 'tst_gestor2', 'gestor')
) AS u(id, uname, role);
UPDATE public.profiles SET ativo = false WHERE id = 'e0000000-0000-0000-0000-000000000006'; -- gestor desativado

INSERT INTO public.funcionarios (id, nome, re, cargo, turno, status) VALUES
  ('d0000000-0000-0000-0000-000000000001', 'ATIVO UM',        'T-1', 'Vigilante', 'Integral', 'ativo'),
  ('d0000000-0000-0000-0000-000000000002', 'ATIVO DOIS',      'T-2', 'Porteiro',  'Integral', 'ativo'),
  ('d0000000-0000-0000-0000-000000000003', 'FERIAS UM',       'T-3', 'Vigilante', 'Integral', 'ferias'),
  ('d0000000-0000-0000-0000-000000000004', 'SAIU UM',         'T-4', 'Vigilante', 'Integral', 'ativo'),
  ('d0000000-0000-0000-0000-000000000005', 'SAIU DOIS',       'T-5', 'Porteiro',  'Integral', 'ativo'),
  ('d0000000-0000-0000-0000-000000000006', 'HISTORICO',       'T-6', 'ASG',       'Integral', 'ativo'),
  ('d0000000-0000-0000-0000-000000000007', 'HIST FALTANTE',   'T-7', 'ASG',       'Integral', 'ativo'),
  ('d0000000-0000-0000-0000-000000000008', 'SEM NENHUMA FT',  'T-8', 'ASG',       'Integral', 'ativo');

-- FTs antigas, lançadas enquanto os funcionários estavam ativos
INSERT INTO public.ft (id, funcionario_id, funcionario_faltante_id, data_ft, motivo, lancado_por, posto_falta) VALUES
  ('f0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000006', 'd0000000-0000-0000-0000-000000000007', DATE '2026-01-10', 'Falta', 'e0000000-0000-0000-0000-000000000001', 'BASE'),
  ('f0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000006', NULL,                                   DATE '2026-01-11', 'Falta', 'e0000000-0000-0000-0000-000000000001', 'BASE'),
  ('f0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000006', NULL,                                   pg_temp.hoje() - 2, 'Falta', 'e0000000-0000-0000-0000-000000000002', 'BASE'),
  ('f0000000-0000-0000-0000-000000000004', 'd0000000-0000-0000-0000-000000000006', NULL,                                   pg_temp.hoje() - 3, 'Falta', 'e0000000-0000-0000-0000-000000000002', 'BASE'),
  ('f0000000-0000-0000-0000-000000000005', 'd0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', DATE '2026-01-14', 'Falta', 'e0000000-0000-0000-0000-000000000001', 'BASE');

CREATE TEMP TABLE _ft_antes ON COMMIT DROP AS SELECT id, funcionario_id, funcionario_faltante_id, data_ft, numero_ft FROM public.ft;
CREATE TEMP TABLE _hist_antes ON COMMIT DROP AS SELECT id FROM public.ft_historico;

-- ---------------------------------------------------------------- 1) estados
DO $$
DECLARE r text; g uuid := 'e0000000-0000-0000-0000-000000000001';
BEGIN
  ASSERT (SELECT status_ativo AND status = 'ativo' AND data_inativacao IS NULL FROM public.funcionarios WHERE re = 'T-1'), 'ativo permanece ativo';
  ASSERT (SELECT status_ativo AND status = 'ferias' AND data_inativacao IS NULL FROM public.funcionarios WHERE re = 'T-3'), 'férias não é inativo';

  -- status_ativo e data enviados pelo cliente são ignorados
  r := pg_temp.como(g, $q$UPDATE public.funcionarios SET status_ativo = false WHERE re = 'T-1'$q$);
  ASSERT r = 'ok:1', r;
  ASSERT (SELECT status_ativo FROM public.funcionarios WHERE re = 'T-1'), 'status_ativo não é controlado pelo cliente';

  r := pg_temp.como(g, $q$UPDATE public.funcionarios SET status = 'ferias', status_ativo = false WHERE re = 'T-2'$q$); -- frontend antigo
  ASSERT r = 'ok:1', r;
  ASSERT (SELECT status = 'ferias' AND status_ativo FROM public.funcionarios WHERE re = 'T-2'), 'frontend antigo: férias segue válido';
  r := pg_temp.como(g, $q$UPDATE public.funcionarios SET status = 'ativo' WHERE re = 'T-2'$q$);
  ASSERT r = 'ok:1', r;

  r := pg_temp.como(g, $q$UPDATE public.funcionarios SET data_inativacao = DATE '2020-01-01' WHERE re = 'T-1'$q$);
  ASSERT r = 'ok:1', r;
  ASSERT (SELECT data_inativacao IS NULL FROM public.funcionarios WHERE re = 'T-1'), 'ativo não recebe data forjada';

  -- inativação registra data efetiva e autor, ignorando o que o cliente manda
  r := pg_temp.como(g, $q$UPDATE public.funcionarios SET status = 'inativo', data_inativacao = DATE '2099-01-01', inativado_por = 'e0000000-0000-0000-0000-000000000002' WHERE re IN ('T-4', 'T-5', 'T-6', 'T-7')$q$);
  ASSERT r = 'ok:4', r;
  ASSERT (SELECT data_inativacao = pg_temp.hoje() AND inativado_por = g AND NOT status_ativo FROM public.funcionarios WHERE re = 'T-4'), 'data efetiva/autor definidos pelo banco';

  -- já inativo: data e autor imutáveis
  r := pg_temp.como(g, $q$UPDATE public.funcionarios SET data_inativacao = DATE '2099-01-01', cargo = 'ASG' WHERE re = 'T-5'$q$);
  ASSERT r = 'ok:1', r;
  ASSERT (SELECT data_inativacao = pg_temp.hoje() AND cargo = 'ASG' FROM public.funcionarios WHERE re = 'T-5'), 'data de inativo não muda';

  -- supervisor não inativa nem desfaz (RLS: 0 linhas)
  ASSERT pg_temp.como('e0000000-0000-0000-0000-000000000002', $q$UPDATE public.funcionarios SET status = 'inativo' WHERE re = 'T-1'$q$) = 'ok:0', 'supervisor não inativa';
  ASSERT pg_temp.como('e0000000-0000-0000-0000-000000000002', $q$UPDATE public.funcionarios SET status = 'ativo' WHERE re = 'T-4'$q$) = 'ok:0', 'supervisor não reativa';

  -- reativação limpa data e autor; nova inativação gera nova data
  ASSERT pg_temp.como(g, $q$UPDATE public.funcionarios SET status = 'ativo' WHERE re = 'T-8'$q$) = 'ok:1', 'no-op ativo';
  ASSERT pg_temp.como(g, $q$UPDATE public.funcionarios SET status = 'inativo' WHERE re = 'T-8'$q$) = 'ok:1', 'inativa T-8';
  ASSERT pg_temp.como(g, $q$UPDATE public.funcionarios SET status = 'ativo', reativacao_motivo = 'motivo adequado de teste' WHERE re = 'T-8'$q$) = 'ok:1', 'reativa T-8';
  ASSERT (SELECT status = 'ativo' AND status_ativo AND data_inativacao IS NULL AND inativado_por IS NULL FROM public.funcionarios WHERE re = 'T-8'), 'reativação consistente';

  -- nenhuma combinação incoerente passa nem como postgres com o trigger ativo; status inválido é recusado
  BEGIN
    UPDATE public.funcionarios SET status = 'demitido' WHERE re = 'T-8';
    RAISE EXCEPTION 'FALHA: status inválido aceito';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;

-- ---------------------------------------------------------------- 2) FT normal
DO $$
DECLARE r text;
  g uuid := 'e0000000-0000-0000-0000-000000000001'; s uuid := 'e0000000-0000-0000-0000-000000000002';
  a uuid := 'd0000000-0000-0000-0000-000000000001'; b uuid := 'd0000000-0000-0000-0000-000000000002';
  fer uuid := 'd0000000-0000-0000-0000-000000000003'; i1 uuid := 'd0000000-0000-0000-0000-000000000004';
BEGIN
  ASSERT pg_temp.como(s, pg_temp.ins(s, a, DATE '2026-02-01')) = 'ok:1', 'ativo permitido';
  ASSERT pg_temp.como(s, pg_temp.ins(s, a, DATE '2026-02-02', b)) = 'ok:1', 'ativo com faltante ativo permitido';

  r := pg_temp.como(s, pg_temp.ins(s, i1, DATE '2026-02-03'));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'inativo bloqueado (supervisor): ' || r;
  r := pg_temp.como(s, pg_temp.ins(s, a, DATE '2026-02-03', i1));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'faltante inativo bloqueado (supervisor): ' || r;

  -- postgres direto, sem JWT: sem usuário não há exceção
  BEGIN
    INSERT INTO public.ft (funcionario_id, data_ft, motivo, lancado_por, retroativa_justificativa)
    VALUES (i1, pg_temp.hoje() - 1, 'Falta', g, 'justificativa bem longa');
    RAISE EXCEPTION 'FALHA: INSERT direto sem usuário aceito';
  EXCEPTION WHEN raise_exception THEN
    ASSERT SQLERRM LIKE 'FUNCIONARIO_INATIVO%', SQLERRM;
  END;

  -- UPDATE: substituir funcionário ou faltante por inativo
  r := pg_temp.como(g, $q$UPDATE public.ft SET funcionario_id = 'd0000000-0000-0000-0000-000000000004' WHERE id = 'f0000000-0000-0000-0000-000000000005'$q$);
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'UPDATE funcionario_id para inativo: ' || r;
  r := pg_temp.como(g, $q$UPDATE public.ft SET funcionario_faltante_id = 'd0000000-0000-0000-0000-000000000004' WHERE id = 'f0000000-0000-0000-0000-000000000005'$q$);
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'UPDATE faltante para inativo: ' || r;
  -- a exceção não vale em UPDATE, mesmo com data anterior e gestor
  r := pg_temp.como(g, $q$UPDATE public.ft SET funcionario_id = 'd0000000-0000-0000-0000-000000000004', retroativa_justificativa = 'justificativa bem longa' WHERE id = 'f0000000-0000-0000-0000-000000000005'$q$);
  ASSERT r LIKE 'P0001 RETROATIVA_IMUTAVEL%', 'exceção não se aplica a UPDATE: ' || r;

  -- trocar para ativo continua possível ao gestor (comportamento anterior)
  ASSERT pg_temp.como(g, $q$UPDATE public.ft SET funcionario_faltante_id = NULL WHERE id = 'f0000000-0000-0000-0000-000000000005'$q$) = 'ok:1', 'faltante removido';
  ASSERT pg_temp.como(g, $q$UPDATE public.ft SET funcionario_faltante_id = 'd0000000-0000-0000-0000-000000000002' WHERE id = 'f0000000-0000-0000-0000-000000000005'$q$) = 'ok:1', 'faltante ativo restaurado';

  -- regra de férias preservada
  r := pg_temp.como(s, pg_temp.ins(s, fer, DATE '2026-02-04'));
  ASSERT r LIKE 'P0001 PERMISSAO_FERIAS%', 'férias: supervisor segue bloqueado: ' || r;
  ASSERT pg_temp.como(g, pg_temp.ins(g, fer, DATE '2026-02-04')) = 'ok:1', 'férias: gestor segue permitido';
  ASSERT (SELECT retroativa_autorizada_em IS NULL FROM public.ft WHERE funcionario_id = fer), 'férias não é exceção retroativa';

  -- justificativa sem inativo é recusada
  r := pg_temp.como(g, pg_temp.ins(g, a, DATE '2026-02-05', NULL, 'justificativa bem longa'));
  ASSERT r LIKE 'P0001 RETROATIVA_INDEVIDA%', r;
END $$;

-- ---------------------------------------------------------------- 3) FT retroativa
DO $$
DECLARE r text; v_ft uuid; v record;
  g uuid := 'e0000000-0000-0000-0000-000000000001'; s uuid := 'e0000000-0000-0000-0000-000000000002';
  ap uuid := 'e0000000-0000-0000-0000-000000000003'; ad uuid := 'e0000000-0000-0000-0000-000000000004';
  rh uuid := 'e0000000-0000-0000-0000-000000000005'; gd uuid := 'e0000000-0000-0000-0000-000000000006';
  a uuid := 'd0000000-0000-0000-0000-000000000001'; b uuid := 'd0000000-0000-0000-0000-000000000002';
  i1 uuid := 'd0000000-0000-0000-0000-000000000004'; i2 uuid := 'd0000000-0000-0000-0000-000000000005';
  ontem date := pg_temp.hoje() - 1; hoje date := pg_temp.hoje();
  j text := 'Serviço prestado antes do desligamento';
BEGIN
  -- gestor sem/curta justificativa
  r := pg_temp.como(g, pg_temp.ins(g, i1, ontem));
  ASSERT r LIKE 'P0001 RETROATIVA_JUSTIFICATIVA%', 'sem justificativa: ' || r;
  r := pg_temp.como(g, pg_temp.ins(g, i1, ontem, NULL, '   curta    '));
  ASSERT r LIKE 'P0001 RETROATIVA_JUSTIFICATIVA%', 'justificativa curta: ' || r;
  r := pg_temp.como(g, pg_temp.ins(g, i1, ontem, NULL, repeat('x', 1001)));
  ASSERT r LIKE 'P0001 RETROATIVA_JUSTIFICATIVA%', 'justificativa longa: ' || r;

  -- data igual ou posterior
  r := pg_temp.como(g, pg_temp.ins(g, i1, hoje, NULL, j));
  ASSERT r LIKE 'P0001 RETROATIVA_DATA%', 'data igual: ' || r;
  r := pg_temp.como(g, pg_temp.ins(g, i1, hoje + 1, NULL, j));
  ASSERT r LIKE 'P0001 RETROATIVA_DATA%', 'data posterior: ' || r;

  -- demais perfis, com tudo válido
  r := pg_temp.como(s, pg_temp.ins(s, i1, ontem, NULL, j));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'supervisor bloqueado: ' || r;
  r := pg_temp.como(ap, pg_temp.ins(ap, i1, ontem, NULL, j));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'apontamento bloqueado: ' || r;
  r := pg_temp.como(ad, pg_temp.ins(ad, i1, ontem, NULL, j));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'admin não é gestor: ' || r;
  r := pg_temp.como(rh, pg_temp.ins(rh, i1, ontem, NULL, j));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'rh bloqueado: ' || r;
  r := pg_temp.como(gd, pg_temp.ins(gd, i1, ontem, NULL, j));
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'gestor com perfil desativado: ' || r;

  -- falsificação de perfil: metadata de gestor e lancado_por de um gestor real
  r := pg_temp.como(s, pg_temp.ins(s, i1, ontem, NULL, j), '{"role": "gestor"}');
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'metadata não dá perfil: ' || r;
  r := pg_temp.como(s, pg_temp.ins(g, i1, ontem, NULL, j));
  -- o trigger roda antes da RLS: aceitar 42501 aqui esconderia um trigger que confiasse em lancado_por
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'lancado_por de outro não dá perfil: ' || r;
  ASSERT NOT EXISTS (SELECT 1 FROM public.ft WHERE funcionario_id = i1), 'nenhuma FT criada até aqui';

  -- caso válido, tentando forjar a autoria
  r := pg_temp.como(g, pg_temp.ins(g, i1, ontem, NULL, '  ' || j || '  ', format(', %L, %L', s, '2000-01-01')));
  ASSERT r = 'ok:1', 'gestor autorizado: ' || r;
  SELECT * INTO v FROM public.ft WHERE funcionario_id = i1;
  v_ft := v.id;
  ASSERT v.retroativa_autorizada_por = g, 'autor é o usuário autenticado, não o enviado';
  ASSERT v.retroativa_autorizada_em::date >= hoje - 1, 'carimbo é do banco, não o enviado';
  ASSERT v.retroativa_justificativa = j, 'justificativa gravada (sem espaços nas pontas)';
  ASSERT EXISTS (SELECT 1 FROM public.ft_historico WHERE ft_id = v_ft AND acao = 'LANCAMENTO_RETROATIVO' AND alterado_por = g AND observacao = j), 'histórico da FT';
  ASSERT EXISTS (SELECT 1 FROM public.audit_logs WHERE entity_id = v_ft::text AND action = 'FT_RETROATIVA_EXCECAO' AND user_id = g AND observacao = j AND username = 'tst_gestor'), 'audit_logs com autoria';

  -- faltante inativo elegível; e dois inativos: a regra vale para os dois
  r := pg_temp.como(g, pg_temp.ins(g, a, ontem - 1, i2, j));
  ASSERT r = 'ok:1', 'faltante inativo elegível: ' || r;
  r := pg_temp.como(g, pg_temp.ins(g, a, ontem - 2, i2));
  ASSERT r LIKE 'P0001 RETROATIVA_JUSTIFICATIVA%', 'faltante inativo exige justificativa: ' || r;
  r := pg_temp.como(g, pg_temp.ins(g, i2, ontem - 3, i1, j));
  ASSERT r = 'ok:1', 'dois inativos elegíveis: ' || r;

  -- contorno posterior: autorização imutável
  r := pg_temp.como(g, format($q$UPDATE public.ft SET retroativa_justificativa = 'outra justificativa qualquer' WHERE id = %L$q$, v_ft));
  ASSERT r LIKE 'P0001 RETROATIVA_IMUTAVEL%', 'justificativa imutável: ' || r;
  r := pg_temp.como(g, format($q$UPDATE public.ft SET retroativa_autorizada_por = NULL, retroativa_autorizada_em = NULL, retroativa_justificativa = NULL WHERE id = %L$q$, v_ft));
  ASSERT r LIKE 'P0001 RETROATIVA_IMUTAVEL%', 'autorização não some: ' || r;
  r := pg_temp.como(g, format($q$UPDATE public.ft SET data_ft = %L WHERE id = %L$q$, hoje + 5, v_ft));
  ASSERT r LIKE 'P0001 RETROATIVA_IMUTAVEL%', 'data da FT retroativa imutável: ' || r;
  r := pg_temp.como(g, format($q$UPDATE public.ft SET funcionario_id = %L WHERE id = %L$q$, b, v_ft));
  ASSERT r LIKE 'P0001 RETROATIVA_IMUTAVEL%', 'funcionário da FT retroativa imutável: ' || r;
  r := pg_temp.como(g, format($q$UPDATE public.ft SET funcionario_faltante_id = %L WHERE id = %L$q$, b, v_ft));
  ASSERT r LIKE 'P0001 RETROATIVA_IMUTAVEL%', 'faltante da FT retroativa imutável: ' || r;

  -- nem postgres passa por cima do congelamento
  BEGIN
    UPDATE public.ft SET retroativa_justificativa = 'adulterada via sql direto' WHERE id = v_ft;
    RAISE EXCEPTION 'FALHA: justificativa adulterada';
  EXCEPTION WHEN raise_exception THEN
    ASSERT SQLERRM LIKE 'RETROATIVA_IMUTAVEL%', SQLERRM;
  END;

  -- FT comum não vira exceção por UPDATE (já coberto) nem muda de data com inativo vinculado
  r := pg_temp.como(g, $q$UPDATE public.ft SET data_ft = DATE '2026-01-20' WHERE id = 'f0000000-0000-0000-0000-000000000002'$q$);
  ASSERT r LIKE 'P0001 FUNCIONARIO_INATIVO%', 'mudar data de FT com inativo: ' || r;
  r := pg_temp.como(g, $q$UPDATE public.ft SET data_ft = DATE '2026-01-20' WHERE id = 'f0000000-0000-0000-0000-000000000005'$q$);
  ASSERT r = 'ok:1', 'mudar data com ativos continua igual: ' || r;

  -- FT retroativa segue processável
  ASSERT pg_temp.como(g, format($q$UPDATE public.ft SET status = 'APROVADA', aprovado_por = %L WHERE id = %L$q$, g, v_ft)) = 'ok:1', 'FT retroativa aprovável';

  -- reativado depois: evidência fica, FT nova volta ao fluxo normal
  ASSERT pg_temp.como(g, $q$UPDATE public.funcionarios SET status = 'ativo', reativacao_motivo = 'motivo adequado de teste' WHERE re = 'T-4'$q$) = 'ok:1', 'reativa T-4';
  ASSERT (SELECT retroativa_justificativa = j FROM public.ft WHERE id = v_ft), 'evidência sobrevive à reativação';
  r := pg_temp.como(s, pg_temp.ins(s, i1, DATE '2026-02-10'));
  ASSERT r = 'ok:1', 'reativado volta ao fluxo normal: ' || r;
END $$;

-- ---------------------------------------------------------------- 4) histórico: FT antiga de quem foi inativado depois
DO $$
DECLARE r text; v_sol uuid; n int;
  g uuid := 'e0000000-0000-0000-0000-000000000001'; s uuid := 'e0000000-0000-0000-0000-000000000002';
  ft1 uuid := 'f0000000-0000-0000-0000-000000000001'; ft2 uuid := 'f0000000-0000-0000-0000-000000000002';
  ft3 uuid := 'f0000000-0000-0000-0000-000000000003'; ft4 uuid := 'f0000000-0000-0000-0000-000000000004';
BEGIN
  ASSERT (SELECT status FROM public.funcionarios WHERE re = 'T-6') = 'inativo', 'pressuposto: funcionário da FT antiga está inativo';

  -- consulta, com o mesmo embed do frontend, por gestor e apontamento
  ASSERT pg_temp.como(g, format('SELECT f.id, x.nome, y.nome FROM public.ft f JOIN public.funcionarios x ON x.id = f.funcionario_id LEFT JOIN public.funcionarios y ON y.id = f.funcionario_faltante_id WHERE f.id = %L', ft1)) = 'ok:1', 'gestor vê';
  ASSERT pg_temp.como('e0000000-0000-0000-0000-000000000003', format('SELECT id FROM public.ft WHERE id = %L', ft1)) = 'ok:1', 'apontamento vê';

  -- correção de valor (mesmo UPDATE do detalhe), histórico e aprovação
  ASSERT pg_temp.como(g, format($q$UPDATE public.ft SET valor_pago = 250, pagamento_em_folha = true WHERE id = %L AND status = 'PENDENTE'$q$, ft1)) = 'ok:1', 'correção de valor';
  ASSERT EXISTS (SELECT 1 FROM public.ft_historico WHERE ft_id = ft1 AND acao = 'VALORES_CORRIGIDOS' AND alterado_por = g), 'histórico de correção gravado pelo banco';
  ASSERT pg_temp.como(g, format($q$UPDATE public.ft SET status = 'APROVADA', aprovado_por = %L WHERE id = %L$q$, g, ft1)) = 'ok:1', 'aprovação';

  -- negação e cancelamento direto
  ASSERT pg_temp.como(g, format($q$UPDATE public.ft SET status = 'NEGADA', aprovado_por = %L WHERE id = %L$q$, g, ft2)) = 'ok:1', 'negação';
  ASSERT pg_temp.como(g, format($q$UPDATE public.ft SET status = 'CANCELADA', data_cancelamento = now() WHERE id = %L$q$, ft1)) = 'ok:1', 'cancelamento direto';

  -- fluxo com solicitação do supervisor: aprovar (ft3) e rejeitar (ft4)
  r := pg_temp.como(s, format($q$INSERT INTO public.ft_cancelamento_solicitacoes (ft_id, solicitado_por, motivo) VALUES (%L, %L, 'teste')$q$, ft3, s));
  ASSERT r = 'ok:1', 'solicitação de cancelamento: ' || r;
  SELECT id INTO v_sol FROM public.ft_cancelamento_solicitacoes WHERE ft_id = ft3;
  ASSERT pg_temp.como(g, format('SELECT public.aprovar_cancelamento(%L)', v_sol)) = 'ok:1', 'aprovar cancelamento';
  ASSERT (SELECT status FROM public.ft WHERE id = ft3) = 'CANCELADA', 'FT antiga cancelada';

  r := pg_temp.como(s, format($q$INSERT INTO public.ft_cancelamento_solicitacoes (ft_id, solicitado_por, motivo) VALUES (%L, %L, 'teste')$q$, ft4, s));
  ASSERT r = 'ok:1', 'solicitação de cancelamento 2: ' || r;
  SELECT id INTO v_sol FROM public.ft_cancelamento_solicitacoes WHERE ft_id = ft4;
  ASSERT pg_temp.como(g, format('SELECT public.rejeitar_cancelamento(%L)', v_sol)) = 'ok:1', 'rejeitar cancelamento';
  ASSERT (SELECT status FROM public.ft WHERE id = ft4) = 'PENDENTE', 'FT antiga volta a PENDENTE';

  -- NEGADA de inativo pode ser reaberta: o vínculo não é novo (comportamento anterior mantido)
  ASSERT pg_temp.como(g, format($q$UPDATE public.ft SET status = 'PENDENTE' WHERE id = %L$q$, ft2)) = 'ok:1', 'NEGADA reaberta';
END $$;

-- ---------------------------------------------------------------- 5) exclusão física
DO $$
DECLARE r text;
  g uuid := 'e0000000-0000-0000-0000-000000000001'; s uuid := 'e0000000-0000-0000-0000-000000000002';
  ad uuid := 'e0000000-0000-0000-0000-000000000004';
BEGIN
  -- T-8 não tem FT: a proibição não depende de haver vínculo
  ASSERT NOT EXISTS (SELECT 1 FROM public.ft f JOIN public.funcionarios x ON x.id IN (f.funcionario_id, f.funcionario_faltante_id) WHERE x.re = 'T-8'), 'pressuposto: T-8 sem FT';
  r := pg_temp.como(g, $q$DELETE FROM public.funcionarios WHERE re = 'T-8'$q$);
  ASSERT r LIKE '42501%', 'gestor: ' || r;
  r := pg_temp.como(ad, $q$DELETE FROM public.funcionarios WHERE re = 'T-8'$q$);
  ASSERT r LIKE '42501%', 'admin: ' || r;
  r := pg_temp.como(s, $q$DELETE FROM public.funcionarios WHERE re = 'T-8'$q$);
  ASSERT r LIKE '42501%', 'supervisor: ' || r;
  r := pg_temp.como(g, 'TRUNCATE public.funcionarios CASCADE');
  ASSERT r LIKE '42501%', 'TRUNCATE gestor: ' || r;
  r := pg_temp.como(g, 'TRUNCATE public.ft_historico');
  ASSERT r LIKE '42501%', 'TRUNCATE histórico: ' || r;

  -- service_role e postgres: passam por cima de RLS, não do bloqueio
  PERFORM set_config('role', 'service_role', true);
  BEGIN
    DELETE FROM public.funcionarios WHERE re = 'T-8';
    RAISE EXCEPTION 'FALHA: service_role excluiu';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM set_config('role', 'postgres', true);

  BEGIN
    DELETE FROM public.funcionarios WHERE re = 'T-8';
    RAISE EXCEPTION 'FALHA: postgres excluiu';
  EXCEPTION WHEN raise_exception THEN
    ASSERT SQLERRM LIKE 'EXCLUSAO_PROIBIDA%', SQLERRM;
  END;
  BEGIN
    TRUNCATE public.funcionarios CASCADE;
    RAISE EXCEPTION 'FALHA: postgres truncou';
  EXCEPTION WHEN raise_exception THEN
    ASSERT SQLERRM LIKE 'EXCLUSAO_PROIBIDA%', SQLERRM;
  END;

  ASSERT NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'funcionarios' AND cmd IN ('DELETE', 'ALL')), 'sem policy de DELETE';
  ASSERT (SELECT count(*) FROM pg_constraint WHERE conrelid = 'public.ft'::regclass AND contype = 'f' AND confrelid = 'public.funcionarios'::regclass AND confdeltype = 'r'
           AND conname IN ('ft_funcionario_id_fkey', 'ft_funcionario_faltante_id_fkey')) = 2, 'FKs com RESTRICT e nomes usados pelo frontend';
  ASSERT NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND prosrc ~* 'delete\s+from\s+(public\.)?funcionarios'
  ), 'nenhuma função apaga funcionários';
END $$;

-- Segunda barreira: com o trigger desligado de propósito, a FK ainda segura funcionário com FT (titular e faltante)
ALTER TABLE public.funcionarios DISABLE TRIGGER trg_funcionarios_bloquear_exclusao;
DO $$ BEGIN
  BEGIN
    DELETE FROM public.funcionarios WHERE re = 'T-6';
    RAISE EXCEPTION 'FALHA: FK não segurou o titular';
  EXCEPTION WHEN foreign_key_violation OR restrict_violation THEN NULL;
  END;
  BEGIN
    DELETE FROM public.funcionarios WHERE re = 'T-7';
    RAISE EXCEPTION 'FALHA: FK não segurou o faltante';
  EXCEPTION WHEN foreign_key_violation OR restrict_violation THEN NULL;
  END;
END $$;
ALTER TABLE public.funcionarios ENABLE TRIGGER trg_funcionarios_bloquear_exclusao;

-- ---------------------------------------------------------------- 6) integridade final
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _ft_antes a LEFT JOIN public.ft f USING (id) WHERE f.id IS NULL;
  ASSERT n = 0, 'nenhuma FT antiga apagada';

  -- ft5 teve a data mudada de propósito (seção 3), com ativos; as demais seguem idênticas
  SELECT count(*) INTO n FROM _ft_antes a JOIN public.ft f USING (id)
   WHERE a.id <> 'f0000000-0000-0000-0000-000000000005'
     AND (f.funcionario_id, f.funcionario_faltante_id, f.data_ft, f.numero_ft) IS DISTINCT FROM (a.funcionario_id, a.funcionario_faltante_id, a.data_ft, a.numero_ft);
  ASSERT n = 0, 'associações, datas e números históricos intactos';

  SELECT count(*) INTO n FROM _hist_antes a LEFT JOIN public.ft_historico h USING (id) WHERE h.id IS NULL;
  ASSERT n = 0, 'nenhum histórico apagado';

  ASSERT (SELECT count(*) FROM public.funcionarios WHERE re LIKE 'T-%') = 8, 'nenhum funcionário apagado';
  ASSERT NOT EXISTS (SELECT 1 FROM public.funcionarios WHERE status_ativo <> (status <> 'inativo') OR (status = 'inativo') <> (data_inativacao IS NOT NULL)), 'estados coerentes';
END $$;

ROLLBACK;
