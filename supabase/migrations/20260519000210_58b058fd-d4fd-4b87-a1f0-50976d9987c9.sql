
-- Reset admin password to guaranteed value
UPDATE auth.users
SET encrypted_password = crypt('Ab783514', gen_salt('bf')),
    email_confirmed_at = COALESCE(email_confirmed_at, now())
WHERE email = 'admin@interno.local';

-- ===== AUDIT LOG =====
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid,
  username text,
  role text,
  action text NOT NULL,            -- INSERT | UPDATE | DELETE | LOGIN | EXPORT | IMPORT | APROVAR | NEGAR | CANCELAR | RESET_SENHA | etc.
  entity_type text NOT NULL,       -- ft | funcionarios | profiles | user_roles | relatorio | importacao
  entity_id text,
  description text,
  old_data jsonb,
  new_data jsonb,
  observacao text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON public.audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_user ON public.audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON public.audit_logs(entity_type, entity_id);

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- Só gestor lê; qualquer autenticado escreve (via SECURITY DEFINER trigger ou server fn). Bloqueia UPDATE/DELETE.
DROP POLICY IF EXISTS "Gestor lê audit_logs" ON public.audit_logs;
CREATE POLICY "Gestor lê audit_logs" ON public.audit_logs FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'gestor'::app_role));

DROP POLICY IF EXISTS "Auth insert audit" ON public.audit_logs;
CREATE POLICY "Auth insert audit" ON public.audit_logs FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

-- helper para registrar (lê username/role e grava)
CREATE OR REPLACE FUNCTION public.log_audit(
  _action text,
  _entity_type text,
  _entity_id text,
  _description text DEFAULT NULL,
  _old jsonb DEFAULT NULL,
  _new jsonb DEFAULT NULL,
  _obs text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_username text;
  v_role text;
BEGIN
  IF v_uid IS NOT NULL THEN
    SELECT username INTO v_username FROM public.profiles WHERE id = v_uid;
    SELECT role::text INTO v_role FROM public.user_roles WHERE user_id = v_uid LIMIT 1;
  END IF;
  INSERT INTO public.audit_logs(user_id, username, role, action, entity_type, entity_id, description, old_data, new_data, observacao)
  VALUES (v_uid, v_username, v_role, _action, _entity_type, _entity_id, _description, _old, _new, _obs);
END; $$;

-- Trigger genérico: registra INSERT/UPDATE/DELETE em tabelas marcadas
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

-- Aplica triggers nas tabelas sensíveis
DROP TRIGGER IF EXISTS audit_ft ON public.ft;
CREATE TRIGGER audit_ft AFTER INSERT OR UPDATE OR DELETE ON public.ft
  FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();

DROP TRIGGER IF EXISTS audit_funcionarios ON public.funcionarios;
CREATE TRIGGER audit_funcionarios AFTER INSERT OR UPDATE OR DELETE ON public.funcionarios
  FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();

DROP TRIGGER IF EXISTS audit_profiles ON public.profiles;
CREATE TRIGGER audit_profiles AFTER INSERT OR UPDATE OR DELETE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();

DROP TRIGGER IF EXISTS audit_user_roles ON public.user_roles;
CREATE TRIGGER audit_user_roles AFTER INSERT OR UPDATE OR DELETE ON public.user_roles
  FOR EACH ROW EXECUTE FUNCTION public.tg_audit_row();
