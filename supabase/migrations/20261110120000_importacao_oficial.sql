-- Importação oficial de funcionários (sobre a Conferência) e restrição do CPF por perfil. NÃO APLICADA.
-- Requer 20261105120000, 20261105120100 e 20261106120000. Reversão: supabase/rollback/20261110120000_rollback.sql.
--
-- Regras:
--  * Uma importação por empresa; a empresa é obrigatória e vem de lista fechada.
--  * Primeira importação concluída de cada empresa fica registrada em importacao_empresas. Nela, ausentes são só sinalizados.
--  * Inativar ausente: só em importação posterior, com quadro completo confirmado ("QUADRO COMPLETO <EMPRESA>"), justificativa,
--    funcionário da mesma empresa e cargo diferente de Freelancer (valor controlado do cadastro, conferido de novo na aplicação).
--  * A inativação usa o UPDATE normal: os gatilhos da Fase 1A criam o período e protegem as FTs.
--  * Decisões alteradas depois da tela carregada invalidam a aplicação (revisao).
--  * Conferência aberta há mais de 7 dias não pode ser decidida, confirmada nem aplicada; é descartada e mascarada ao criar a próxima.
--  * CPF: nenhum perfil lê ou altera a coluna diretamente. O Gestor lê por funcionario_cpf()/funcionarios_cpfs() e altera por
--    funcionario_alterar_cpf(), com justificativa. Todo CPF gravado é normalizado e validado.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $$
BEGIN
  IF to_regclass('public.conferencias') IS NULL OR to_regclass('public.funcionario_inatividades') IS NULL THEN
    RAISE EXCEPTION 'Abortado: aplique antes as migrations da Fase 1A e da Conferência.';
  END IF;
END $$;

-- ============================================================
-- 1. Empresas e primeira importação
-- ============================================================
CREATE OR REPLACE FUNCTION public.empresa_valida(_empresa TEXT)
RETURNS BOOLEAN
LANGUAGE SQL IMMUTABLE
SET search_path = public
AS $$
  SELECT coalesce(_empresa IN (
    'M C ALPHA SEGURANCA ELETRONICA LTDA ME', 'M C SERVICOS GERAIS LTDA', 'MC FACILIT SERVICOS E COMERCIO SOCIEDADE', 'MC REMOTA LTDA',
    'MC SEGURANCA E VIGILANCIA SS LTDA', 'MC SERVICOS E PORTARIA EIRELI', 'MC SERVICOS PATRIMONIAIS EIRELI', 'MC SOLUCOES E SERVICOS LTDA'), false)
$$;

CREATE TABLE public.importacao_empresas (
  empresa        TEXT        PRIMARY KEY CHECK (public.empresa_valida(empresa)),
  conferencia_id UUID        NOT NULL REFERENCES public.conferencias(id) ON DELETE RESTRICT,
  validada_por   UUID        NOT NULL,
  validada_em    TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.importacao_empresas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Gestor le importacao_empresas" ON public.importacao_empresas FOR SELECT TO authenticated
  USING ((SELECT public.has_role(auth.uid(), 'gestor'::public.app_role)));
REVOKE ALL ON public.importacao_empresas FROM anon, authenticated, service_role;
GRANT SELECT ON public.importacao_empresas TO authenticated;
CREATE TRIGGER audit_importacao_empresas AFTER INSERT OR UPDATE OR DELETE ON public.importacao_empresas
  FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();
CREATE TRIGGER trg_importacao_empresas_bloquear_exclusao BEFORE DELETE ON public.importacao_empresas
  FOR EACH ROW EXECUTE FUNCTION public.tg_bloquear_exclusao('o registro da primeira importação não pode ser excluído.');
CREATE TRIGGER trg_importacao_empresas_bloquear_truncate BEFORE TRUNCATE ON public.importacao_empresas
  FOR EACH STATEMENT EXECUTE FUNCTION public.tg_bloquear_exclusao('o registro da primeira importação não pode ser excluído.');

ALTER TABLE public.conferencias
  ADD COLUMN empresa TEXT CHECK (empresa IS NULL OR public.empresa_valida(empresa)),
  ADD COLUMN primeira_da_empresa BOOLEAN,
  ADD COLUMN quadro_completo_em TIMESTAMPTZ,
  ADD COLUMN quadro_completo_por UUID,
  ADD COLUMN revisao INT NOT NULL DEFAULT 0,
  ADD CONSTRAINT conferencias_quadro_so_depois_da_primeira CHECK (quadro_completo_em IS NULL OR primeira_da_empresa = false);

-- ============================================================
-- 2. Tipos e ações dos itens
-- ============================================================
ALTER TABLE public.conferencia_itens
  DROP CONSTRAINT conferencia_itens_tipo_check,
  DROP CONSTRAINT conferencia_itens_opcoes_validas,
  DROP CONSTRAINT conferencia_itens_ausente_sem_acao,
  ADD CONSTRAINT conferencia_itens_tipo_check CHECK (tipo IN ('CORRESPONDENTE', 'DIVERGENCIA_NOME', 'DIVERGENCIA_CPF', 'DIVERGENCIA_CARGO',
    'DIVERGENCIA_RE', 'DIVERGENCIA_EMPRESA', 'NOVO', 'INATIVO', 'AUSENTE', 'DUPLICADO', 'PENDENCIA')),
  ADD CONSTRAINT conferencia_itens_opcoes_validas CHECK (opcoes <@ ARRAY['ATUALIZAR_NOME', 'PREENCHER_CPF', 'CORRIGIR_CPF', 'CADASTRAR', 'REATIVAR',
    'ATUALIZAR_CARGO', 'CORRIGIR_RE', 'CORRIGIR_EMPRESA', 'INATIVAR']),
  -- ausente só pode ser inativado; e inativar só existe para ausente
  ADD CONSTRAINT conferencia_itens_ausente_so_inativa CHECK (tipo <> 'AUSENTE' OR opcoes <@ ARRAY['INATIVAR']),
  ADD CONSTRAINT conferencia_itens_inativar_so_ausente CHECK (NOT 'INATIVAR' = ANY (opcoes) OR tipo = 'AUSENTE');

-- ============================================================
-- 3. CPF: normalização, validação e justificativa em qualquer alteração
-- ============================================================
-- SECURITY DEFINER: as funções de CPF não são executáveis por authenticated, e o gatilho roda em gravações feitas pelo app.
CREATE OR REPLACE FUNCTION public.tg_funcionarios_cpf()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.cpf := public.cpf_digitos(NEW.cpf);
  IF NEW.cpf IS NOT NULL AND NOT public.cpf_valido(NEW.cpf) THEN
    RAISE EXCEPTION 'CPF_INVALIDO: o CPF informado não é válido.';
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.cpf IS DISTINCT FROM OLD.cpf
     AND NOT public.texto_justificativa_valido(current_setting('app.cpf_justificativa', true)) THEN
    RAISE EXCEPTION 'CPF_JUSTIFICATIVA: alterar o CPF exige justificativa com pelo menos 10 letras ou números.';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.tg_funcionarios_cpf() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER trg_funcionarios_cpf BEFORE INSERT OR UPDATE OF cpf ON public.funcionarios
  FOR EACH ROW EXECUTE FUNCTION public.tg_funcionarios_cpf();

-- Auditoria genérica: o CPF vai mascarado (mesma máscara da Conferência). A troca continua rastreável: "cpf_alterado" na própria
-- linha e o registro CPF_ALTERADO/CPF_INFORMADO com justificativa. Só afeta tabelas com coluna cpf (hoje, funcionarios).
CREATE OR REPLACE FUNCTION public.tg_audit_row()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_entity text := TG_TABLE_NAME;
  v_old jsonb := CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END;
  v_new jsonb := CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END;
  v_id text := coalesce(v_new, v_old)->>'id';
BEGIN
  IF v_old ? 'cpf' THEN v_old := jsonb_set(v_old, '{cpf}', coalesce(to_jsonb(public.cpf_mascarado(v_old->>'cpf')), 'null'::jsonb)); END IF;
  IF v_new ? 'cpf' THEN
    IF TG_OP = 'UPDATE' AND (to_jsonb(OLD)->>'cpf') IS DISTINCT FROM (to_jsonb(NEW)->>'cpf') THEN v_new := v_new || '{"cpf_alterado": true}'; END IF;
    v_new := jsonb_set(v_new, '{cpf}', coalesce(to_jsonb(public.cpf_mascarado(v_new->>'cpf')), 'null'::jsonb));
  END IF;
  IF TG_OP = 'DELETE' THEN
    PERFORM public.log_audit('DELETE', v_entity, v_id, format('Excluiu registro em %s (id %s)', v_entity, v_id), v_old, NULL, NULL);
    RETURN OLD;
  ELSIF TG_OP = 'UPDATE' THEN
    PERFORM public.log_audit('UPDATE', v_entity, v_id, format('Atualizou registro em %s (id %s)', v_entity, v_id), v_old, v_new, NULL);
    RETURN NEW;
  ELSE
    PERFORM public.log_audit('INSERT', v_entity, v_id, format('Criou registro em %s (id %s)', v_entity, v_id), NULL, v_new, NULL);
    RETURN NEW;
  END IF;
END; $$;
REVOKE EXECUTE ON FUNCTION public.tg_audit_row() FROM PUBLIC, anon, authenticated;

-- Leitura do CPF: só Gestor com conta ativa.
CREATE OR REPLACE FUNCTION public.funcionario_cpf(_id UUID)
RETURNS TEXT
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'gestor'::public.app_role) THEN
    RAISE EXCEPTION 'PERMISSAO: apenas o Gestor pode ver o CPF.';
  END IF;
  RETURN (SELECT cpf FROM public.funcionarios WHERE id = _id);
END;
$$;

CREATE OR REPLACE FUNCTION public.funcionarios_cpfs()
RETURNS TABLE (id UUID, cpf TEXT)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'gestor'::public.app_role) THEN
    RAISE EXCEPTION 'PERMISSAO: apenas o Gestor pode ver o CPF.';
  END IF;
  RETURN QUERY SELECT f.id, f.cpf FROM public.funcionarios f WHERE f.cpf IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.funcionario_alterar_cpf(_id UUID, _cpf TEXT, _justificativa TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_cpf TEXT := public.cpf_digitos(_cpf);
  v_just TEXT := btrim(_justificativa);
  v_antigo TEXT;
BEGIN
  IF NOT public.has_role(v_uid, 'gestor'::public.app_role) THEN
    RAISE EXCEPTION 'PERMISSAO: apenas o Gestor pode alterar o CPF.';
  END IF;
  IF NOT public.texto_justificativa_valido(v_just) THEN
    RAISE EXCEPTION 'CPF_JUSTIFICATIVA: informe uma justificativa com pelo menos 10 letras ou números.';
  END IF;
  IF NOT public.cpf_valido(v_cpf) THEN RAISE EXCEPTION 'CPF_INVALIDO: o CPF informado não é válido.'; END IF;
  SELECT cpf INTO v_antigo FROM public.funcionarios WHERE id = _id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CPF_ESTADO: funcionário não encontrado.'; END IF;
  IF v_antigo IS NOT DISTINCT FROM v_cpf THEN RAISE EXCEPTION 'CPF_ESTADO: o CPF informado é igual ao atual.'; END IF;
  IF EXISTS (SELECT 1 FROM public.funcionarios WHERE public.cpf_digitos(cpf) = v_cpf AND id <> _id) THEN
    RAISE EXCEPTION 'CPF_DUPLICADO: este CPF já pertence a outro funcionário.';
  END IF;
  PERFORM set_config('app.cpf_justificativa', v_just, true);
  BEGIN
    UPDATE public.funcionarios SET cpf = v_cpf WHERE id = _id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'CPF_DUPLICADO: este CPF já pertence a outro funcionário.';
  END;
  PERFORM set_config('app.cpf_justificativa', '', true);
  PERFORM public.log_audit(CASE WHEN v_antigo IS NULL THEN 'CPF_INFORMADO' ELSE 'CPF_ALTERADO' END, 'funcionarios', _id::text,
    'CPF do funcionário alterado', jsonb_build_object('cpf', public.cpf_mascarado(v_antigo)), jsonb_build_object('cpf', public.cpf_mascarado(v_cpf)), v_just);
END;
$$;

-- Ninguém lê nem altera a coluna diretamente; inserir com CPF continua possível (o gatilho valida).
REVOKE SELECT, UPDATE ON public.funcionarios FROM anon, authenticated;
DO $$
DECLARE v_cols TEXT;
BEGIN
  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position) INTO v_cols
    FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'funcionarios' AND column_name <> 'cpf';
  EXECUTE format('GRANT SELECT (%s), UPDATE (%s) ON public.funcionarios TO authenticated', v_cols, v_cols);
END $$;

-- ============================================================
-- 4. Criar: empresa obrigatória, primeira importação calculada aqui, expiração das abertas antigas
-- ============================================================
CREATE OR REPLACE FUNCTION public.conferencia_criar(_arquivo JSONB, _resumo JSONB, _itens JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_id UUID;
  v_i JSONB;
  v_ordem BIGINT;
  v_opcoes TEXT[];
  v_empresa TEXT := _arquivo->>'empresa';
  v_primeira BOOLEAN;
  v_velha UUID;
BEGIN
  IF NOT public.has_role(v_uid, 'gestor'::public.app_role) THEN
    RAISE EXCEPTION 'PERMISSAO: apenas o Gestor pode criar uma conferência.';
  END IF;
  IF jsonb_typeof(_itens) IS DISTINCT FROM 'array' OR jsonb_array_length(_itens) > 25000 OR coalesce(btrim(_arquivo->>'nome'), '') = '' THEN
    RAISE EXCEPTION 'CONFERENCIA_DADOS: conferência sem arquivo ou com itens inválidos.';
  END IF;
  IF NOT public.empresa_valida(v_empresa) THEN
    RAISE EXCEPTION 'CONFERENCIA_EMPRESA: informe a empresa da planilha oficial.';
  END IF;

  FOR v_velha IN SELECT id FROM public.conferencias WHERE status = 'ABERTA' AND criada_em < now() - interval '7 days' FOR UPDATE LOOP
    UPDATE public.conferencias SET status = 'DESCARTADA', motivo_descarte = 'Expirada: aberta por mais de 7 dias sem aplicação',
           encerrada_por = v_uid, encerrada_em = now() WHERE id = v_velha;
    PERFORM public.conferencia_mascarar_itens(v_velha);
    PERFORM public.log_audit('CONFERENCIA_EXPIRADA', 'conferencias', v_velha::text, 'Conferência aberta há mais de 7 dias descartada sem aplicar alterações', NULL, NULL, NULL);
  END LOOP;

  v_primeira := NOT EXISTS (SELECT 1 FROM public.importacao_empresas WHERE empresa = v_empresa);
  IF v_primeira AND EXISTS (SELECT 1 FROM jsonb_array_elements(_itens) e WHERE coalesce(e->'opcoes', '[]') ? 'INATIVAR') THEN
    RAISE EXCEPTION 'CONFERENCIA_PRIMEIRA: na primeira importação da empresa os ausentes são apenas sinalizados.';
  END IF;

  BEGIN
    INSERT INTO public.conferencias (arquivo_nome, arquivo_abas, mapeamento, linhas_ignoradas, total_impresso, resumo, criada_por, empresa, primeira_da_empresa)
    VALUES (
      left(_arquivo->>'nome', 255),
      ARRAY(SELECT jsonb_array_elements_text(coalesce(_arquivo->'abas', '[]'::jsonb))),
      coalesce(_arquivo->'mapeamento', '{}'::jsonb),
      coalesce((_arquivo->>'ignoradas')::int, 0),
      (_arquivo->>'total_impresso')::int,
      _resumo, v_uid, v_empresa, v_primeira
    ) RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'CONFERENCIA_ABERTA: já existe uma conferência aberta. Conclua ou descarte antes de iniciar outra.';
  END;

  FOR v_i, v_ordem IN SELECT e, o FROM jsonb_array_elements(_itens) WITH ORDINALITY AS t(e, o) LOOP
    v_opcoes := ARRAY(SELECT jsonb_array_elements_text(coalesce(v_i->'opcoes', '[]'::jsonb)));
    INSERT INTO public.conferencia_itens (conferencia_id, ordem, tipo, funcionario_id, folha, atual, acao_sugerida, opcoes, motivo, origens, decisao)
    VALUES (
      v_id, v_ordem, v_i->>'tipo', (v_i->>'funcionario_id')::uuid,
      nullif(v_i->'folha', 'null'::jsonb), nullif(v_i->'atual', 'null'::jsonb), v_i->>'acao', v_opcoes,
      coalesce(v_i->>'motivo', ''), ARRAY(SELECT jsonb_array_elements_text(coalesce(v_i->'origens', '[]'::jsonb))),
      CASE WHEN v_i->>'tipo' = 'CORRESPONDENTE' THEN 'SEM_ACAO' ELSE 'PENDENTE' END
    );
  END LOOP;

  PERFORM public.log_audit('CONFERENCIA_CRIADA', 'conferencias', v_id::text,
    format('Importação oficial de %s (%s): %s linhas, nenhuma alteração aplicada%s', v_empresa, left(_arquivo->>'nome', 120), _resumo->>'total_folha',
      CASE WHEN v_primeira THEN '; primeira importação da empresa' ELSE '' END), NULL, _resumo, NULL);
  RETURN v_id;
END;
$$;

-- ============================================================
-- 5. Quadro completo: só depois da primeira importação, com confirmação textual
-- ============================================================
CREATE OR REPLACE FUNCTION public.conferencia_confirmar_quadro(_id UUID, _confirmacao TEXT)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_c public.conferencias%ROWTYPE;
BEGIN
  IF NOT public.has_role(v_uid, 'gestor'::public.app_role) THEN
    RAISE EXCEPTION 'PERMISSAO: apenas o Gestor pode confirmar o quadro completo.';
  END IF;
  SELECT * INTO v_c FROM public.conferencias WHERE id = _id FOR UPDATE;
  IF NOT FOUND OR v_c.status <> 'ABERTA' THEN RAISE EXCEPTION 'CONFERENCIA_ESTADO: conferência não encontrada ou encerrada.'; END IF;
  IF v_c.criada_em < now() - interval '7 days' THEN
    RAISE EXCEPTION 'CONFERENCIA_EXPIRADA: importação aberta há mais de 7 dias. Descarte e envie a planilha de novo.';
  END IF;
  IF v_c.empresa IS NULL OR v_c.primeira_da_empresa IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONFERENCIA_PRIMEIRA: na primeira importação da empresa os ausentes são apenas sinalizados.';
  END IF;
  IF _confirmacao IS DISTINCT FROM 'QUADRO COMPLETO ' || v_c.empresa THEN
    RAISE EXCEPTION 'CONFERENCIA_CONFIRMACAO: digite QUADRO COMPLETO % para confirmar.', v_c.empresa;
  END IF;
  UPDATE public.conferencias SET quadro_completo_em = now(), quadro_completo_por = v_uid, revisao = revisao + 1 WHERE id = _id;
  PERFORM public.log_audit('CONFERENCIA_QUADRO_COMPLETO', 'conferencias', _id::text,
    format('Gestor confirmou que a planilha representa o quadro completo de %s', v_c.empresa), NULL, NULL, NULL);
  RETURN v_c.revisao + 1;
END;
$$;

-- ============================================================
-- 6. Decidir: devolve a nova revisão. Validações por ação.
-- ============================================================
DROP FUNCTION public.conferencia_decidir(UUID, TEXT, TEXT, TEXT, JSONB);
CREATE FUNCTION public.conferencia_decidir(_item UUID, _decisao TEXT, _acao TEXT DEFAULT NULL, _justificativa TEXT DEFAULT NULL, _dados JSONB DEFAULT NULL)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_i public.conferencia_itens%ROWTYPE;
  v_c public.conferencias%ROWTYPE;
  v_just TEXT := btrim(_justificativa);
BEGIN
  IF NOT public.has_role(v_uid, 'gestor'::public.app_role) THEN
    RAISE EXCEPTION 'PERMISSAO: apenas o Gestor pode revisar uma conferência.';
  END IF;

  SELECT * INTO v_i FROM public.conferencia_itens WHERE id = _item;
  IF NOT FOUND THEN RAISE EXCEPTION 'CONFERENCIA_ESTADO: item não encontrado.'; END IF;
  SELECT * INTO v_c FROM public.conferencias WHERE id = v_i.conferencia_id FOR UPDATE;
  IF v_c.status <> 'ABERTA' THEN RAISE EXCEPTION 'CONFERENCIA_ESTADO: esta conferência já foi encerrada.'; END IF;
  IF v_c.criada_em < now() - interval '7 days' THEN
    RAISE EXCEPTION 'CONFERENCIA_EXPIRADA: importação aberta há mais de 7 dias. Descarte e envie a planilha de novo.';
  END IF;
  SELECT * INTO v_i FROM public.conferencia_itens WHERE id = _item FOR UPDATE;

  IF v_i.decisao = 'SEM_ACAO' THEN RAISE EXCEPTION 'CONFERENCIA_ESTADO: este item não precisa de revisão.'; END IF;
  IF _decisao NOT IN ('APROVADA', 'REJEITADA', 'REVISADA') THEN RAISE EXCEPTION 'CONFERENCIA_DADOS: decisão inválida.'; END IF;

  IF _decisao = 'APROVADA' THEN
    IF _acao IS NULL OR NOT _acao = ANY (v_i.opcoes) THEN
      RAISE EXCEPTION 'CONFERENCIA_ACAO: esta ação não está disponível para o item.';
    END IF;
    IF (_acao IN ('CORRIGIR_CPF', 'PREENCHER_CPF', 'REATIVAR', 'CORRIGIR_RE', 'CORRIGIR_EMPRESA', 'INATIVAR') OR (_acao = 'CADASTRAR' AND v_i.tipo = 'PENDENCIA')
        OR (_acao = 'ATUALIZAR_CARGO' AND 'Freelancer' IN (coalesce(v_i.atual->>'cargo', ''), coalesce(v_i.folha->>'cargo_sistema', ''))))
       AND NOT public.texto_justificativa_valido(v_just) THEN
      RAISE EXCEPTION 'CONFERENCIA_JUSTIFICATIVA: informe uma justificativa com pelo menos 10 letras ou números.';
    END IF;
    IF _acao = 'INATIVAR' AND (v_c.primeira_da_empresa IS DISTINCT FROM false OR v_c.quadro_completo_em IS NULL) THEN
      RAISE EXCEPTION 'CONFERENCIA_QUADRO: inativar exige importação posterior à primeira e quadro completo confirmado.';
    END IF;
    IF _acao IN ('CORRIGIR_CPF', 'PREENCHER_CPF', 'CADASTRAR') AND NOT public.cpf_valido(v_i.folha->>'cpf') THEN
      RAISE EXCEPTION 'CONFERENCIA_CPF: CPF inválido.';
    END IF;
    IF _acao IN ('ATUALIZAR_NOME', 'CADASTRAR') AND coalesce(btrim(v_i.folha->>'nome'), '') = '' THEN
      RAISE EXCEPTION 'CONFERENCIA_DADOS: a planilha não traz o nome.';
    END IF;
    IF _acao IN ('CORRIGIR_RE', 'CORRIGIR_EMPRESA') AND coalesce(btrim(v_i.folha->>'re'), '') = '' THEN
      RAISE EXCEPTION 'CONFERENCIA_DADOS: a planilha não traz o RE.';
    END IF;
    IF _acao = 'ATUALIZAR_CARGO' AND coalesce(v_i.folha->>'cargo_sistema', '') NOT IN ('Vigilante', 'Porteiro', 'ASG', 'Recepcionista', 'Manutencista', 'Freelancer') THEN
      RAISE EXCEPTION 'CONFERENCIA_DADOS: cargo da planilha não reconhecido.';
    END IF;
    IF _acao = 'CADASTRAR' AND (
      coalesce(btrim(_dados->>'re'), '') = ''
      OR coalesce(_dados->>'cargo', '') NOT IN ('Vigilante', 'Porteiro', 'ASG', 'Recepcionista', 'Manutencista', 'Freelancer')
    ) THEN
      RAISE EXCEPTION 'CONFERENCIA_DADOS: novo cadastro exige nome, RE e cargo válido.';
    END IF;
  END IF;

  UPDATE public.conferencia_itens
     SET decisao = _decisao,
         acao = CASE WHEN _decisao = 'APROVADA' THEN _acao END,
         justificativa = v_just,
         dados = CASE WHEN _decisao = 'APROVADA' AND _acao = 'CADASTRAR' THEN jsonb_strip_nulls(jsonb_build_object('re', btrim(_dados->>'re'), 'cargo', _dados->>'cargo',
                   'empresa', coalesce(v_c.empresa, nullif(_dados->>'empresa', '')))) END,
         decidido_por = v_uid, decidido_em = now()
   WHERE id = _item;
  UPDATE public.conferencias SET revisao = revisao + 1 WHERE id = v_c.id;

  PERFORM public.log_audit('CONFERENCIA_DECISAO', 'conferencia_itens', _item::text,
    format('Decisão %s no item %s (%s)', _decisao, v_i.ordem, v_i.tipo), NULL,
    jsonb_build_object('conferencia_id', v_i.conferencia_id, 'funcionario_id', v_i.funcionario_id, 'decisao', _decisao, 'acao', _acao), v_just);
  RETURN v_c.revisao + 1;
END;
$$;

-- ============================================================
-- 7. Inativação em lote: confirmação forte, uma decisão e um registro de auditoria por item
-- ============================================================
CREATE OR REPLACE FUNCTION public.conferencia_inativar_lote(_id UUID, _itens UUID[], _justificativa TEXT, _confirmacao TEXT)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_c public.conferencias%ROWTYPE;
  v_just TEXT := btrim(_justificativa);
  v_n INT := coalesce(cardinality(_itens), 0);
  v_validos INT;
  v_item UUID;
BEGIN
  IF NOT public.has_role(v_uid, 'gestor'::public.app_role) THEN
    RAISE EXCEPTION 'PERMISSAO: apenas o Gestor pode revisar uma conferência.';
  END IF;
  SELECT * INTO v_c FROM public.conferencias WHERE id = _id FOR UPDATE;
  IF NOT FOUND OR v_c.status <> 'ABERTA' THEN RAISE EXCEPTION 'CONFERENCIA_ESTADO: conferência não encontrada ou encerrada.'; END IF;
  IF v_c.criada_em < now() - interval '7 days' THEN
    RAISE EXCEPTION 'CONFERENCIA_EXPIRADA: importação aberta há mais de 7 dias. Descarte e envie a planilha de novo.';
  END IF;
  IF v_c.primeira_da_empresa IS DISTINCT FROM false OR v_c.quadro_completo_em IS NULL THEN
    RAISE EXCEPTION 'CONFERENCIA_QUADRO: inativar exige importação posterior à primeira e quadro completo confirmado.';
  END IF;
  IF NOT public.texto_justificativa_valido(v_just) THEN
    RAISE EXCEPTION 'CONFERENCIA_JUSTIFICATIVA: informe uma justificativa com pelo menos 10 letras ou números.';
  END IF;
  IF v_n = 0 OR _confirmacao IS DISTINCT FROM format('INATIVAR %s %s', v_n, v_c.empresa) THEN
    RAISE EXCEPTION 'CONFERENCIA_CONFIRMACAO: digite INATIVAR % % para confirmar.', v_n, v_c.empresa;
  END IF;
  SELECT count(DISTINCT i.id) INTO v_validos FROM public.conferencia_itens i
   WHERE i.id = ANY (_itens) AND i.conferencia_id = _id AND i.tipo = 'AUSENTE' AND 'INATIVAR' = ANY (i.opcoes);
  IF v_validos <> v_n THEN RAISE EXCEPTION 'CONFERENCIA_ACAO: há itens que não são ausentes desta importação.'; END IF;

  FOREACH v_item IN ARRAY _itens LOOP
    UPDATE public.conferencia_itens SET decisao = 'APROVADA', acao = 'INATIVAR', justificativa = v_just, dados = NULL,
           decidido_por = v_uid, decidido_em = now() WHERE id = v_item;
    PERFORM public.log_audit('CONFERENCIA_DECISAO', 'conferencia_itens', v_item::text, 'Decisão APROVADA (inativação em lote)', NULL,
      jsonb_build_object('conferencia_id', _id, 'funcionario_id', (SELECT funcionario_id FROM public.conferencia_itens WHERE id = v_item),
        'decisao', 'APROVADA', 'acao', 'INATIVAR', 'lote', v_n), v_just);
  END LOOP;
  UPDATE public.conferencias SET revisao = revisao + 1 WHERE id = _id;
  RETURN v_c.revisao + 1;
END;
$$;

-- ============================================================
-- 8. Aplicar: revisão conferida; conflito por campo; novas ações; registra a primeira importação.
-- ============================================================
DROP FUNCTION public.conferencia_aplicar(UUID, TEXT);
CREATE FUNCTION public.conferencia_aplicar(_id UUID, _confirmacao TEXT, _revisao INT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_c public.conferencias%ROWTYPE;
  v_i public.conferencia_itens%ROWTYPE;
  v_f public.funcionarios%ROWTYPE;
  v_n INT;
  v_aplicados INT := 0;
  v_conflitos INT := 0;
  v_conflito TEXT;
  v_novo UUID;
  v_cpf TEXT;
  v_atual_cpf TEXT;
  v_re TEXT;
  v_resultado JSONB;
BEGIN
  IF NOT public.has_role(v_uid, 'gestor'::public.app_role) THEN
    RAISE EXCEPTION 'PERMISSAO: apenas o Gestor pode aplicar uma conferência.';
  END IF;

  SELECT * INTO v_c FROM public.conferencias WHERE id = _id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CONFERENCIA_ESTADO: conferência não encontrada.'; END IF;
  IF v_c.status <> 'ABERTA' THEN RAISE EXCEPTION 'CONFERENCIA_ESTADO: esta conferência já foi encerrada.'; END IF;
  IF v_c.criada_em < now() - interval '7 days' THEN
    RAISE EXCEPTION 'CONFERENCIA_EXPIRADA: importação aberta há mais de 7 dias. Descarte e envie a planilha de novo.';
  END IF;
  IF _revisao IS DISTINCT FROM v_c.revisao THEN
    RAISE EXCEPTION 'CONFERENCIA_ALTERADA: as decisões mudaram depois que a tela foi carregada. Recarregue e confira antes de aplicar.';
  END IF;

  SELECT count(*) INTO v_n FROM public.conferencia_itens WHERE conferencia_id = _id AND decisao = 'APROVADA';
  IF _confirmacao IS DISTINCT FROM format('APLICAR %s', v_n) THEN
    RAISE EXCEPTION 'CONFERENCIA_CONFIRMACAO: confirmação incorreta. Digite APLICAR % para confirmar.', v_n;
  END IF;

  FOR v_i IN
    SELECT * FROM public.conferencia_itens WHERE conferencia_id = _id AND decisao = 'APROVADA' ORDER BY funcionario_id NULLS LAST, ordem
  LOOP
    v_conflito := NULL;
    v_novo := NULL;
    v_cpf := v_i.folha->>'cpf';
    v_atual_cpf := v_i.atual->>'cpf';
    v_re := btrim(v_i.folha->>'re');

    IF v_i.acao = 'CADASTRAR' THEN
      IF EXISTS (SELECT 1 FROM public.funcionarios WHERE public.cpf_digitos(cpf) = v_cpf) THEN
        v_conflito := 'CPF já cadastrado depois da leitura';
      ELSE
        BEGIN
          INSERT INTO public.funcionarios (nome, cpf, re, cargo, empresa, turno, status, data_admissao)
          VALUES (v_i.folha->>'nome', v_cpf, v_i.dados->>'re', v_i.dados->>'cargo', v_i.dados->>'empresa', 'Integral', 'ativo', (v_i.folha->>'admissao')::date)
          RETURNING id INTO v_novo;
        EXCEPTION WHEN unique_violation THEN v_conflito := 'CPF já cadastrado por outra operação';
        END;
      END IF;
    ELSE
      SELECT * INTO v_f FROM public.funcionarios WHERE id = v_i.funcionario_id FOR UPDATE;
      -- Identidade (CPF) sempre; demais campos só os que a ação depende, para que dois itens do mesmo cadastro não se anulem.
      IF NOT FOUND
         OR (CASE WHEN v_atual_cpf LIKE '***%' THEN public.cpf_mascarado(v_f.cpf) IS DISTINCT FROM v_atual_cpf
                  ELSE public.cpf_digitos(v_f.cpf) IS DISTINCT FROM public.cpf_digitos(v_atual_cpf) END)
         OR (v_i.acao = 'ATUALIZAR_NOME' AND v_f.nome IS DISTINCT FROM v_i.atual->>'nome')
         OR (v_i.acao IN ('ATUALIZAR_CARGO', 'INATIVAR') AND v_f.cargo IS DISTINCT FROM v_i.atual->>'cargo')
         OR (v_i.acao IN ('CORRIGIR_RE', 'CORRIGIR_EMPRESA') AND (v_f.re IS DISTINCT FROM v_i.atual->>'re' OR v_f.empresa IS DISTINCT FROM v_i.atual->>'empresa'))
         OR (v_i.acao IN ('REATIVAR', 'INATIVAR', 'PREENCHER_CPF', 'CORRIGIR_CPF') AND (v_f.status IS DISTINCT FROM v_i.atual->>'status' OR v_f.nome IS DISTINCT FROM v_i.atual->>'nome')) THEN
        v_conflito := 'Cadastro alterado depois da leitura da planilha';
      ELSIF v_i.acao = 'ATUALIZAR_NOME' THEN
        UPDATE public.funcionarios SET nome = v_i.folha->>'nome' WHERE id = v_f.id;
      ELSIF v_i.acao = 'ATUALIZAR_CARGO' THEN
        UPDATE public.funcionarios SET cargo = v_i.folha->>'cargo_sistema' WHERE id = v_f.id;
      ELSIF v_i.acao IN ('CORRIGIR_RE', 'CORRIGIR_EMPRESA') THEN
        IF EXISTS (SELECT 1 FROM public.funcionarios WHERE empresa = v_c.empresa AND btrim(re) = v_re AND id <> v_f.id) THEN
          v_conflito := 'RE já usado por outro funcionário nesta empresa';
        ELSE
          UPDATE public.funcionarios SET re = v_re, empresa = v_c.empresa WHERE id = v_f.id;
        END IF;
      ELSIF v_i.acao IN ('PREENCHER_CPF', 'CORRIGIR_CPF') THEN
        IF v_i.acao = 'PREENCHER_CPF' AND public.cpf_digitos(v_f.cpf) IS NOT NULL THEN
          v_conflito := 'Cadastro já tem CPF';
        ELSIF EXISTS (SELECT 1 FROM public.funcionarios WHERE public.cpf_digitos(cpf) = v_cpf AND id <> v_f.id) THEN
          v_conflito := 'CPF vinculado a outro funcionário';
        ELSE
          PERFORM set_config('app.cpf_justificativa', v_i.justificativa, true);
          BEGIN
            UPDATE public.funcionarios SET cpf = v_cpf WHERE id = v_f.id;
          EXCEPTION WHEN unique_violation THEN v_conflito := 'CPF vinculado a outro funcionário por outra operação';
          END;
          PERFORM set_config('app.cpf_justificativa', '', true);
        END IF;
      ELSIF v_i.acao = 'REATIVAR' THEN
        UPDATE public.funcionarios SET status = 'ativo', reativacao_motivo = v_i.justificativa WHERE id = v_f.id;
      ELSIF v_i.acao = 'INATIVAR' THEN
        IF v_c.primeira_da_empresa IS DISTINCT FROM false OR v_c.quadro_completo_em IS NULL THEN
          v_conflito := 'Quadro completo não confirmado';
        ELSIF v_f.empresa IS DISTINCT FROM v_c.empresa THEN
          v_conflito := 'Funcionário não pertence à empresa da planilha';
        ELSIF v_f.cargo = 'Freelancer' THEN
          v_conflito := 'Freelancer não é inativado por ausência na planilha oficial';
        ELSE
          UPDATE public.funcionarios SET status = 'inativo' WHERE id = v_f.id;
        END IF;
      END IF;
    END IF;

    UPDATE public.conferencia_itens
       SET resultado = CASE WHEN v_conflito IS NULL THEN 'APLICADO' ELSE 'CONFLITO' END,
           resultado_detalhe = v_conflito, novo_funcionario_id = v_novo
     WHERE id = v_i.id;

    IF v_conflito IS NULL THEN
      v_aplicados := v_aplicados + 1;
      PERFORM public.log_audit('CONFERENCIA_ITEM_APLICADO', 'conferencia_itens', v_i.id::text,
        format('%s pela importação oficial', v_i.acao), NULL,
        jsonb_build_object('conferencia_id', _id, 'funcionario_id', coalesce(v_novo, v_i.funcionario_id), 'acao', v_i.acao), v_i.justificativa);
    ELSE
      v_conflitos := v_conflitos + 1;
    END IF;
  END LOOP;

  v_resultado := jsonb_build_object('aplicados', v_aplicados, 'conflitos', v_conflitos);
  UPDATE public.conferencias SET status = 'CONCLUIDA', resultado = v_resultado, encerrada_por = v_uid, encerrada_em = now() WHERE id = _id;
  IF v_c.empresa IS NOT NULL THEN
    INSERT INTO public.importacao_empresas (empresa, conferencia_id, validada_por) VALUES (v_c.empresa, _id, v_uid) ON CONFLICT (empresa) DO NOTHING;
  END IF;
  PERFORM public.conferencia_mascarar_itens(_id);
  PERFORM public.log_audit('CONFERENCIA_APLICADA', 'conferencias', _id::text,
    format('Importação aplicada: %s alterações, %s conflitos', v_aplicados, v_conflitos), NULL, v_resultado, NULL);
  RETURN v_resultado;
END;
$$;

-- ============================================================
-- 9. Permissões
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.empresa_valida(TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.funcionario_cpf(UUID), public.funcionarios_cpfs(), public.funcionario_alterar_cpf(UUID, TEXT, TEXT),
  public.conferencia_criar(JSONB, JSONB, JSONB), public.conferencia_decidir(UUID, TEXT, TEXT, TEXT, JSONB), public.conferencia_confirmar_quadro(UUID, TEXT),
  public.conferencia_inativar_lote(UUID, UUID[], TEXT, TEXT), public.conferencia_aplicar(UUID, TEXT, INT) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.funcionario_cpf(UUID), public.funcionarios_cpfs(), public.funcionario_alterar_cpf(UUID, TEXT, TEXT),
  public.conferencia_criar(JSONB, JSONB, JSONB), public.conferencia_decidir(UUID, TEXT, TEXT, TEXT, JSONB), public.conferencia_confirmar_quadro(UUID, TEXT),
  public.conferencia_inativar_lote(UUID, UUID[], TEXT, TEXT), public.conferencia_aplicar(UUID, TEXT, INT) TO authenticated;

-- ============================================================
-- 10. Guarda final
-- ============================================================
DO $$
DECLARE r TEXT;
BEGIN
  FOREACH r IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    IF has_column_privilege(r, 'public.funcionarios', 'cpf', 'SELECT') OR has_column_privilege(r, 'public.funcionarios', 'cpf', 'UPDATE') THEN
      RAISE EXCEPTION 'Abortado: % ainda lê ou altera funcionarios.cpf.', r;
    END IF;
  END LOOP;
  IF NOT has_column_privilege('authenticated', 'public.funcionarios', 'nome', 'SELECT') THEN
    RAISE EXCEPTION 'Abortado: authenticated perdeu a leitura das demais colunas.';
  END IF;
  IF has_table_privilege('authenticated', 'public.importacao_empresas', 'INSERT') OR has_table_privilege('authenticated', 'public.importacao_empresas', 'UPDATE') THEN
    RAISE EXCEPTION 'Abortado: authenticated escreve em importacao_empresas.';
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
