-- Fase 1A: funcionário inativo, períodos de inatividade, proteção de FTs e proibição de exclusão física.
-- NÃO APLICADA. Revisar antes (Fase 1B). Não usar `supabase db push`: o histórico de migrations de produção está desalinhado.
-- Aplicar ANTES do código novo, em horário sem uso, junto com 20261105120100. O frontend novo lê colunas criadas aqui.
-- Reversão: supabase/rollback/20261105120000_rollback.sql (nunca trechos soltos).
-- Com BEGIN/COMMIT explícito: qualquer guarda que falhe desfaz tudo. Se esperar lock por mais de 5s, aborta sem efeito; basta repetir.
--
-- Efeito sobre dados: nenhum funcionário é inativado, nenhuma FT é alterada e nenhum registro é apagado.
-- Em 2026-11-05 produção tinha 798 funcionários, todos status='ativo'/status_ativo=true: o UPDATE do passo 1 afetaria 0 linhas.
--
-- Regras:
--  * status é a fonte da verdade: ativo | ferias | inativo. Férias não é desligamento.
--  * status_ativo significa "não está inativo" (férias = true). O banco calcula; o valor enviado pelo cliente é ignorado.
--  * data_inativacao e inativado_por são definidos pelo banco na transição para inativo; o cliente não os controla.
--  * Todo período de inatividade fica em funcionario_inatividades, escrita apenas por trigger. Reativar encerra o período, não o apaga.
--  * Período registrado por engano é anulado por RPC só do Gestor, com justificativa: continua guardado, marcado como anulado, e deixa de bloquear.
--  * Sair de inativo exige motivo. UPDATE que só carrega status='ativo' (formulário desatualizado) é recusado.
--  * FT nova nunca cai dentro de período de inatividade, encerrado ou não.
--  * Exceção só no INSERT: Gestor + data_ft anterior à inativação atual + justificativa. Fica gravada na FT e é imutável.
--  * FT com data em período de inatividade não é aprovada; continua existindo para análise e cancelamento.
--  * Vínculos e data da FT só mudam em FT PENDENTE, sem decisão anterior e sem funcionário inativo. Aprovar, negar, cancelar e corrigir valor seguem iguais.
--  * Funcionário, FT e histórico nunca são excluídos fisicamente: trigger, grants, policies e FKs (nenhum depende do outro).

BEGIN;

SET LOCAL lock_timeout = '5s';

-- Mesma ordem em que a aplicação pega locks (solicitação > ft > histórico > funcionário): sem isto, migration e lançamento podem
-- entrar em deadlock. Pegar tudo no início também evita ficar no meio do caminho.
LOCK TABLE public.ft_cancelamento_solicitacoes, public.ft, public.ft_historico, public.funcionarios IN ACCESS EXCLUSIVE MODE;

-- ============================================================
-- 0. Guarda: status_ativo=false com status='ativo' seria um caso desconhecido; não adivinhar se a pessoa está ativa.
-- ============================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.funcionarios WHERE status = 'ativo' AND NOT status_ativo) THEN
    RAISE EXCEPTION 'Abortado: há funcionários com status=ativo e status_ativo=false. Revisar manualmente antes de migrar.';
  END IF;
END $$;

-- ============================================================
-- 1. Funcionários: três estados, data efetiva e coerência
-- ============================================================
ALTER TABLE public.funcionarios
  ADD COLUMN data_inativacao DATE,
  ADD COLUMN inativado_por UUID, -- sem FK, como audit_logs.user_id: o registro sobrevive à exclusão do usuário
  ADD COLUMN reativacao_motivo TEXT; -- só entrada do UPDATE de reativação; o trigger copia para o período e limpa

COMMENT ON COLUMN public.funcionarios.data_inativacao IS
  'Início da inatividade atual (America/Sao_Paulo). Definida pelo trigger tg_funcionarios_status; NULL se não estiver inativo.';
COMMENT ON COLUMN public.funcionarios.status_ativo IS
  'Derivado de status: false somente quando inativo. Férias = true. Calculado por tg_funcionarios_status.';
COMMENT ON COLUMN public.funcionarios.reativacao_motivo IS
  'Parâmetro da reativação: exigido ao sair de inativo, gravado em funcionario_inatividades e nunca persistido aqui.';

-- Férias marcadas como status_ativo=false pela regra antiga do formulário. Status não muda: férias continua férias.
UPDATE public.funcionarios SET status_ativo = true WHERE status = 'ferias' AND NOT status_ativo;

ALTER TABLE public.funcionarios DROP CONSTRAINT funcionarios_status_check;
ALTER TABLE public.funcionarios
  ADD CONSTRAINT funcionarios_status_check CHECK (status IN ('ativo', 'ferias', 'inativo')),
  ADD CONSTRAINT funcionarios_status_ativo_coerente CHECK (status_ativo = (status <> 'inativo')),
  ADD CONSTRAINT funcionarios_inativacao_coerente CHECK ((status = 'inativo') = (data_inativacao IS NOT NULL)),
  ADD CONSTRAINT funcionarios_reativacao_motivo_transitorio CHECK (reativacao_motivo IS NULL);

-- [inicio, fim): fim é o dia da reativação, em que a pessoa já pode trabalhar. fim NULL = inatividade em curso.
CREATE TABLE public.funcionario_inatividades (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  funcionario_id    UUID        NOT NULL REFERENCES public.funcionarios(id) ON DELETE RESTRICT,
  inicio            DATE        NOT NULL,
  fim               DATE,
  inativado_por     UUID,
  inativado_em      TIMESTAMPTZ NOT NULL DEFAULT now(),
  reativado_por     UUID,
  reativado_em      TIMESTAMPTZ,
  motivo_reativacao TEXT,
  anulada_em        TIMESTAMPTZ,
  anulada_por       UUID,
  anulacao_justificativa TEXT,
  anulacao_fts      JSONB, -- FTs com data no período no momento da anulação, para auditoria
  CONSTRAINT funcionario_inatividades_ordem CHECK (fim IS NULL OR fim >= inicio),
  CONSTRAINT funcionario_inatividades_reativacao_coerente CHECK ((fim IS NULL) = (motivo_reativacao IS NULL)),
  CONSTRAINT funcionario_inatividades_anulacao_coerente
    CHECK (num_nonnulls(anulada_em, anulada_por, anulacao_justificativa, anulacao_fts) IN (0, 4)),
  CONSTRAINT funcionario_inatividades_anula_so_encerrado CHECK (anulada_em IS NULL OR fim IS NOT NULL)
);
CREATE UNIQUE INDEX uq_funcionario_inatividade_aberta ON public.funcionario_inatividades (funcionario_id) WHERE fim IS NULL;
CREATE INDEX idx_funcionario_inatividades_funcionario ON public.funcionario_inatividades (funcionario_id, inicio);

ALTER TABLE public.funcionario_inatividades ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Gestor le inatividades" ON public.funcionario_inatividades FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'gestor'::public.app_role));
REVOKE ALL ON public.funcionario_inatividades FROM anon, authenticated, service_role;
GRANT SELECT ON public.funcionario_inatividades TO authenticated, service_role;

CREATE TRIGGER audit_funcionario_inatividades AFTER INSERT OR UPDATE OR DELETE ON public.funcionario_inatividades
  FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();

-- Exige conteúdo real: espaços, quebras de linha, pontuação e caracteres invisíveis não contam. COLLATE "C": mesmo resultado em qualquer
-- configuração do banco e igual à validação do frontend (letras sem acento e dígitos).
CREATE OR REPLACE FUNCTION public.texto_justificativa_valido(_txt TEXT)
RETURNS BOOLEAN
LANGUAGE SQL IMMUTABLE
SET search_path = public
AS $$
  SELECT char_length(coalesce(_txt, '')) <= 1000
     AND char_length(regexp_replace(coalesce(_txt, '') COLLATE "C", '[^A-Za-z0-9]', '', 'g')) >= 10
$$;
REVOKE EXECUTE ON FUNCTION public.texto_justificativa_valido(TEXT) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.tg_funcionarios_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hoje DATE := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_motivo TEXT;
BEGIN
  v_motivo := btrim(NEW.reativacao_motivo);
  NEW.reativacao_motivo := NULL;
  NEW.status_ativo := NEW.status <> 'inativo';

  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'inativo' THEN
      RAISE EXCEPTION 'CADASTRO_INATIVO: cadastre o funcionário e depois use a inativação.';
    END IF;
    NEW.data_inativacao := NULL;
    NEW.inativado_por := NULL;
  ELSIF OLD.status = 'inativo' AND NEW.status = 'inativo' THEN
    NEW.data_inativacao := OLD.data_inativacao; -- já inativo: data e autor não mudam
    NEW.inativado_por := OLD.inativado_por;
  ELSIF OLD.status = 'inativo' THEN
    IF NOT public.texto_justificativa_valido(v_motivo) THEN
      RAISE EXCEPTION 'REATIVACAO_MOTIVO: reativar um funcionário exige motivo com pelo menos 10 letras ou números.';
    END IF;
    UPDATE public.funcionario_inatividades
       SET fim = v_hoje, reativado_por = auth.uid(), reativado_em = now(), motivo_reativacao = v_motivo
     WHERE funcionario_id = NEW.id AND fim IS NULL;
    NEW.data_inativacao := NULL;
    NEW.inativado_por := NULL;
  ELSIF NEW.status = 'inativo' THEN
    NEW.data_inativacao := v_hoje;
    NEW.inativado_por := auth.uid();
    INSERT INTO public.funcionario_inatividades (funcionario_id, inicio, inativado_por)
    VALUES (NEW.id, v_hoje, auth.uid());
  ELSE
    NEW.data_inativacao := NULL;
    NEW.inativado_por := NULL;
  END IF;

  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.tg_funcionarios_status() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_funcionarios_status
  BEFORE INSERT OR UPDATE ON public.funcionarios
  FOR EACH ROW EXECUTE FUNCTION public.tg_funcionarios_status();

-- ============================================================
-- 2. FT: evidência da exceção retroativa (preenchida e congelada pelo trigger)
-- ============================================================
ALTER TABLE public.ft
  ADD COLUMN retroativa_justificativa TEXT,
  ADD COLUMN retroativa_autorizada_por UUID, -- sem FK: a evidência sobrevive à exclusão do usuário
  ADD COLUMN retroativa_autorizada_em TIMESTAMPTZ,
  ADD CONSTRAINT ft_retroativa_coerente
    CHECK (num_nonnulls(retroativa_justificativa, retroativa_autorizada_por, retroativa_autorizada_em) IN (0, 3));

COMMENT ON COLUMN public.ft.retroativa_justificativa IS
  'Exceção de FT retroativa com funcionário inativo. Enviada no INSERT, validada e congelada por tg_ft_validar_funcionarios.';

CREATE OR REPLACE FUNCTION public.funcionario_em_inatividade(_funcionario_id UUID, _data DATE)
RETURNS BOOLEAN
LANGUAGE SQL STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.funcionario_inatividades
     WHERE funcionario_id = _funcionario_id AND inicio <= _data AND (fim IS NULL OR _data < fim) AND anulada_em IS NULL
  )
$$;
REVOKE EXECUTE ON FUNCTION public.funcionario_em_inatividade(UUID, DATE) FROM PUBLIC, anon, authenticated;

-- Anulação de período registrado por engano. Só período encerrado: inatividade em curso sai pela reativação, com motivo, e só depois é anulável;
-- assim há um único caminho para deixar de ser inativo. Não altera FT nenhuma: FTs com data no período ficam registradas em anulacao_fts.
-- Irreversível de propósito. FOR UPDATE no funcionário serializa com inativação, reativação e lançamento (mesma ordem de lock dos triggers).
CREATE OR REPLACE FUNCTION public.anular_inatividade(_periodo_id UUID, _justificativa TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_just TEXT := btrim(_justificativa);
  v_func UUID;
  v_status TEXT;
  v_p public.funcionario_inatividades%ROWTYPE;
  v_fts JSONB;
BEGIN
  IF NOT public.has_role(v_uid, 'gestor'::public.app_role) THEN
    RAISE EXCEPTION 'PERMISSAO: apenas o Gestor pode anular um período de inatividade.';
  END IF;
  IF NOT public.texto_justificativa_valido(v_just) THEN
    RAISE EXCEPTION 'ANULACAO_JUSTIFICATIVA: informe uma justificativa com pelo menos 10 letras ou números (máximo de 1000 caracteres).';
  END IF;

  SELECT funcionario_id INTO v_func FROM public.funcionario_inatividades WHERE id = _periodo_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ANULACAO_ESTADO: período não encontrado.';
  END IF;

  SELECT status INTO v_status FROM public.funcionarios WHERE id = v_func FOR UPDATE;
  SELECT * INTO v_p FROM public.funcionario_inatividades WHERE id = _periodo_id FOR UPDATE;

  IF v_p.anulada_em IS NOT NULL THEN
    RAISE EXCEPTION 'ANULACAO_ESTADO: este período já foi anulado.';
  END IF;
  IF v_status = 'inativo' OR v_p.fim IS NULL THEN
    RAISE EXCEPTION 'ANULACAO_ESTADO: reative o funcionário antes de anular um período.';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'numero_ft', numero_ft, 'status', status, 'data_ft', data_ft) ORDER BY data_ft), '[]'::jsonb)
    INTO v_fts
    FROM public.ft
   WHERE v_func IN (funcionario_id, funcionario_faltante_id) AND data_ft >= v_p.inicio AND data_ft < v_p.fim;

  UPDATE public.funcionario_inatividades
     SET anulada_em = now(), anulada_por = v_uid, anulacao_justificativa = v_just, anulacao_fts = v_fts
   WHERE id = _periodo_id;

  PERFORM public.log_audit(
    'ANULAR_INATIVIDADE', 'funcionario_inatividades', _periodo_id::text,
    format('Anulou o período de inatividade de %s a %s', to_char(v_p.inicio, 'DD/MM/YYYY'), to_char(v_p.fim, 'DD/MM/YYYY')),
    to_jsonb(v_p),
    jsonb_build_object('funcionario_id', v_func, 'anulada_por', v_uid, 'fts_no_periodo', v_fts),
    v_just
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.anular_inatividade(UUID, TEXT) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.anular_inatividade(UUID, TEXT) TO authenticated;

-- ============================================================
-- 3. FT: INSERT pela API sempre nasce pendente, com campos de controle do banco
--    Nome com "a_": precisa rodar antes de trg_ft_numero (triggers BEFORE rodam em ordem alfabética).
--    Sem auth.uid() (SQL administrativo) não se aplica; a aplicação não lança FT com service role.
-- ============================================================
CREATE OR REPLACE FUNCTION public.tg_ft_normalizar_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.status <> 'PENDENTE'::public.ft_status THEN
    RAISE EXCEPTION 'FT_STATUS_INICIAL: uma movimentação nova sempre começa pendente de aprovação.';
  END IF;
  NEW.aprovado_por := NULL;
  NEW.numero_ft := NULL;
  NEW.data_cancelamento := NULL;
  NEW.data_lancamento := now();
  NEW.created_at := now();
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.tg_ft_normalizar_insert() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_ft_a_normalizar_insert
  BEFORE INSERT ON public.ft
  FOR EACH ROW EXECUTE FUNCTION public.tg_ft_normalizar_insert();

-- ============================================================
-- 4. FT: validação de vínculos, datas e campos históricos
--    FOR SHARE serializa com a inativação: quem chega depois espera e enxerga o status já confirmado.
--    A FK só pega FOR KEY SHARE, que não conflita com UPDATE de status; por isso o lock explícito.
--    ORDER BY id: ordem fixa de lock entre os dois vínculos.
--    Perfil vem de auth.uid() + user_roles (mesma fonte da RLS). Nunca de metadata do JWT nem de NEW.lancado_por.
-- ============================================================
CREATE OR REPLACE FUNCTION public.tg_ft_validar_funcionarios()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ids UUID[];
  v_f RECORD;
  v_tem_inativo BOOLEAN := false;
  v_mudou_vinculo BOOLEAN;
  v_uid UUID := auth.uid();
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF (NEW.id, NEW.numero_ft, NEW.lancado_por, NEW.created_at, NEW.data_lancamento)
       IS DISTINCT FROM (OLD.id, OLD.numero_ft, OLD.lancado_por, OLD.created_at, OLD.data_lancamento) THEN
      RAISE EXCEPTION 'FT_IMUTAVEL: número, autor e datas de registro da movimentação não podem ser alterados.';
    END IF;

    IF (NEW.retroativa_justificativa, NEW.retroativa_autorizada_por, NEW.retroativa_autorizada_em)
       IS DISTINCT FROM (OLD.retroativa_justificativa, OLD.retroativa_autorizada_por, OLD.retroativa_autorizada_em) THEN
      RAISE EXCEPTION 'RETROATIVA_IMUTAVEL: os dados de autorização de uma FT retroativa não podem ser alterados.';
    END IF;

    -- Aprovador é quem decidiu, autenticado; fora de uma decisão não muda, nem para NULL.
    IF NEW.aprovado_por IS DISTINCT FROM OLD.aprovado_por AND v_uid IS NOT NULL THEN
      NEW.aprovado_por := CASE WHEN NEW.status IS DISTINCT FROM OLD.status THEN v_uid ELSE OLD.aprovado_por END;
    END IF;

    v_mudou_vinculo := (NEW.funcionario_id, NEW.funcionario_faltante_id, NEW.data_ft)
                       IS DISTINCT FROM (OLD.funcionario_id, OLD.funcionario_faltante_id, OLD.data_ft);

    IF v_mudou_vinculo THEN
      IF OLD.retroativa_autorizada_em IS NOT NULL THEN
        RAISE EXCEPTION 'RETROATIVA_IMUTAVEL: funcionários e data de uma FT retroativa não podem ser alterados.';
      END IF;
      -- aprovado_por preenchido = já houve decisão: FT aprovada ou negada e reaberta como PENDENTE não ganha vínculos novos.
      IF OLD.status <> 'PENDENTE'::public.ft_status OR OLD.aprovado_por IS NOT NULL THEN
        RAISE EXCEPTION 'FT_VINCULO_IMUTAVEL: funcionários e data só podem ser alterados em movimentação pendente, ainda sem decisão.';
      END IF;

      -- Vínculos antigos e novos: nem trocar por inativo, nem tirar um inativo do histórico, nem mover a data com inativo.
      v_ids := array_remove(ARRAY[OLD.funcionario_id, OLD.funcionario_faltante_id, NEW.funcionario_id, NEW.funcionario_faltante_id], NULL);
      FOR v_f IN
        SELECT id, nome, status, data_inativacao FROM public.funcionarios WHERE id = ANY (v_ids) ORDER BY id FOR SHARE
      LOOP
        IF v_f.status = 'inativo' THEN
          RAISE EXCEPTION 'FUNCIONARIO_INATIVO: % está inativo desde %. A movimentação não pode ser alterada para este vínculo ou data.',
            v_f.nome, to_char(v_f.data_inativacao, 'DD/MM/YYYY');
        END IF;
        IF v_f.id IN (NEW.funcionario_id, NEW.funcionario_faltante_id) AND public.funcionario_em_inatividade(v_f.id, NEW.data_ft) THEN
          RAISE EXCEPTION 'FUNCIONARIO_INATIVO: % estava inativo em %.', v_f.nome, to_char(NEW.data_ft, 'DD/MM/YYYY');
        END IF;
      END LOOP;
    END IF;

    IF NEW.status = 'APROVADA'::public.ft_status AND OLD.status IS DISTINCT FROM NEW.status THEN
      v_ids := array_remove(ARRAY[NEW.funcionario_id, NEW.funcionario_faltante_id], NULL);
      FOR v_f IN
        SELECT id, nome FROM public.funcionarios WHERE id = ANY (v_ids) ORDER BY id FOR SHARE
      LOOP
        IF public.funcionario_em_inatividade(v_f.id, NEW.data_ft) THEN
          RAISE EXCEPTION 'FT_INATIVO_NA_DATA: % está inativo na data do serviço (%). A movimentação não pode ser aprovada; analise ou cancele.',
            v_f.nome, to_char(NEW.data_ft, 'DD/MM/YYYY');
        END IF;
      END LOOP;
    END IF;

    RETURN NEW;
  END IF;

  -- INSERT. Autoria nunca vem do cliente.
  NEW.retroativa_autorizada_por := NULL;
  NEW.retroativa_autorizada_em := NULL;
  NEW.retroativa_justificativa := nullif(regexp_replace(NEW.retroativa_justificativa, '^\s+|\s+$', '', 'g'), '');

  v_ids := array_remove(ARRAY[NEW.funcionario_id, NEW.funcionario_faltante_id], NULL);
  FOR v_f IN
    SELECT id, nome, status, data_inativacao FROM public.funcionarios WHERE id = ANY (v_ids) ORDER BY id FOR SHARE
  LOOP
    IF v_f.status = 'inativo' THEN
      v_tem_inativo := true;

      IF NOT public.has_role(v_uid, 'gestor'::public.app_role)
         OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid AND ativo) THEN
        RAISE EXCEPTION 'FUNCIONARIO_INATIVO: % está inativo desde % e não pode ser incluído em novas movimentações.',
          v_f.nome, to_char(v_f.data_inativacao, 'DD/MM/YYYY');
      END IF;

      IF NEW.data_ft >= v_f.data_inativacao THEN
        RAISE EXCEPTION 'RETROATIVA_DATA: a data do serviço deve ser anterior à inativação de % (%).',
          v_f.nome, to_char(v_f.data_inativacao, 'DD/MM/YYYY');
      END IF;
    END IF;

    -- Período encerrado por reativação continua valendo: reativar não reabre datas em que a pessoa estava inativa.
    IF public.funcionario_em_inatividade(v_f.id, NEW.data_ft) THEN
      RAISE EXCEPTION 'FUNCIONARIO_INATIVO: % estava inativo em %.', v_f.nome, to_char(NEW.data_ft, 'DD/MM/YYYY');
    END IF;
  END LOOP;

  IF NOT v_tem_inativo THEN
    IF NEW.retroativa_justificativa IS NOT NULL THEN
      RAISE EXCEPTION 'RETROATIVA_INDEVIDA: justificativa retroativa só se aplica a funcionário inativo.';
    END IF;
    RETURN NEW;
  END IF;

  IF NOT public.texto_justificativa_valido(NEW.retroativa_justificativa) THEN
    RAISE EXCEPTION 'RETROATIVA_JUSTIFICATIVA: informe uma justificativa com pelo menos 10 letras ou números (máximo de 1000 caracteres).';
  END IF;

  NEW.retroativa_autorizada_por := v_uid;
  NEW.retroativa_autorizada_em := now();
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.tg_ft_validar_funcionarios() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_ft_validar_funcionarios
  BEFORE INSERT OR UPDATE ON public.ft
  FOR EACH ROW EXECUTE FUNCTION public.tg_ft_validar_funcionarios();

-- Registro legível da exceção, na mesma transação do lançamento.
CREATE OR REPLACE FUNCTION public.tg_ft_retroativa_registrar()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.ft_historico (ft_id, acao, status_novo, alterado_por, observacao)
  VALUES (NEW.id, 'LANCAMENTO_RETROATIVO', NEW.status, NEW.retroativa_autorizada_por, NEW.retroativa_justificativa);

  PERFORM public.log_audit(
    'FT_RETROATIVA_EXCECAO', 'ft', NEW.id::text,
    format('Lançamento retroativo excepcional %s, data do serviço %s', NEW.numero_ft, to_char(NEW.data_ft, 'DD/MM/YYYY')),
    NULL,
    jsonb_build_object(
      'numero_ft', NEW.numero_ft, 'data_ft', NEW.data_ft,
      'funcionario_id', NEW.funcionario_id, 'funcionario_faltante_id', NEW.funcionario_faltante_id,
      'autorizada_por', NEW.retroativa_autorizada_por, 'autorizada_em', NEW.retroativa_autorizada_em
    ),
    NEW.retroativa_justificativa
  );
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.tg_ft_retroativa_registrar() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_ft_retroativa_registrar
  AFTER INSERT ON public.ft
  FOR EACH ROW WHEN (NEW.retroativa_autorizada_em IS NOT NULL)
  EXECUTE FUNCTION public.tg_ft_retroativa_registrar();

-- ============================================================
-- 5. Exclusão física: proibida para funcionários, FTs, histórico e períodos
--    Trigger vale para todos, inclusive service_role e postgres. Só some com ALTER TABLE ... DISABLE TRIGGER (dono da tabela).
-- ============================================================
CREATE OR REPLACE FUNCTION public.tg_bloquear_exclusao()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  RAISE EXCEPTION 'EXCLUSAO_PROIBIDA: %', TG_ARGV[0];
END;
$$;
REVOKE EXECUTE ON FUNCTION public.tg_bloquear_exclusao() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_funcionarios_bloquear_exclusao BEFORE DELETE ON public.funcionarios
  FOR EACH ROW EXECUTE FUNCTION public.tg_bloquear_exclusao('funcionários não podem ser excluídos. Use a inativação.');
CREATE TRIGGER trg_funcionarios_bloquear_truncate BEFORE TRUNCATE ON public.funcionarios
  FOR EACH STATEMENT EXECUTE FUNCTION public.tg_bloquear_exclusao('funcionários não podem ser excluídos. Use a inativação.');

CREATE TRIGGER trg_ft_bloquear_exclusao BEFORE DELETE ON public.ft
  FOR EACH ROW EXECUTE FUNCTION public.tg_bloquear_exclusao('movimentações não podem ser excluídas. Use o cancelamento.');
CREATE TRIGGER trg_ft_bloquear_truncate BEFORE TRUNCATE ON public.ft
  FOR EACH STATEMENT EXECUTE FUNCTION public.tg_bloquear_exclusao('movimentações não podem ser excluídas. Use o cancelamento.');

CREATE TRIGGER trg_ft_historico_bloquear_exclusao BEFORE DELETE ON public.ft_historico
  FOR EACH ROW EXECUTE FUNCTION public.tg_bloquear_exclusao('o histórico da movimentação não pode ser excluído.');
CREATE TRIGGER trg_ft_historico_bloquear_truncate BEFORE TRUNCATE ON public.ft_historico
  FOR EACH STATEMENT EXECUTE FUNCTION public.tg_bloquear_exclusao('o histórico da movimentação não pode ser excluído.');

CREATE TRIGGER trg_inatividades_bloquear_exclusao BEFORE DELETE ON public.funcionario_inatividades
  FOR EACH ROW EXECUTE FUNCTION public.tg_bloquear_exclusao('períodos de inatividade não podem ser excluídos.');
CREATE TRIGGER trg_inatividades_bloquear_truncate BEFORE TRUNCATE ON public.funcionario_inatividades
  FOR EACH STATEMENT EXECUTE FUNCTION public.tg_bloquear_exclusao('períodos de inatividade não podem ser excluídos.');

DROP POLICY "Gestores delete funcionarios" ON public.funcionarios;
DROP POLICY "Gestores delete ft" ON public.ft;

-- RLS não se aplica a TRUNCATE; o histórico não pode depender dela.
REVOKE DELETE, TRUNCATE ON public.funcionarios, public.ft, public.ft_historico FROM anon, authenticated, service_role;

-- Segunda barreira: mesmo com os triggers desligados, nada some em cascata.
-- Nomes mantidos: o frontend usa funcionarios!ft_funcionario_id_fkey nos selects.
ALTER TABLE public.ft
  DROP CONSTRAINT ft_funcionario_id_fkey,
  DROP CONSTRAINT ft_funcionario_faltante_id_fkey,
  ADD CONSTRAINT ft_funcionario_id_fkey
    FOREIGN KEY (funcionario_id) REFERENCES public.funcionarios(id) ON DELETE RESTRICT,
  ADD CONSTRAINT ft_funcionario_faltante_id_fkey
    FOREIGN KEY (funcionario_faltante_id) REFERENCES public.funcionarios(id) ON DELETE RESTRICT;

ALTER TABLE public.ft_historico
  DROP CONSTRAINT ft_historico_ft_id_fkey,
  ADD CONSTRAINT ft_historico_ft_id_fkey FOREIGN KEY (ft_id) REFERENCES public.ft(id) ON DELETE RESTRICT;

ALTER TABLE public.ft_cancelamento_solicitacoes
  DROP CONSTRAINT ft_cancelamento_solicitacoes_ft_id_fkey,
  ADD CONSTRAINT ft_cancelamento_solicitacoes_ft_id_fkey FOREIGN KEY (ft_id) REFERENCES public.ft(id) ON DELETE RESTRICT;

-- ============================================================
-- 6. Guarda final: REVOKE não falha quando o grant veio de outro grantor; aqui a falha é explícita.
-- ============================================================
DO $$
DECLARE r TEXT; t TEXT;
BEGIN
  FOREACH r IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    FOREACH t IN ARRAY ARRAY['public.funcionarios', 'public.ft', 'public.ft_historico', 'public.funcionario_inatividades'] LOOP
      IF has_table_privilege(r, t, 'DELETE') OR has_table_privilege(r, t, 'TRUNCATE') THEN
        RAISE EXCEPTION 'Abortado: % ainda tem DELETE/TRUNCATE em %.', r, t;
      END IF;
    END LOOP;
    IF has_table_privilege(r, 'public.funcionario_inatividades', 'INSERT') OR has_table_privilege(r, 'public.funcionario_inatividades', 'UPDATE') THEN
      RAISE EXCEPTION 'Abortado: % pode escrever em funcionario_inatividades.', r;
    END IF;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
