-- Auditoria paginada no servidor (P4, limitação do C1). NÃO APLICADA. Requer 20261111120000 (e 20261112120000).
-- Reversão: supabase/rollback/20261118120000_rollback.sql.
--
--  * A API (PostgREST) devolve no máximo 1000 linhas por resposta; auditoria_listar() traz só os mais recentes e a tela filtrava
--    no navegador. Aqui: páginas por cursor (keyset) com filtros no servidor, para percorrer TODO o histórico autorizado.
--  * Ordem determinística: created_at DESC, id DESC. Cursor = (created_at, id) do último item da página anterior; empates em
--    created_at são desempatados por id, então nenhum registro se repete nem é pulado; registros novos não deslocam páginas.
--  * Filtros só por IGUALDADE em campos que não são dado pessoal (período, user_id, perfil, ação, módulo). Sem busca de texto
--    no servidor: sobre os dados crus ela revelaria se um CPF existe na auditoria (oráculo), mesmo exibido mascarado.
--  * Período em dias do fuso America/Sao_Paulo: [_de 00:00, _ate+1 00:00) local.
--  * Máscara de CPF igual à de auditoria_listar, aplicada só às linhas da página (CTE materializada depois do LIMIT).
--  * Mesma porta: SECURITY DEFINER, search_path vazio (tudo qualificado), só Gestor com conta ativa (has_role), EXECUTE só para
--    authenticated. Nenhuma permissão de audit_logs muda; auditoria_listar() permanece.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $$
BEGIN
  IF to_regprocedure('public.auditoria_listar(integer)') IS NULL OR to_regprocedure('public.audit_mascarar(jsonb)') IS NULL
     OR to_regprocedure('public.texto_cpf_mascarado(text)') IS NULL THEN
    RAISE EXCEPTION 'Abortado: aplique antes 20261111120000 (e 20261112120000).';
  END IF;
END $$;

-- Cursor: busca da página seguinte sem varrer o que já foi lido.
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_id ON public.audit_logs (created_at DESC, id DESC);

CREATE OR REPLACE FUNCTION public.auditoria_pagina(
  _de DATE DEFAULT NULL, _ate DATE DEFAULT NULL, _user_id UUID DEFAULT NULL, _role TEXT DEFAULT NULL,
  _action TEXT DEFAULT NULL, _entity_type TEXT DEFAULT NULL,
  _antes_em TIMESTAMPTZ DEFAULT NULL, _antes_id UUID DEFAULT NULL, _tamanho INT DEFAULT 100)
RETURNS TABLE (id UUID, user_id UUID, username TEXT, role TEXT, action TEXT, entity_type TEXT, entity_id TEXT,
               description TEXT, old_data JSONB, new_data JSONB, observacao TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_tam INT := least(greatest(coalesce(_tamanho, 100), 1), 500);
BEGIN
  IF NOT public.has_role(auth.uid(), 'gestor'::public.app_role) THEN
    RAISE EXCEPTION 'PERMISSAO: apenas o Gestor pode consultar a auditoria.';
  END IF;
  IF (_antes_em IS NULL) <> (_antes_id IS NULL) THEN
    RAISE EXCEPTION 'AUDITORIA_CURSOR: informe data e id do último registro, ou nenhum.';
  END IF;
  IF _de IS NOT NULL AND _ate IS NOT NULL AND _de > _ate THEN
    RAISE EXCEPTION 'AUDITORIA_PERIODO: a data inicial é posterior à final.';
  END IF;
  RETURN QUERY
    WITH pagina AS MATERIALIZED (
      SELECT a.*
        FROM public.audit_logs a
       WHERE (_de IS NULL OR a.created_at >= (_de::timestamp AT TIME ZONE 'America/Sao_Paulo'))
         AND (_ate IS NULL OR a.created_at < ((_ate + 1)::timestamp AT TIME ZONE 'America/Sao_Paulo'))
         AND (_user_id IS NULL OR a.user_id = _user_id)
         AND (_role IS NULL OR a.role = _role)
         AND (_action IS NULL OR a.action = _action)
         AND (_entity_type IS NULL OR a.entity_type = _entity_type)
         AND (_antes_em IS NULL OR (a.created_at, a.id) < (_antes_em, _antes_id))
       ORDER BY a.created_at DESC, a.id DESC
       LIMIT v_tam
    )
    SELECT p.id, p.user_id, public.texto_cpf_mascarado(p.username), p.role, p.action, p.entity_type,
           public.texto_cpf_mascarado(p.entity_id), public.texto_cpf_mascarado(p.description),
           public.audit_mascarar(p.old_data), public.audit_mascarar(p.new_data), public.texto_cpf_mascarado(p.observacao), p.created_at
      FROM pagina p
     ORDER BY p.created_at DESC, p.id DESC;
END;
$$;

-- Opções dos filtros (valores existentes), com a mesma proteção. Usuário: id + nome mais recente, mascarado.
CREATE OR REPLACE FUNCTION public.auditoria_filtros()
RETURNS JSONB
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'gestor'::public.app_role) THEN
    RAISE EXCEPTION 'PERMISSAO: apenas o Gestor pode consultar a auditoria.';
  END IF;
  RETURN jsonb_build_object(
    'usuarios', coalesce((
      SELECT jsonb_agg(jsonb_build_object('id', u.user_id, 'username', public.texto_cpf_mascarado(u.username)) ORDER BY lower(coalesce(u.username, '')), u.user_id)
        FROM (SELECT DISTINCT ON (a.user_id) a.user_id, a.username FROM public.audit_logs a
               WHERE a.user_id IS NOT NULL ORDER BY a.user_id, a.created_at DESC, a.id DESC) u), '[]'::jsonb),
    'acoes', coalesce((SELECT jsonb_agg(DISTINCT a.action ORDER BY a.action) FROM public.audit_logs a), '[]'::jsonb),
    'perfis', coalesce((SELECT jsonb_agg(DISTINCT a.role ORDER BY a.role) FROM public.audit_logs a WHERE a.role IS NOT NULL), '[]'::jsonb),
    'modulos', coalesce((SELECT jsonb_agg(DISTINCT a.entity_type ORDER BY a.entity_type) FROM public.audit_logs a), '[]'::jsonb));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.auditoria_pagina(DATE, DATE, UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ, UUID, INT) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.auditoria_filtros() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.auditoria_pagina(DATE, DATE, UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ, UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.auditoria_filtros() TO authenticated;

DO $$
BEGIN
  IF has_function_privilege('anon', 'public.auditoria_pagina(date, date, uuid, text, text, text, timestamptz, uuid, integer)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.auditoria_filtros()', 'EXECUTE') THEN
    RAISE EXCEPTION 'Abortado: anon executa as funções da auditoria.';
  END IF;
  IF has_any_column_privilege('authenticated', 'public.audit_logs', 'SELECT') OR has_any_column_privilege('anon', 'public.audit_logs', 'SELECT') THEN
    RAISE EXCEPTION 'Abortado: audit_logs legível diretamente.';
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
