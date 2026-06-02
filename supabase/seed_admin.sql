-- =============================================================================
-- Recria o usuário administrador inicial (login de testes)
-- Execute no SQL Editor do Supabase (projeto dqwiojgajitmatbwobgt)
--
-- Login na tela:  admin
-- Senha:         Ab783514
-- E-mail interno: admin@interno.local
-- Perfil:        gestor (acesso total ao sistema)
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
  v_user_id UUID;
BEGIN
  SELECT id INTO v_user_id FROM auth.users WHERE email = 'admin@interno.local' LIMIT 1;

  IF v_user_id IS NOT NULL THEN
    -- Já existe: apenas garante senha e perfil ativo
    UPDATE auth.users
    SET
      encrypted_password = crypt('Ab783514', gen_salt('bf')),
      email_confirmed_at = COALESCE(email_confirmed_at, now()),
      updated_at = now()
    WHERE id = v_user_id;

    UPDATE public.profiles
    SET nome = 'Administrador', username = 'admin', ativo = true
    WHERE id = v_user_id;

    DELETE FROM public.user_roles WHERE user_id = v_user_id;
    INSERT INTO public.user_roles (user_id, role) VALUES (v_user_id, 'gestor');

    RAISE NOTICE 'Admin já existia — senha redefinida para Ab783514 e role gestor aplicada.';
    RETURN;
  END IF;

  v_user_id := gen_random_uuid();

  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    is_super_admin, confirmation_token, email_change, email_change_token_new, recovery_token
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    v_user_id,
    'authenticated', 'authenticated',
    'admin@interno.local',
    crypt('Ab783514', gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('username', 'admin', 'nome', 'Administrador', 'role', 'gestor'),
    false, '', '', '', ''
  );

  INSERT INTO auth.identities (
    id, user_id, identity_data, provider, provider_id,
    last_sign_in_at, created_at, updated_at
  ) VALUES (
    gen_random_uuid(),
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', 'admin@interno.local'),
    'email',
    v_user_id::text,
    now(), now(), now()
  );

  -- O trigger on_auth_user_created também cria profile/role; garantimos explicitamente:
  INSERT INTO public.profiles (id, nome, email, username, ativo)
  VALUES (v_user_id, 'Administrador', 'admin@interno.local', 'admin', true)
  ON CONFLICT (id) DO UPDATE
  SET nome = EXCLUDED.nome, username = EXCLUDED.username, ativo = true;

  INSERT INTO public.user_roles (user_id, role)
  VALUES (v_user_id, 'gestor')
  ON CONFLICT (user_id, role) DO NOTHING;

  RAISE NOTICE 'Admin criado — login: admin / senha: Ab783514';
END $$;
