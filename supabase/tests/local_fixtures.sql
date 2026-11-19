-- SOMENTE PARA O POSTGRES DESCARTÁVEL. Faz nos fixtures o que createUser faz no servidor (admin.functions.ts): ativa a conta e grava
-- o perfil. handle_new_user não concede mais nada; as suítes declaram o perfil no metadata por simplicidade.
-- seguranca_regressao.sql desliga este trigger para testar o handle_new_user puro.

CREATE FUNCTION auth.fixture_conta_admin() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.profiles SET ativo = true WHERE id = NEW.id;
  IF NEW.raw_user_meta_data ? 'role' THEN
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, (NEW.raw_user_meta_data->>'role')::public.app_role)
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER zz_fixture_conta_admin AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION auth.fixture_conta_admin();
