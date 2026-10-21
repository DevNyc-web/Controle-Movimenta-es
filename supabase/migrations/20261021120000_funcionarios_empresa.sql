-- Empresa à qual o funcionário está cadastrado (nome como nas planilhas de cadastro).
-- Aditiva: coluna nullable, sem default, sem constraint. Não toca em ft, RLS, triggers nem em nenhum dado existente;
-- o preenchimento dos cadastros atuais é um backfill separado e revisado (supabase/backfill/funcionarios_empresa.sql).
ALTER TABLE public.funcionarios ADD COLUMN IF NOT EXISTS empresa TEXT;

-- Rollback: ALTER TABLE public.funcionarios DROP COLUMN IF EXISTS empresa;
