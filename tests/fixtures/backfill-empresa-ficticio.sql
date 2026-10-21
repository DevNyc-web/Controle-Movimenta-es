-- FIXTURE FICTÍCIA para testes: mesma estrutura do backfill real de funcionarios.empresa, com IDs inventados.
-- O backfill real (IDs de funcionários) não é versionado; ver tests/validar-backfill-empresa.ts.

BEGIN;

CREATE TEMP TABLE _empresa_backfill (id uuid PRIMARY KEY, empresa text NOT NULL) ON COMMIT DROP;

INSERT INTO _empresa_backfill (id, empresa)
SELECT unnest(ARRAY[
  '00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002'
]::uuid[]), 'MC REMOTA LTDA'
UNION ALL SELECT unnest(ARRAY[
  '00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000004'
]::uuid[]), 'MC SERVICOS E PORTARIA EIRELI'
UNION ALL SELECT unnest(ARRAY[
  '00000000-0000-4000-8000-000000000005'
]::uuid[]), 'M C ALPHA SEGURANCA ELETRONICA LTDA ME';

-- Guardas (qualquer falha aborta a transação inteira)
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _empresa_backfill;
  IF n <> 5 THEN RAISE EXCEPTION 'Backfill: esperado 5 IDs na lista, encontrado %', n; END IF;

  SELECT count(*) INTO n FROM _empresa_backfill b JOIN public.funcionarios f USING (id);
  IF n <> 5 THEN RAISE EXCEPTION 'Backfill: % dos 5 IDs não existem mais em funcionarios', 5 - n; END IF;

  SELECT count(*) INTO n FROM _empresa_backfill b JOIN public.funcionarios f USING (id) WHERE f.cpf IS NULL;
  IF n > 0 THEN RAISE EXCEPTION 'Backfill: % IDs da lista estão sem CPF (correspondência não é mais por CPF)', n; END IF;

  SELECT count(*) INTO n FROM _empresa_backfill b JOIN public.funcionarios f USING (id)
   WHERE f.empresa IS NOT NULL AND f.empresa <> b.empresa;
  IF n > 0 THEN RAISE EXCEPTION 'Backfill: % funcionários já têm empresa diferente preenchida; nada foi sobrescrito', n; END IF;
END $$;

-- Só preenche onde está vazio: reexecutar é inofensivo e nunca sobrescreve edição manual.
UPDATE public.funcionarios f
   SET empresa = b.empresa
  FROM _empresa_backfill b
 WHERE f.id = b.id
   AND f.empresa IS NULL;

SELECT coalesce(empresa, '(sem empresa)') AS empresa, count(*) FROM public.funcionarios GROUP BY 1 ORDER BY 1;

COMMIT;
