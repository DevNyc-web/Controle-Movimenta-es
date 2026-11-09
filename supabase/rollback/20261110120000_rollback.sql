-- Reverte 20261110120000 (Importação oficial e restrição do CPF). Executar o arquivo INTEIRO, antes do rollback 20261106120000.
-- Recusa rodar se já houver importação oficial registrada ou conferência com empresa: o histórico não é apagado por este arquivo.
-- As funções da Conferência voltam exatamente ao texto de 20261106120000 (copiado daquele arquivo).

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.importacao_empresas) OR EXISTS (SELECT 1 FROM public.conferencias WHERE empresa IS NOT NULL) THEN
    RAISE EXCEPTION 'Abortado sem alterações: há importações oficiais registradas. Exportar antes.';
  END IF;
END $$;

-- Auditoria: volta o texto original de 20260519000210 (CPF aberto em audit_logs)
CREATE OR REPLACE FUNCTION public.tg_audit_row()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_desc text;
  v_id text;
  v_entity text := TG_TABLE_NAME;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_id := (to_jsonb(OLD)->>'id');
    v_desc := format('Excluiu registro em %s (id %s)', v_entity, v_id);
    PERFORM public.log_audit('DELETE', v_entity, v_id, v_desc, to_jsonb(OLD), NULL, NULL);
    RETURN OLD;
  ELSIF TG_OP = 'UPDATE' THEN
    v_id := (to_jsonb(NEW)->>'id');
    v_desc := format('Atualizou registro em %s (id %s)', v_entity, v_id);
    PERFORM public.log_audit('UPDATE', v_entity, v_id, v_desc, to_jsonb(OLD), to_jsonb(NEW), NULL);
    RETURN NEW;
  ELSE
    v_id := (to_jsonb(NEW)->>'id');
    v_desc := format('Criou registro em %s (id %s)', v_entity, v_id);
    PERFORM public.log_audit('INSERT', v_entity, v_id, v_desc, NULL, to_jsonb(NEW), NULL);
    RETURN NEW;
  END IF;
END; $$;
REVOKE EXECUTE ON FUNCTION public.tg_audit_row() FROM PUBLIC, anon, authenticated;

-- CPF: volta a leitura e a alteração por tabela
DROP TRIGGER trg_funcionarios_cpf ON public.funcionarios;
DROP FUNCTION public.tg_funcionarios_cpf();
DO $$
DECLARE v_cols TEXT;
BEGIN
  SELECT string_agg(quote_ident(column_name), ', ') INTO v_cols FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'funcionarios' AND column_name <> 'cpf';
  EXECUTE format('REVOKE SELECT (%s), UPDATE (%s) ON public.funcionarios FROM authenticated', v_cols, v_cols);
END $$;
GRANT SELECT, UPDATE ON public.funcionarios TO authenticated;
DROP FUNCTION public.funcionario_alterar_cpf(UUID, TEXT, TEXT);
DROP FUNCTION public.funcionarios_cpfs();
DROP FUNCTION public.funcionario_cpf(UUID);

-- Conferência: funções novas saem, as anteriores voltam
DROP FUNCTION public.conferencia_inativar_lote(UUID, UUID[], TEXT, TEXT);
DROP FUNCTION public.conferencia_confirmar_quadro(UUID, TEXT);
DROP FUNCTION public.conferencia_aplicar(UUID, TEXT, INT);
DROP FUNCTION public.conferencia_decidir(UUID, TEXT, TEXT, TEXT, JSONB);

-- ============================================================
-- 3. Criar: grava a comparação. Não toca em funcionários.
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
BEGIN
  IF NOT public.has_role(v_uid, 'gestor'::public.app_role) THEN
    RAISE EXCEPTION 'PERMISSAO: apenas o Gestor pode criar uma conferência.';
  END IF;
  IF jsonb_typeof(_itens) IS DISTINCT FROM 'array' OR jsonb_array_length(_itens) > 25000 OR coalesce(btrim(_arquivo->>'nome'), '') = '' THEN
    RAISE EXCEPTION 'CONFERENCIA_DADOS: conferência sem arquivo ou com itens inválidos.';
  END IF;

  BEGIN
    INSERT INTO public.conferencias (arquivo_nome, arquivo_abas, mapeamento, linhas_ignoradas, total_impresso, resumo, criada_por)
    VALUES (
      left(_arquivo->>'nome', 255),
      ARRAY(SELECT jsonb_array_elements_text(coalesce(_arquivo->'abas', '[]'::jsonb))),
      coalesce(_arquivo->'mapeamento', '{}'::jsonb),
      coalesce((_arquivo->>'ignoradas')::int, 0),
      (_arquivo->>'total_impresso')::int,
      _resumo, v_uid
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
    format('Conferência do arquivo %s: %s linhas, nenhuma alteração aplicada', left(_arquivo->>'nome', 120), _resumo->>'total_folha'), NULL, _resumo, NULL);
  RETURN v_id;
END;
$$;

-- ============================================================
-- 4. Decidir: registra a revisão do Gestor. Pode mudar de ideia até aplicar. Não toca em funcionários.
-- ============================================================
CREATE OR REPLACE FUNCTION public.conferencia_decidir(_item UUID, _decisao TEXT, _acao TEXT DEFAULT NULL, _justificativa TEXT DEFAULT NULL, _dados JSONB DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_i public.conferencia_itens%ROWTYPE;
  v_status TEXT;
  v_just TEXT := btrim(_justificativa);
BEGIN
  IF NOT public.has_role(v_uid, 'gestor'::public.app_role) THEN
    RAISE EXCEPTION 'PERMISSAO: apenas o Gestor pode revisar uma conferência.';
  END IF;

  SELECT * INTO v_i FROM public.conferencia_itens WHERE id = _item;
  IF NOT FOUND THEN RAISE EXCEPTION 'CONFERENCIA_ESTADO: item não encontrado.'; END IF;
  SELECT status INTO v_status FROM public.conferencias WHERE id = v_i.conferencia_id FOR UPDATE;
  IF v_status <> 'ABERTA' THEN RAISE EXCEPTION 'CONFERENCIA_ESTADO: esta conferência já foi encerrada.'; END IF;
  SELECT * INTO v_i FROM public.conferencia_itens WHERE id = _item FOR UPDATE;

  IF v_i.decisao = 'SEM_ACAO' THEN RAISE EXCEPTION 'CONFERENCIA_ESTADO: este item não precisa de revisão.'; END IF;
  IF _decisao NOT IN ('APROVADA', 'REJEITADA', 'REVISADA') THEN RAISE EXCEPTION 'CONFERENCIA_DADOS: decisão inválida.'; END IF;

  IF _decisao = 'APROVADA' THEN
    IF _acao IS NULL OR NOT _acao = ANY (v_i.opcoes) THEN
      RAISE EXCEPTION 'CONFERENCIA_ACAO: esta ação não está disponível para o item.';
    END IF;
    -- CADASTRAR a partir de pendência: já existe cadastro com este nome, pode ser a mesma pessoa
    IF (_acao IN ('CORRIGIR_CPF', 'PREENCHER_CPF', 'REATIVAR') OR (_acao = 'CADASTRAR' AND v_i.tipo = 'PENDENCIA')) AND NOT public.texto_justificativa_valido(v_just) THEN
      RAISE EXCEPTION 'CONFERENCIA_JUSTIFICATIVA: informe uma justificativa com pelo menos 10 letras ou números.';
    END IF;
    IF _acao IN ('CORRIGIR_CPF', 'PREENCHER_CPF', 'CADASTRAR') AND NOT public.cpf_valido(v_i.folha->>'cpf') THEN
      RAISE EXCEPTION 'CONFERENCIA_CPF: CPF inválido.';
    END IF;
    IF _acao IN ('ATUALIZAR_NOME', 'CADASTRAR') AND coalesce(btrim(v_i.folha->>'nome'), '') = '' THEN
      RAISE EXCEPTION 'CONFERENCIA_DADOS: a folha não traz o nome.';
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
         dados = CASE WHEN _decisao = 'APROVADA' AND _acao = 'CADASTRAR' THEN jsonb_strip_nulls(jsonb_build_object('re', btrim(_dados->>'re'), 'cargo', _dados->>'cargo', 'empresa', nullif(_dados->>'empresa', ''))) END,
         decidido_por = v_uid, decidido_em = now()
   WHERE id = _item;

  PERFORM public.log_audit('CONFERENCIA_DECISAO', 'conferencia_itens', _item::text,
    format('Decisão %s no item %s (%s)', _decisao, v_i.ordem, v_i.tipo), NULL,
    jsonb_build_object('conferencia_id', v_i.conferencia_id, 'funcionario_id', v_i.funcionario_id, 'decisao', _decisao, 'acao', _acao), v_just);
END;
$$;

-- ============================================================
-- 6. Aplicar: única função que altera funcionários. Lista fechada de ações, sem caminho para inativar nem excluir.
--    Transação única. Mudança no cadastro depois da leitura vira CONFLITO no item, sem aplicar.
-- ============================================================
CREATE OR REPLACE FUNCTION public.conferencia_aplicar(_id UUID, _confirmacao TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_status TEXT;
  v_i public.conferencia_itens%ROWTYPE;
  v_f public.funcionarios%ROWTYPE;
  v_n INT;
  v_aplicados INT := 0;
  v_conflitos INT := 0;
  v_conflito TEXT;
  v_novo UUID;
  v_cpf TEXT;
  v_atual_cpf TEXT;
  v_resultado JSONB;
BEGIN
  IF NOT public.has_role(v_uid, 'gestor'::public.app_role) THEN
    RAISE EXCEPTION 'PERMISSAO: apenas o Gestor pode aplicar uma conferência.';
  END IF;

  SELECT status INTO v_status FROM public.conferencias WHERE id = _id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CONFERENCIA_ESTADO: conferência não encontrada.'; END IF;
  IF v_status <> 'ABERTA' THEN RAISE EXCEPTION 'CONFERENCIA_ESTADO: esta conferência já foi encerrada.'; END IF;

  SELECT count(*) INTO v_n FROM public.conferencia_itens WHERE conferencia_id = _id AND decisao = 'APROVADA';
  IF v_n = 0 THEN RAISE EXCEPTION 'CONFERENCIA_ESTADO: nenhum item aprovado para aplicar.'; END IF;
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
      IF NOT FOUND OR v_f.nome IS DISTINCT FROM v_i.atual->>'nome' OR v_f.status IS DISTINCT FROM v_i.atual->>'status'
         -- A máscara esconde 5 dígitos: quem guardou o CPF completo (correção) compara todos.
         OR (CASE WHEN v_atual_cpf LIKE '***%' THEN public.cpf_mascarado(v_f.cpf) IS DISTINCT FROM v_atual_cpf
                  ELSE public.cpf_digitos(v_f.cpf) IS DISTINCT FROM public.cpf_digitos(v_atual_cpf) END) THEN
        v_conflito := 'Cadastro alterado depois da leitura da folha';
      ELSIF v_i.acao = 'ATUALIZAR_NOME' THEN
        UPDATE public.funcionarios SET nome = v_i.folha->>'nome' WHERE id = v_f.id;
      ELSIF v_i.acao IN ('PREENCHER_CPF', 'CORRIGIR_CPF') THEN
        IF v_i.acao = 'PREENCHER_CPF' AND public.cpf_digitos(v_f.cpf) IS NOT NULL THEN
          v_conflito := 'Cadastro já tem CPF';
        ELSIF EXISTS (SELECT 1 FROM public.funcionarios WHERE public.cpf_digitos(cpf) = v_cpf AND id <> v_f.id) THEN
          v_conflito := 'CPF vinculado a outro funcionário';
        ELSE
          UPDATE public.funcionarios SET cpf = v_cpf WHERE id = v_f.id;
        END IF;
      ELSIF v_i.acao = 'REATIVAR' THEN
        UPDATE public.funcionarios SET status = 'ativo', reativacao_motivo = v_i.justificativa WHERE id = v_f.id;
      END IF;
    END IF;

    UPDATE public.conferencia_itens
       SET resultado = CASE WHEN v_conflito IS NULL THEN 'APLICADO' ELSE 'CONFLITO' END,
           resultado_detalhe = v_conflito, novo_funcionario_id = v_novo
     WHERE id = v_i.id;

    IF v_conflito IS NULL THEN
      v_aplicados := v_aplicados + 1;
      PERFORM public.log_audit('CONFERENCIA_ITEM_APLICADO', 'conferencia_itens', v_i.id::text,
        format('%s pela conferência', v_i.acao), NULL,
        jsonb_build_object('conferencia_id', _id, 'funcionario_id', coalesce(v_novo, v_i.funcionario_id), 'acao', v_i.acao), v_i.justificativa);
    ELSE
      v_conflitos := v_conflitos + 1;
    END IF;
  END LOOP;

  v_resultado := jsonb_build_object('aplicados', v_aplicados, 'conflitos', v_conflitos);
  UPDATE public.conferencias SET status = 'CONCLUIDA', resultado = v_resultado, encerrada_por = v_uid, encerrada_em = now() WHERE id = _id;
  PERFORM public.conferencia_mascarar_itens(_id);
  PERFORM public.log_audit('CONFERENCIA_APLICADA', 'conferencias', _id::text,
    format('Conferência aplicada: %s alterações, %s conflitos', v_aplicados, v_conflitos), NULL, v_resultado, NULL);
  RETURN v_resultado;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.conferencia_criar(JSONB, JSONB, JSONB), public.conferencia_decidir(UUID, TEXT, TEXT, TEXT, JSONB),
  public.conferencia_aplicar(UUID, TEXT) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.conferencia_criar(JSONB, JSONB, JSONB), public.conferencia_decidir(UUID, TEXT, TEXT, TEXT, JSONB),
  public.conferencia_aplicar(UUID, TEXT) TO authenticated;

ALTER TABLE public.conferencia_itens
  DROP CONSTRAINT conferencia_itens_inativar_so_ausente,
  DROP CONSTRAINT conferencia_itens_ausente_so_inativa,
  DROP CONSTRAINT conferencia_itens_opcoes_validas,
  DROP CONSTRAINT conferencia_itens_tipo_check,
  ADD CONSTRAINT conferencia_itens_tipo_check CHECK (tipo IN ('CORRESPONDENTE', 'DIVERGENCIA_NOME', 'DIVERGENCIA_CPF', 'NOVO', 'INATIVO', 'AUSENTE', 'DUPLICADO', 'PENDENCIA')),
  ADD CONSTRAINT conferencia_itens_opcoes_validas CHECK (opcoes <@ ARRAY['ATUALIZAR_NOME', 'PREENCHER_CPF', 'CORRIGIR_CPF', 'CADASTRAR', 'REATIVAR']),
  ADD CONSTRAINT conferencia_itens_ausente_sem_acao CHECK (tipo <> 'AUSENTE' OR (opcoes = '{}' AND acao IS NULL));

ALTER TABLE public.conferencias
  DROP CONSTRAINT conferencias_quadro_so_depois_da_primeira,
  DROP COLUMN revisao, DROP COLUMN quadro_completo_por, DROP COLUMN quadro_completo_em, DROP COLUMN primeira_da_empresa, DROP COLUMN empresa;

DROP TABLE public.importacao_empresas;
DROP FUNCTION public.empresa_valida(TEXT);

NOTIFY pgrst, 'reload schema';

COMMIT;
