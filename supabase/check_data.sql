-- Verifique quantos registros existem no banco atual (rode no SQL Editor)

SELECT 'funcionarios' AS tabela, COUNT(*)::int AS total FROM public.funcionarios
UNION ALL
SELECT 'ft', COUNT(*)::int FROM public.ft
UNION ALL
SELECT 'profiles', COUNT(*)::int FROM public.profiles
UNION ALL
SELECT 'user_roles', COUNT(*)::int FROM public.user_roles
UNION ALL
SELECT 'audit_logs', COUNT(*)::int FROM public.audit_logs;

SELECT id, email, created_at
FROM auth.users
ORDER BY created_at;
