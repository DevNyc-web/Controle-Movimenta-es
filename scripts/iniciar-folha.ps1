# Folha Certa: inicia o servidor de produção (opção A) e o mantém no ar. Aprovado no ensaio P3 (na VM: tarefa agendada "ao iniciar").
# Reinicia se o processo cair (espera 5 s; desiste após 5 quedas em 10 min, código 3). Para de forma limpa quando existe <Logs>\PARAR
# (use parar-folha.ps1). Não altera variáveis do sistema/usuário: HOST/PORT valem só para o processo filho.
param(
  [Parameter(Mandatory)][string]$Pasta,      # pasta com servidor-producao.mjs, dist\ e node_modules\
  [Parameter(Mandatory)][string]$Config,     # arquivo de credenciais (fora da pasta do app), lido por node --env-file
  [string]$HostIp = "127.0.0.1", [int]$Porta = 8080,
  [Parameter(Mandatory)][string]$Logs
)
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force $Logs | Out-Null
$diario = Join-Path $Logs "supervisor.log"
function Log([string]$m) { $l = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m"; Add-Content -LiteralPath $diario -Value $l -Encoding UTF8; $l }

$node = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
foreach ($c in @(@($node, "node.exe no PATH"), @((Join-Path $Pasta "servidor-producao.mjs"), "servidor-producao.mjs"), @((Join-Path $Pasta "dist\server\server.js"), "dist\server\server.js"), @($Config, "arquivo de configuração"))) {
  if (-not $c[0] -or -not (Test-Path -LiteralPath $c[0])) { Log "RECUSADO: $($c[1]) não encontrado"; exit 2 } }
$ocupada = Get-NetTCPConnection -LocalPort $Porta -State Listen -ErrorAction SilentlyContinue
if ($ocupada) { Log "RECUSADO: porta $Porta já em uso pelo PID $($ocupada[0].OwningProcess)"; exit 2 }
$sinal = Join-Path $Logs "PARAR"; Remove-Item -LiteralPath $sinal -ErrorAction SilentlyContinue
$PID | Set-Content -LiteralPath (Join-Path $Logs "supervisor.pid")

$quedas = New-Object System.Collections.Generic.List[datetime]
$env:HOST = $HostIp; $env:PORT = "$Porta"; $env:NODE_ENV = "production"
while ($true) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $p = Start-Process -FilePath $node -ArgumentList @("--env-file=`"$Config`"", "servidor-producao.mjs") -WorkingDirectory $Pasta -NoNewWindow -PassThru `
        -RedirectStandardOutput (Join-Path $Logs "app-$stamp.log") -RedirectStandardError (Join-Path $Logs "app-$stamp.err.log")
  $null = $p.Handle   # sem isto o PowerShell 5.1 não preenche ExitCode quando a saída é redirecionada
  $p.Id | Set-Content -LiteralPath (Join-Path $Logs "app.pid")
  Log "iniciado: node PID $($p.Id) em ${HostIp}:$Porta"
  $p.WaitForExit()
  if (Test-Path -LiteralPath $sinal) { Remove-Item -LiteralPath $sinal; Log "parado a pedido (código $($p.ExitCode))"; exit 0 }
  if ($p.ExitCode -eq 78) { Log "RECUSADO: configuração incompleta (ver app-$stamp.err.log); não reinicia"; exit 4 }
  $agora = Get-Date; $quedas.Add($agora); $quedas.RemoveAll({ param($t) $t -lt $agora.AddMinutes(-10) }) | Out-Null
  Log "QUEDA: node PID $($p.Id) saiu com código $($p.ExitCode); quedas em 10 min: $($quedas.Count)"
  if ($quedas.Count -ge 5) { Log "DESISTINDO: 5 quedas em 10 minutos; verificar app-*.err.log"; exit 3 }
  Start-Sleep -Seconds 5
}
