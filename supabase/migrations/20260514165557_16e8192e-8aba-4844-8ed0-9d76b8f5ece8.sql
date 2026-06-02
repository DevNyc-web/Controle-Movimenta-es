
ALTER TABLE public.funcionarios
  ADD COLUMN IF NOT EXISTS posto_servico text,
  ADD COLUMN IF NOT EXISTS usa_banco_horas boolean NOT NULL DEFAULT false;

ALTER TABLE public.funcionarios ALTER COLUMN cpf DROP NOT NULL;
ALTER TABLE public.funcionarios ALTER COLUMN data_admissao DROP NOT NULL;

ALTER TABLE public.ft
  ADD COLUMN IF NOT EXISTS escala_servico text,
  ADD COLUMN IF NOT EXISTS funcionario_faltante_id uuid REFERENCES public.funcionarios(id) ON DELETE SET NULL;

ALTER TABLE public.ft ALTER COLUMN tipo_folga DROP NOT NULL;
ALTER TABLE public.ft ALTER COLUMN motivo DROP NOT NULL;
