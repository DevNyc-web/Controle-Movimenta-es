#!/usr/bin/env bash
# Testes SQL em Postgres DESCARTÁVEL: cria um cluster em pasta temporária, porta própria e só 127.0.0.1, aplica as
# migrations em ordem, roda supabase/tests/*.sql e apaga tudo ao sair. Não lê .env e não conecta em nenhum projeto Supabase.
# Uso:  bash supabase/tests/rodar_local.sh            (todas as migrations)
#       ATE=20261030120000 bash supabase/tests/rodar_local.sh   (só até essa versão: mede a base, sem testes novos)
#       PGBIN=/caminho/pg17/bin bash supabase/tests/rodar_local.sh   (outra versão do servidor)
# Requer PostgreSQL local (PGBIN). Produção é PG 17.
set -euo pipefail

PGBIN="${PGBIN:-/c/Program Files/PostgreSQL/18/bin}"
PORTA="${PORTA:-54399}"
ATE="${ATE:-99999999999999}"
cd "$(dirname "$0")/../.."

DADOS="$(mktemp -d)"
DADOS_NATIVO="$(cygpath -w "$DADOS" 2>/dev/null || echo "$DADOS")"
export PGHOST=127.0.0.1 PGPORT="$PORTA" PGUSER=postgres PGDATABASE=postgres PGCLIENTENCODING=UTF8 PGOPTIONS="-c client_min_messages=warning"
sql() { "$PGBIN/psql" -q -X -v ON_ERROR_STOP=1 "$@"; }

encerrar() {
  "$PGBIN/pg_ctl" -D "$DADOS_NATIVO" -m immediate -w stop >/dev/null 2>&1 || true
  rm -rf "$DADOS"
}
trap encerrar EXIT

"$PGBIN/initdb" -D "$DADOS_NATIVO" -U postgres -A trust -E UTF8 --locale=C >/dev/null
"$PGBIN/pg_ctl" -D "$DADOS_NATIVO" -w -l "$DADOS_NATIVO/server.log" \
  -o "-p $PORTA -c listen_addresses=127.0.0.1 -c TimeZone=UTC" start >/dev/null
"$PGBIN/psql" -X -At -c "select 'servidor: ' || split_part(version(), ' on ', 1)"

sql -f supabase/tests/local_bootstrap.sql
for m in supabase/migrations/*.sql; do
  v="$(basename "$m")"; v="${v%%_*}"
  if [ "$v" -le "$ATE" ]; then sql -f "$m"; fi
done
sql -f supabase/tests/local_fixtures.sql
echo "migrations aplicadas (até $ATE)"

falhas=0
if [ "$ATE" = 99999999999999 ]; then
  sql -d template1 -c "ALTER DATABASE template1 ALLOW_CONNECTIONS true" >/dev/null
  sql -d template1 -c "CREATE DATABASE rollback_ok TEMPLATE postgres" -c "CREATE DATABASE rollback_guarda TEMPLATE postgres"
fi

for t in supabase/tests/*.sql; do
  case "$t" in */local_bootstrap.sql | */local_fixtures.sql) continue ;; esac
  if [ "$ATE" != 99999999999999 ]; then
    case "$t" in */funcionarios_inativos* | */seguranca_regressao* | */conferencia* | */importacao_oficial*) continue ;; esac
  fi
  if sql -f "$t" >/dev/null; then echo "OK    $t"; else echo "FALHA $t"; falhas=$((falhas + 1)); fi
done

if [ "$ATE" = 99999999999999 ]; then
  # shellcheck disable=SC1091
  . supabase/tests/funcionarios_inativos_concorrencia.inc
  # shellcheck disable=SC1091
  . supabase/tests/conferencia_concorrencia.inc
  # shellcheck disable=SC1091
  . supabase/tests/rollback_local.inc
fi

echo "falhas: $falhas"
exit "$falhas"
