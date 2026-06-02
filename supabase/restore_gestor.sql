-- =============================================================================
-- EMERGÊNCIA: restaura perfil GESTOR para o usuário admin
-- Use quando você alterou seu próprio usuário para supervisor/apontamento
-- e perdeu acesso à tela de Usuários.
--
-- Execute no SQL Editor do Supabase e depois faça logout/login no app.
-- =============================================================================

DO $$
DECLARE
  v_user_id UUID;
BEGIN
  SELECT p.id INTO v_user_id
  FROM public.profiles p
  WHERE LOWER(p.username) = 'admin'
  LIMIT 1;

  IF v_user_id IS NULL THEN
    SELECT u.id INTO v_user_id
    FROM auth.users u
    WHERE u.email = 'admin@interno.local'
    LIMIT 1;
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuário admin não encontrado. Ajuste o filtro (username ou email) neste script.';
  END IF;

  DELETE FROM public.user_roles WHERE user_id = v_user_id;

  INSERT INTO public.user_roles (user_id, role)
  VALUES (v_user_id, 'gestor')
  ON CONFLICT (user_id, role) DO NOTHING;

  UPDATE public.profiles
  SET ativo = true, username = COALESCE(username, 'admin')
  WHERE id = v_user_id;

  RAISE NOTICE 'Perfil gestor restaurado para user_id=%. Faça logout e login novamente.', v_user_id;
END $$;
