-- Auditoria com CPF mascarado na leitura (opção B). NÃO APLICADA. Requer 20261110120000.
-- Reversão: supabase/rollback/20261111120000_rollback.sql.
--
--  * Nenhum registro de audit_logs é alterado: a máscara é aplicada só na leitura.
--  * Nenhum perfil lê audit_logs diretamente (anon e authenticated sem SELECT). O Gestor lê por auditoria_listar().
--  * Máscara: chave "cpf" em qualquer nível do JSON (mesma regra de cpf_mascarado); CPF escrito em qualquer texto (usuário,
--    registro, descrição, observação e valores do JSON) com ou sem ponto, hífen, barra ou espaço entre os grupos; e número JSON
--    de 11 dígitos em qualquer chave. CNPJ, UUID, datas, telefones formatados e números maiores não casam.
--  * O CPF completo continua no banco, acessível só a quem administra o banco (postgres/service_role).

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $$
BEGIN
  IF to_regclass('public.importacao_empresas') IS NULL OR to_regprocedure('public.cpf_mascarado(text)') IS NULL THEN
    RAISE EXCEPTION 'Abortado: aplique antes 20261110120000.';
  END IF;
END $$;

-- CPF em texto livre: 11 dígitos em grupos 3-3-3-2, separados ou não por um ponto, hífen, barra ou espaço; sem dígito colado antes ou depois.
CREATE OR REPLACE FUNCTION public.texto_cpf_mascarado(_t TEXT)
RETURNS TEXT
LANGUAGE SQL IMMUTABLE
SET search_path = public
AS $$
  SELECT regexp_replace(_t, '(?<![0-9])[0-9]{3}[ ./-]?([0-9]{3})[ ./-]?([0-9]{3})[ ./-]?[0-9]{2}(?![0-9])', '***.\1.\2-**', 'g')
$$;

CREATE OR REPLACE FUNCTION public.audit_mascarar(_j JSONB)
RETURNS JSONB
LANGUAGE plpgsql IMMUTABLE
SET search_path = public
AS $$
BEGIN
  CASE jsonb_typeof(_j)
    WHEN 'object' THEN
      RETURN (SELECT coalesce(jsonb_object_agg(k,
                CASE WHEN lower(k) = 'cpf' AND jsonb_typeof(v) = 'string' THEN to_jsonb(public.cpf_mascarado(v #>> '{}'))
                     WHEN lower(k) = 'cpf' AND jsonb_typeof(v) = 'number' THEN to_jsonb(public.cpf_mascarado(v::text))
                     ELSE public.audit_mascarar(v) END), '{}'::jsonb)
                FROM jsonb_each(_j) AS e(k, v));
    WHEN 'array' THEN
      RETURN (SELECT coalesce(jsonb_agg(public.audit_mascarar(v) ORDER BY o), '[]'::jsonb) FROM jsonb_array_elements(_j) WITH ORDINALITY AS a(v, o));
    WHEN 'string' THEN
      RETURN to_jsonb(public.texto_cpf_mascarado(_j #>> '{}'));
    WHEN 'number' THEN  -- CPF gravado como número, em qualquer chave
      RETURN CASE WHEN _j::text ~ '^[0-9]{11}$' THEN to_jsonb(public.cpf_mascarado(_j::text)) ELSE _j END;
    ELSE
      RETURN _j;
  END CASE;
END;
$$;

-- Leitura do Gestor: os mesmos campos da tabela, mais recentes primeiro, CPF sempre mascarado.
CREATE OR REPLACE FUNCTION public.auditoria_listar(_limite INT DEFAULT 2000)
RETURNS TABLE (id UUID, user_id UUID, username TEXT, role TEXT, action TEXT, entity_type TEXT, entity_id TEXT,
               description TEXT, old_data JSONB, new_data JSONB, observacao TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'gestor'::public.app_role) THEN
    RAISE EXCEPTION 'PERMISSAO: apenas o Gestor pode consultar a auditoria.';
  END IF;
  RETURN QUERY
    SELECT a.id, a.user_id, public.texto_cpf_mascarado(a.username), a.role, a.action, a.entity_type, public.texto_cpf_mascarado(a.entity_id),
           public.texto_cpf_mascarado(a.description), public.audit_mascarar(a.old_data), public.audit_mascarar(a.new_data),
           public.texto_cpf_mascarado(a.observacao), a.created_at
      FROM public.audit_logs a
     ORDER BY a.created_at DESC, a.id
     LIMIT least(greatest(coalesce(_limite, 2000), 1), 5000);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.texto_cpf_mascarado(TEXT), public.audit_mascarar(JSONB) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.auditoria_listar(INT) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.auditoria_listar(INT) TO authenticated;

-- Sem leitura direta: nem com select *, filtro, nem pela API. Também remove concessões por coluna, que o REVOKE da tabela não alcança.
REVOKE SELECT ON public.audit_logs FROM anon, authenticated;
DO $$
DECLARE v_cols TEXT;
BEGIN
  SELECT string_agg(quote_ident(column_name), ', ') INTO v_cols FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'audit_logs';
  EXECUTE format('REVOKE SELECT (%s) ON public.audit_logs FROM anon, authenticated', v_cols);
END $$;

DO $$
BEGIN
  IF has_any_column_privilege('authenticated', 'public.audit_logs', 'SELECT') OR has_any_column_privilege('anon', 'public.audit_logs', 'SELECT') THEN
    RAISE EXCEPTION 'Abortado: audit_logs ainda legível diretamente.';
  END IF;
  IF has_table_privilege('authenticated', 'public.audit_logs', 'INSERT') OR has_table_privilege('authenticated', 'public.audit_logs', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.audit_logs', 'DELETE') THEN
    RAISE EXCEPTION 'Abortado: authenticated escreve em audit_logs.';
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
