-- Conferência de funcionários contra folha de pagamento. NÃO APLICADA. Requer a Fase 1A (20261105120000 e 20261105120100).
-- Reversão: supabase/rollback/20261106120000_rollback.sql.
--
-- Regras:
--  * Nada muda em funcionários até o Gestor aprovar item a item e confirmar a aplicação.
--  * Ações possíveis são lista fechada: atualizar nome, preencher CPF, corrigir CPF, cadastrar, reativar. Inativar NÃO existe aqui:
--    funcionário ausente da folha é só sinalizado, porque uma folha isolada não comprova desligamento.
--  * Só o Gestor com conta ativa lê ou executa. Sem escrita direta: tudo passa pelas RPCs, que revalidam tudo.
--  * Na aplicação, item cujo cadastro mudou depois da leitura vira CONFLITO e não é aplicado.
--  * Reativação usa o UPDATE normal: os triggers da Fase 1A cuidam de motivo, período e auditoria.
--  * Retenção: CPF completo só nos itens abertos que precisam dele. Ao concluir ou descartar, é mascarado.
--    Não há hash de CPF: com tão poucas combinações ele seria reversível e não anonimiza. audit_logs de funcionarios segue guardando
--    o valor antigo e novo do cadastro, como em qualquer edição.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $$
BEGIN
  IF to_regclass('public.funcionario_inatividades') IS NULL OR to_regprocedure('public.conta_ativa()') IS NULL THEN
    RAISE EXCEPTION 'Abortado: aplique antes as migrations da Fase 1A.';
  END IF;
END $$;

-- ============================================================
-- 1. Auxiliares internos
-- ============================================================
CREATE OR REPLACE FUNCTION public.cpf_valido(_cpf TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql IMMUTABLE
SET search_path = public
AS $$
DECLARE s INT; n INT; i INT; d INT;
BEGIN
  IF _cpf IS NULL OR _cpf !~ '^\d{11}$' OR _cpf ~ '^(\d)\1{10}$' THEN RETURN false; END IF;
  FOREACH n IN ARRAY ARRAY[9, 10] LOOP
    s := 0;
    FOR i IN 1..n LOOP s := s + substr(_cpf, i, 1)::int * (n + 2 - i); END LOOP;
    d := ((s * 10) % 11) % 10;
    IF d <> substr(_cpf, n + 1, 1)::int THEN RETURN false; END IF;
  END LOOP;
  RETURN true;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.cpf_valido(TEXT) FROM PUBLIC, anon, authenticated;

-- Cadastros antigos podem ter pontuação ou ter perdido zeros à esquerda: a comparação usa só os dígitos. Vazio vira NULL.
CREATE OR REPLACE FUNCTION public.cpf_digitos(_cpf TEXT)
RETURNS TEXT
LANGUAGE SQL IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE WHEN length(d) IN (9, 10) THEN lpad(d, 11, '0') ELSE nullif(d, '') END
  FROM (SELECT regexp_replace(_cpf, '[^0-9]', '', 'g') AS d) t
$$;
REVOKE EXECUTE ON FUNCTION public.cpf_digitos(TEXT) FROM PUBLIC, anon, authenticated;

-- Mesma regra de mascararCpf no app: valor já mascarado passa direto, para comparar snapshot e cadastro; o resto nunca sai aberto.
CREATE OR REPLACE FUNCTION public.cpf_mascarado(_cpf TEXT)
RETURNS TEXT
LANGUAGE SQL IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN _cpf IS NULL OR _cpf LIKE '***%' THEN _cpf
    WHEN d ~ '^[0-9]{11}$' THEN '***.' || substr(d, 4, 3) || '.' || substr(d, 7, 3) || '-**'
    ELSE '***'
  END
  FROM (SELECT regexp_replace(_cpf, '[^0-9]', '', 'g') AS d) t
$$;
REVOKE EXECUTE ON FUNCTION public.cpf_mascarado(TEXT) FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 2. Tabelas
-- ============================================================
CREATE TABLE public.conferencias (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  status        TEXT        NOT NULL DEFAULT 'ABERTA' CHECK (status IN ('ABERTA', 'CONCLUIDA', 'DESCARTADA')),
  arquivo_nome  TEXT        NOT NULL,
  arquivo_abas  TEXT[]      NOT NULL DEFAULT '{}',
  mapeamento    JSONB       NOT NULL DEFAULT '{}',
  linhas_ignoradas INT      NOT NULL DEFAULT 0,
  total_impresso INT,
  resumo        JSONB       NOT NULL,
  resultado     JSONB,
  criada_por    UUID        NOT NULL,
  criada_em     TIMESTAMPTZ NOT NULL DEFAULT now(),
  encerrada_por UUID,
  encerrada_em  TIMESTAMPTZ,
  motivo_descarte TEXT
);
-- Uma aberta por vez: duas revisões paralelas se invalidariam.
CREATE UNIQUE INDEX uq_conferencia_aberta ON public.conferencias ((true)) WHERE status = 'ABERTA';
CREATE INDEX idx_conferencias_criada_em ON public.conferencias (criada_em DESC);

CREATE TABLE public.conferencia_itens (
  id             UUID     PRIMARY KEY DEFAULT gen_random_uuid(),
  conferencia_id UUID     NOT NULL REFERENCES public.conferencias(id) ON DELETE RESTRICT,
  ordem          INT      NOT NULL,
  tipo           TEXT     NOT NULL CHECK (tipo IN ('CORRESPONDENTE', 'DIVERGENCIA_NOME', 'DIVERGENCIA_CPF', 'NOVO', 'INATIVO', 'AUSENTE', 'DUPLICADO', 'PENDENCIA')),
  funcionario_id UUID     REFERENCES public.funcionarios(id) ON DELETE RESTRICT,
  folha          JSONB,
  atual          JSONB,
  acao_sugerida  TEXT,
  opcoes         TEXT[]   NOT NULL DEFAULT '{}',
  motivo         TEXT     NOT NULL,
  origens        TEXT[]   NOT NULL DEFAULT '{}',
  decisao        TEXT     NOT NULL DEFAULT 'PENDENTE' CHECK (decisao IN ('PENDENTE', 'APROVADA', 'REJEITADA', 'REVISADA', 'SEM_ACAO')),
  acao           TEXT,
  dados          JSONB,
  justificativa  TEXT,
  decidido_por   UUID,
  decidido_em    TIMESTAMPTZ,
  resultado      TEXT     CHECK (resultado IN ('APLICADO', 'CONFLITO')),
  resultado_detalhe TEXT,
  novo_funcionario_id UUID REFERENCES public.funcionarios(id) ON DELETE RESTRICT,
  CONSTRAINT conferencia_itens_opcoes_validas
    CHECK (opcoes <@ ARRAY['ATUALIZAR_NOME', 'PREENCHER_CPF', 'CORRIGIR_CPF', 'CADASTRAR', 'REATIVAR']),
  CONSTRAINT conferencia_itens_acao_valida CHECK (acao IS NULL OR acao = ANY (opcoes)),
  CONSTRAINT conferencia_itens_ausente_sem_acao CHECK (tipo <> 'AUSENTE' OR (opcoes = '{}' AND acao IS NULL)),
  UNIQUE (conferencia_id, ordem)
);
CREATE INDEX idx_conferencia_itens_conferencia ON public.conferencia_itens (conferencia_id, tipo);
CREATE INDEX idx_conferencia_itens_funcionario ON public.conferencia_itens (funcionario_id);

ALTER TABLE public.conferencias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conferencia_itens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Gestor le conferencias" ON public.conferencias FOR SELECT TO authenticated
  USING ((SELECT public.has_role(auth.uid(), 'gestor'::public.app_role)));
CREATE POLICY "Gestor le itens de conferencia" ON public.conferencia_itens FOR SELECT TO authenticated
  USING ((SELECT public.has_role(auth.uid(), 'gestor'::public.app_role)));

REVOKE ALL ON public.conferencias, public.conferencia_itens FROM anon, authenticated, service_role;
GRANT SELECT ON public.conferencias, public.conferencia_itens TO authenticated;

-- conferencias não tem CPF: pode ir para audit_logs inteira. Itens têm decisão própria (colunas e log_audit sem CPF).
CREATE TRIGGER audit_conferencias AFTER INSERT OR UPDATE OR DELETE ON public.conferencias
  FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();

CREATE TRIGGER trg_conferencias_bloquear_exclusao BEFORE DELETE ON public.conferencias
  FOR EACH ROW EXECUTE FUNCTION public.tg_bloquear_exclusao('conferências não podem ser excluídas.');
CREATE TRIGGER trg_conferencias_bloquear_truncate BEFORE TRUNCATE ON public.conferencias
  FOR EACH STATEMENT EXECUTE FUNCTION public.tg_bloquear_exclusao('conferências não podem ser excluídas.');
CREATE TRIGGER trg_conferencia_itens_bloquear_exclusao BEFORE DELETE ON public.conferencia_itens
  FOR EACH ROW EXECUTE FUNCTION public.tg_bloquear_exclusao('itens de conferência não podem ser excluídos.');
CREATE TRIGGER trg_conferencia_itens_bloquear_truncate BEFORE TRUNCATE ON public.conferencia_itens
  FOR EACH STATEMENT EXECUTE FUNCTION public.tg_bloquear_exclusao('itens de conferência não podem ser excluídos.');

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
-- 5. Encerramento comum: tira CPF completo dos itens
-- ============================================================
CREATE OR REPLACE FUNCTION public.conferencia_mascarar_itens(_id UUID)
RETURNS VOID
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.conferencia_itens
     SET folha = CASE WHEN folha ? 'cpf' THEN jsonb_set(folha, '{cpf}', to_jsonb(public.cpf_mascarado(folha->>'cpf'))) ELSE folha END,
         atual = CASE WHEN atual ? 'cpf' AND atual->>'cpf' IS NOT NULL THEN jsonb_set(atual, '{cpf}', to_jsonb(public.cpf_mascarado(atual->>'cpf'))) ELSE atual END
   WHERE conferencia_id = _id
$$;
REVOKE EXECUTE ON FUNCTION public.conferencia_mascarar_itens(UUID) FROM PUBLIC, anon, authenticated;

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

-- ============================================================
-- 7. Descartar: encerra sem aplicar nada. O registro fica.
-- ============================================================
CREATE OR REPLACE FUNCTION public.conferencia_descartar(_id UUID, _motivo TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_status TEXT;
  v_motivo TEXT := btrim(_motivo);
BEGIN
  IF NOT public.has_role(v_uid, 'gestor'::public.app_role) THEN
    RAISE EXCEPTION 'PERMISSAO: apenas o Gestor pode descartar uma conferência.';
  END IF;
  IF NOT public.texto_justificativa_valido(v_motivo) THEN
    RAISE EXCEPTION 'CONFERENCIA_JUSTIFICATIVA: informe o motivo com pelo menos 10 letras ou números.';
  END IF;
  SELECT status INTO v_status FROM public.conferencias WHERE id = _id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CONFERENCIA_ESTADO: conferência não encontrada.'; END IF;
  IF v_status <> 'ABERTA' THEN RAISE EXCEPTION 'CONFERENCIA_ESTADO: esta conferência já foi encerrada.'; END IF;

  UPDATE public.conferencias SET status = 'DESCARTADA', motivo_descarte = v_motivo, encerrada_por = v_uid, encerrada_em = now() WHERE id = _id;
  PERFORM public.conferencia_mascarar_itens(_id);
  PERFORM public.log_audit('CONFERENCIA_DESCARTADA', 'conferencias', _id::text, 'Conferência descartada sem aplicar alterações', NULL, NULL, v_motivo);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.conferencia_criar(JSONB, JSONB, JSONB), public.conferencia_decidir(UUID, TEXT, TEXT, TEXT, JSONB),
  public.conferencia_aplicar(UUID, TEXT), public.conferencia_descartar(UUID, TEXT) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.conferencia_criar(JSONB, JSONB, JSONB), public.conferencia_decidir(UUID, TEXT, TEXT, TEXT, JSONB),
  public.conferencia_aplicar(UUID, TEXT), public.conferencia_descartar(UUID, TEXT) TO authenticated;

-- ============================================================
-- 8. Guarda final
-- ============================================================
DO $$
DECLARE r TEXT; t TEXT; p TEXT;
BEGIN
  FOREACH r IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    FOREACH t IN ARRAY ARRAY['public.conferencias', 'public.conferencia_itens'] LOOP
      FOREACH p IN ARRAY ARRAY['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'] LOOP
        IF has_table_privilege(r, t, p) THEN RAISE EXCEPTION 'Abortado: % ainda tem % em %.', r, p, t; END IF;
      END LOOP;
    END LOOP;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
