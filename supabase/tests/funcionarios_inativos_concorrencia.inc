# Incluído por rodar_local.sh. Duas conexões reais disputando o mesmo funcionário: isto não dá para simular em uma conexão só.
# Dados fictícios, confirmados no cluster descartável, que é apagado ao final.
GESTOR=e1000000-0000-0000-0000-000000000001
SUP=e1000000-0000-0000-0000-000000000002
FA=d1000000-0000-0000-0000-00000000000a
FB=d1000000-0000-0000-0000-00000000000b

sql -c "INSERT INTO auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) VALUES
 ('00000000-0000-0000-0000-000000000000', '$GESTOR', 'authenticated', 'authenticated', 'cg@teste.local', '{\"username\":\"cg\",\"nome\":\"cg\",\"role\":\"gestor\"}', now(), now()),
 ('00000000-0000-0000-0000-000000000000', '$SUP', 'authenticated', 'authenticated', 'cs@teste.local', '{\"username\":\"cs\",\"nome\":\"cs\",\"role\":\"supervisor\"}', now(), now())"
sql -c "INSERT INTO public.funcionarios (id, nome, re, cargo, turno) VALUES
 ('$FA', 'CONCORRENCIA A', 'C-A', 'Vigilante', 'Integral'), ('$FB', 'CONCORRENCIA B', 'C-B', 'Vigilante', 'Integral')"

como() { echo "SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claims', '{\"sub\":\"$1\"}', true);"; }
inserir() { echo "INSERT INTO public.ft (funcionario_id, data_ft, motivo, lancado_por) VALUES ('$1', DATE '$2', 'Falta', '$SUP');"; }
contar() { "$PGBIN/psql" -X -At -c "$1"; }

# A) inativação aberta; lançamento chega durante ela: precisa ESPERAR e ser recusado
( echo "BEGIN; $(como "$GESTOR") UPDATE public.funcionarios SET status = 'inativo' WHERE id = '$FA'; SELECT pg_sleep(2); COMMIT;" | sql >/dev/null ) &
PID_A=$!
"$PGBIN/psql" -q -X -c "SELECT pg_sleep(0.7)" >/dev/null
ERRO_A=$(echo "BEGIN; $(como "$SUP") $(inserir "$FA" 2026-03-01) COMMIT;" | "$PGBIN/psql" -q -X 2>&1 >/dev/null || true)
wait "$PID_A"
N_A=$(contar "SELECT count(*) FROM public.ft WHERE funcionario_id = '$FA'")
if [ "$N_A" = 0 ] && echo "$ERRO_A" | grep -q FUNCIONARIO_INATIVO; then
  echo "OK    concorrência A: lançamento esperou a inativação e foi recusado"
else
  echo "FALHA concorrência A: FTs=$N_A erro=[$ERRO_A]"; falhas=$((falhas + 1))
fi

# B) lançamento aberto; inativação chega durante ele: precisa ESPERAR o commit da FT, e a FT permanece
( echo "BEGIN; $(como "$SUP") $(inserir "$FB" 2026-03-02) SELECT pg_sleep(2); COMMIT;" | sql >/dev/null ) &
PID_B=$!
"$PGBIN/psql" -q -X -c "SELECT pg_sleep(0.7)" >/dev/null
INI_B=$(date +%s%N)
echo "BEGIN; $(como "$GESTOR") UPDATE public.funcionarios SET status = 'inativo' WHERE id = '$FB'; COMMIT;" | sql >/dev/null
ESPERA_MS=$(( ($(date +%s%N) - INI_B) / 1000000 ))
wait "$PID_B"
N_B=$(contar "SELECT count(*) FROM public.ft WHERE funcionario_id = '$FB'")
ST_B=$(contar "SELECT status FROM public.funcionarios WHERE id = '$FB'")
if [ "$N_B" = 1 ] && [ "$ST_B" = inativo ] && [ "$ESPERA_MS" -ge 800 ]; then
  echo "OK    concorrência B: inativação esperou ${ESPERA_MS}ms pelo lançamento; FT preservada"
else
  echo "FALHA concorrência B: FTs=$N_B status=$ST_B espera=${ESPERA_MS}ms"; falhas=$((falhas + 1))
fi

# C) inativação aberta; aprovação de FT futura chega durante ela: precisa ESPERAR e ser recusada, sem apagar a FT
FC=d1000000-0000-0000-0000-00000000000c; FTC=f1000000-0000-0000-0000-00000000000c
sql -c "INSERT INTO public.funcionarios (id, nome, re, cargo, turno) VALUES ('$FC', 'CONCORRENCIA C', 'C-C', 'Vigilante', 'Integral')"
sql -c "INSERT INTO public.ft (id, funcionario_id, data_ft, motivo, lancado_por) VALUES ('$FTC', '$FC', (now() AT TIME ZONE 'America/Sao_Paulo')::date + 5, 'Falta', '$SUP')"
( echo "BEGIN; $(como "$GESTOR") UPDATE public.funcionarios SET status = 'inativo' WHERE id = '$FC'; SELECT pg_sleep(2); COMMIT;" | sql >/dev/null ) &
PID_C=$!
"$PGBIN/psql" -q -X -c "SELECT pg_sleep(0.7)" >/dev/null
ERRO_C=$(echo "BEGIN; $(como "$GESTOR") UPDATE public.ft SET status = 'APROVADA', aprovado_por = '$GESTOR' WHERE id = '$FTC'; COMMIT;" | "$PGBIN/psql" -q -X 2>&1 >/dev/null || true)
wait "$PID_C"
ST_C=$(contar "SELECT status FROM public.ft WHERE id = '$FTC'")
if [ "$ST_C" = PENDENTE ] && echo "$ERRO_C" | grep -q FT_INATIVO_NA_DATA; then
  echo "OK    concorrência C: aprovação esperou a inativação e foi recusada; FT preservada"
else
  echo "FALHA concorrência C: status=$ST_C erro=[$ERRO_C]"; falhas=$((falhas + 1))
fi

# D) inativação aberta; anulação de período antigo chega durante ela: precisa ESPERAR e ser recusada
FD=d1000000-0000-0000-0000-00000000000d
sql -c "INSERT INTO public.funcionarios (id, nome, re, cargo, turno) VALUES ('$FD', 'CONCORRENCIA D', 'C-D', 'Vigilante', 'Integral')"
sql -c "UPDATE public.funcionarios SET status = 'inativo' WHERE id = '$FD'"
sql -c "UPDATE public.funcionarios SET status = 'ativo', reativacao_motivo = 'reativado para o teste de concorrencia' WHERE id = '$FD'"
PD=$(contar "SELECT id FROM public.funcionario_inatividades WHERE funcionario_id = '$FD'")
( echo "BEGIN; $(como "$GESTOR") UPDATE public.funcionarios SET status = 'inativo' WHERE id = '$FD'; SELECT pg_sleep(2); COMMIT;" | sql >/dev/null ) &
PID_D=$!
"$PGBIN/psql" -q -X -c "SELECT pg_sleep(0.7)" >/dev/null
ERRO_D=$(echo "BEGIN; $(como "$GESTOR") SELECT public.anular_inatividade('$PD', 'tentativa concorrente de anular'); COMMIT;" | "$PGBIN/psql" -q -X 2>&1 >/dev/null || true)
wait "$PID_D"
AN_D=$(contar "SELECT anulada_em IS NULL FROM public.funcionario_inatividades WHERE id = '$PD'")
if [ "$AN_D" = t ] && echo "$ERRO_D" | grep -q ANULACAO_ESTADO; then
  echo "OK    concorrência D: anulação esperou a inativação e foi recusada"
else
  echo "FALHA concorrência D: anulado_null=$AN_D erro=[$ERRO_D]"; falhas=$((falhas + 1))
fi
