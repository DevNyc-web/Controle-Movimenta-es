# Folha Certa: para o servidor iniciado por iniciar-folha.ps1 (cria o sinal PARAR e encerra o node; o supervisor sai com código 0).
param([Parameter(Mandatory)][string]$Logs, [int]$EsperaSegundos = 15)
$pidArq = Join-Path $Logs "app.pid"
if (-not (Test-Path -LiteralPath $pidArq)) { "nada a parar: $pidArq não existe"; exit 0 }
New-Item -ItemType File -Force (Join-Path $Logs "PARAR") | Out-Null
$appPid = [int](Get-Content -LiteralPath $pidArq)
$p = Get-Process -Id $appPid -ErrorAction SilentlyContinue
if ($p -and $p.ProcessName -eq "node") { Stop-Process -Id $appPid; "node PID $appPid encerrado" } else { "node PID $appPid já não estava em execução" }
$supArq = Join-Path $Logs "supervisor.pid"
if (Test-Path -LiteralPath $supArq) { $s = Get-Process -Id ([int](Get-Content -LiteralPath $supArq)) -ErrorAction SilentlyContinue
  if ($s) { if (-not $s.WaitForExit($EsperaSegundos * 1000)) { "ATENÇÃO: supervisor ainda ativo após $EsperaSegundos s"; exit 1 } } }
"parado"
