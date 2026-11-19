# Incluído por rodar_local.sh. Executa os arquivos reais de rollback em cópias do banco já migrado (criadas antes das suítes).
RB6=supabase/rollback/20261112120000_rollback.sql
RB5=supabase/rollback/20261111120000_rollback.sql
RB4=supabase/rollback/20261110120000_rollback.sql
RB3=supabase/rollback/20261106120000_rollback.sql
RB2=supabase/rollback/20261105120100_rollback.sql
RB1=supabase/rollback/20261105120000_rollback.sql
val_db() { "$PGBIN/psql" -X -At -d "$1" -c "$2"; }

# 00) 20261118120000 (auditoria paginada): remove só as funções novas e o índice; auditoria_listar e as permissões ficam
RB8=supabase/rollback/20261118120000_rollback.sql
P8="select (select count(*) from pg_proc where proname in ('auditoria_pagina', 'auditoria_filtros'))::text || '/' || (to_regclass('public.idx_audit_logs_created_id') is null)::text || '/' || (to_regprocedure('public.auditoria_listar(integer)') is not null)::text || '/' || has_any_column_privilege('authenticated', 'public.audit_logs', 'SELECT')::text"
for B in rollback_guarda rollback_ok; do
  if sql -d "$B" -f "$RB8" && [ "$(val_db "$B" "$P8")" = "0/true/true/false" ]; then
    echo "OK    rollback 20261118120000 em $B: funções e índice removidos; auditoria_listar e permissões intactas"
  else
    echo "FALHA rollback 20261118120000 em $B: [$(val_db "$B" "$P8")]"; falhas=$((falhas + 1))
  fi
done

# 0) 20261113120000 depois de 20261105120100: o rollback dela recusa e não muda nada (o estado é o de 20261105120100)
RB7=supabase/rollback/20261113120000_rollback.sql
P7="select count(*)::text || '/' || has_table_privilege('authenticated', 'public.audit_logs', 'INSERT')::text || '/' || has_table_privilege('authenticated', 'public.ft_historico', 'INSERT')::text from pg_policies where policyname in ('Auth insert audit', 'Auth insert historico')"
SAIDA=$("$PGBIN/psql" -q -X -d rollback_guarda -f "$RB7" 2>&1 || true)
if echo "$SAIDA" | grep -q '20261105120100 já aplicada' && [ "$(val_db rollback_guarda "$P7")" = "0/false/false" ]; then
  echo "OK    rollback 20261113120000 recusado depois de 20261105120100; nada mudou"
else
  echo "FALHA rollback 20261113120000: [$(val_db rollback_guarda "$P7")] [$SAIDA]"; falhas=$((falhas + 1))
fi

# 1) Com informação a preservar: aborta sem nenhum efeito, mesmo fora de transação do cliente
sql -d rollback_guarda -c "INSERT INTO public.funcionarios (id, nome, re, cargo, turno) VALUES ('d9000000-0000-0000-0000-000000000001', 'RB', 'RB-1', 'ASG', 'Integral')"
sql -d rollback_guarda -c "UPDATE public.funcionarios SET status = 'inativo' WHERE re = 'RB-1'"
sql -d rollback_guarda -f "$RB6"
sql -d rollback_guarda -f "$RB5"
sql -d rollback_guarda -f "$RB4"
sql -d rollback_guarda -f "$RB3"
sql -d rollback_guarda -f "$RB2"
SAIDA=$("$PGBIN/psql" -q -X -d rollback_guarda -f "$RB1" 2>&1 || true)
GUARDA=$(val_db rollback_guarda "select (select count(*) from pg_trigger where tgname = 'trg_funcionarios_bloquear_exclusao')::text || '/' || (select count(*) from information_schema.columns where column_name = 'data_inativacao')::text || '/' || (select status from public.funcionarios where re = 'RB-1')")
if echo "$SAIDA" | grep -q 'Abortado sem alterações' && [ "$GUARDA" = "1/1/inativo" ]; then
  echo "OK    rollback recusado com informação a preservar; nada mudou"
else
  echo "FALHA rollback guarda: [$GUARDA] [$SAIDA]"; falhas=$((falhas + 1))
fi

# 2) Sem nada a preservar: reverte, e as suítes anteriores passam no esquema revertido
if sql -d rollback_ok -f "$RB6" && sql -d rollback_ok -f "$RB5" && sql -d rollback_ok -f "$RB4" && sql -d rollback_ok -f "$RB3" && sql -d rollback_ok -f "$RB2" && sql -d rollback_ok -f "$RB1"; then
  ESTADO=$(val_db rollback_ok "select (select count(*) from information_schema.columns where column_name in ('data_inativacao', 'retroativa_justificativa'))::text || '/' || (select count(*) from pg_class where relname = 'funcionario_inatividades')::text || '/' || (select count(*) from pg_proc where proname = 'conta_ativa')::text")
  # handle_new_user endurecido não volta; delete/cascade perigosos também não
  CASC=$(val_db rollback_ok "select count(*) from pg_constraint where conrelid = 'public.ft'::regclass and contype = 'f' and confrelid = 'public.funcionarios'::regclass and confdeltype <> 'r'")
  SEG=$(val_db rollback_ok "select count(*) from pg_policies where policyname in ('Admins manage roles', 'Users update own profile', 'Auth insert audit')")
  if [ "$ESTADO" = "0/0/0" ] && [ "$CASC" = 0 ] && [ "$SEG" = 0 ]; then
    echo "OK    rollback aplicado; falhas de segurança não voltaram"
  else
    echo "FALHA rollback estado: [$ESTADO] cascade=$CASC seg=$SEG"; falhas=$((falhas + 1))
  fi
  for t in ft_reuso_data limite_mensal supervisor_window; do
    if sql -d rollback_ok -f "supabase/tests/$t.sql" >/dev/null; then echo "OK    $t no esquema revertido"; else echo "FALHA $t no esquema revertido"; falhas=$((falhas + 1)); fi
  done
else
  echo "FALHA rollback não aplicou"; falhas=$((falhas + 1))
fi
