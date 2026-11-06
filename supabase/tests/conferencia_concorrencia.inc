# Incluído por rodar_local.sh, depois de funcionarios_inativos_concorrencia.inc (usa GESTOR, como, contar). Duas conexões reais.
FE=d1000000-0000-0000-0000-00000000000e
sql -c "INSERT INTO public.funcionarios (id, nome, re, cargo, turno) VALUES ('$FE', 'DISPUTA NOME', 'C-E', 'Vigilante', 'Integral')"
ITENS="[{\"tipo\":\"DIVERGENCIA_NOME\",\"funcionario_id\":\"$FE\",\"folha\":{\"nome\":\"DISPUTA NOME NOVO\",\"cpf\":\"***\"},\"atual\":{\"nome\":\"DISPUTA NOME\",\"cpf\":null,\"status\":\"ativo\"},\"acao\":\"ATUALIZAR_NOME\",\"opcoes\":[\"ATUALIZAR_NOME\"],\"motivo\":\"teste\",\"origens\":[\"F:2\"]}]"
criar() { echo "BEGIN; $(como "$GESTOR") SELECT public.conferencia_criar('{\"nome\":\"$1\"}', '{\"total_folha\":1}', '$ITENS'); $2 COMMIT;"; }

# E) duas conferências ao mesmo tempo: a segunda espera e é recusada; só uma fica aberta
( criar a.xlsx "SELECT pg_sleep(2);" | sql >/dev/null ) &
PID_E=$!
"$PGBIN/psql" -q -X -c "SELECT pg_sleep(0.7)" >/dev/null
ERRO_E=$(criar b.xlsx "" | "$PGBIN/psql" -q -X 2>&1 >/dev/null || true)
wait "$PID_E"
N_E=$(contar "SELECT count(*) FROM public.conferencias WHERE status = 'ABERTA'")
if [ "$N_E" = 1 ] && echo "$ERRO_E" | grep -q CONFERENCIA_ABERTA; then
  echo "OK    concorrência E: segunda conferência esperou e foi recusada"
else
  echo "FALHA concorrência E: abertas=$N_E erro=[$ERRO_E]"; falhas=$((falhas + 1))
fi

CID=$(contar "SELECT id FROM public.conferencias WHERE status = 'ABERTA'")
ITEM=$(contar "SELECT id FROM public.conferencia_itens WHERE conferencia_id = '$CID'")
echo "BEGIN; $(como "$GESTOR") SELECT public.conferencia_decidir('$ITEM', 'APROVADA', 'ATUALIZAR_NOME'); COMMIT;" | sql >/dev/null
aplicar() { echo "BEGIN; $(como "$GESTOR") SELECT public.conferencia_aplicar('$CID', 'APLICAR 1'); $1 COMMIT;"; }

# F) edição do cadastro aberta durante a aplicação: aplicar espera, enxerga a mudança e registra CONFLITO sem sobrescrever
( echo "BEGIN; $(como "$GESTOR") UPDATE public.funcionarios SET nome = 'EDITADO NA TELA' WHERE id = '$FE'; SELECT pg_sleep(2); COMMIT;" | sql >/dev/null ) &
PID_F=$!
"$PGBIN/psql" -q -X -c "SELECT pg_sleep(0.7)" >/dev/null
# G) duas aplicações da mesma conferência: a segunda espera a primeira e encontra a conferência encerrada
( aplicar "SELECT pg_sleep(1);" | sql >/dev/null ) &
PID_G=$!
"$PGBIN/psql" -q -X -c "SELECT pg_sleep(0.3)" >/dev/null
ERRO_G=$(aplicar "" | "$PGBIN/psql" -q -X 2>&1 >/dev/null || true)
wait "$PID_F" "$PID_G"
NOME_F=$(contar "SELECT nome FROM public.funcionarios WHERE id = '$FE'")
RES_F=$(contar "SELECT resultado FROM public.conferencia_itens WHERE id = '$ITEM'")
if [ "$NOME_F" = "EDITADO NA TELA" ] && [ "$RES_F" = CONFLITO ]; then
  echo "OK    concorrência F: aplicação esperou a edição e registrou conflito"
else
  echo "FALHA concorrência F: nome=[$NOME_F] resultado=[$RES_F]"; falhas=$((falhas + 1))
fi
if echo "$ERRO_G" | grep -q CONFERENCIA_ESTADO; then
  echo "OK    concorrência G: segunda aplicação recusada"
else
  echo "FALHA concorrência G: erro=[$ERRO_G]"; falhas=$((falhas + 1))
fi
