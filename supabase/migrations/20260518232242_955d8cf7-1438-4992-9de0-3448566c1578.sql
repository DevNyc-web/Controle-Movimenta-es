
-- ============================================
-- RESET TOTAL DE DADOS
-- ============================================
DELETE FROM public.ft_historico;
DELETE FROM public.ft;
DELETE FROM public.funcionarios;
DELETE FROM public.user_roles;
DELETE FROM public.profiles;
-- Remover todos os usuários do auth
DELETE FROM auth.identities;
DELETE FROM auth.users;

-- ============================================
-- NOVOS PAPÉIS
-- ============================================
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'apontamento';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'supervisor';
