# Produção em Node (opção A do ensaio P3)

O build de produção gera um servidor Node (`dist/server/server.js`) servido por `servidor-producao.mjs`.
O desenvolvimento continua com `npm run dev` (o plugin Cloudflare só atuava no build).

## Arquivos
| Arquivo | Papel |
|---|---|
| `vite.config.ts` | `defineConfig({ cloudflare: false })` → build Node em vez de Worker |
| `package.json` | `srvx` 0.11.15 como dependência direta (versão exata; antes vinha só pelo TanStack Start) |
| `servidor-producao.mjs` | Estáticos de `dist/client` comprimidos uma vez e mantidos em memória; `/assets/*` com cache imutável; o resto vai ao app. Recusa partir sem `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` e `SUPABASE_SERVICE_ROLE_KEY` (código 78) |
| `scripts/iniciar-folha.ps1` | Supervisor: inicia, reinicia após queda (5 s; desiste após 5 quedas em 10 min), recusa porta ocupada e configuração ausente |
| `scripts/parar-folha.ps1` | Parada limpa (sinal `PARAR` + encerra o node) |

## Build (fora da VM: pico de ~0,9 GB)
Só variáveis **públicas** no build: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PROJECT_ID`, `VITE_SUPABASE_PUBLISHABLE_KEY`.
Nenhuma chave secreta no ambiente do build. Portão: varredura de credenciais em `dist/` = 0 achados.

```
npm ci && npm test && npm run build
npm ci --omit=dev        # pacote de execução: dist/, node_modules/, servidor-producao.mjs, package*.json
```

## Execução
```
node --env-file=<arquivo fora da pasta do app> servidor-producao.mjs     # HOST e PORT pelo ambiente; padrão 127.0.0.1:8080
scripts\iniciar-folha.ps1 -Pasta <app> -Config <arquivo> -HostIp <ip interno> -Porta 8080 -Logs <pasta>
scripts\parar-folha.ps1 -Logs <pasta>
```
Requisitos: Node ≥ 20.11 (`import.meta.dirname`, `--env-file`); ensaio em v24.16.0.

## Diferenças em relação aos protótipos aprovados no P3
- Conteúdo idêntico, exceto a 1ª linha de comentário de `servidor-producao.mjs` e `iniciar-folha.ps1` ("Proposta… ainda não versionado" → "Aprovado no ensaio P3"). `parar-folha.ps1` é idêntico ao byte.
  Por isso os sha256 dos dois primeiros diferem dos registrados em `P3-RESULTADO.md`.
- Os scripts PowerShell ficam em `scripts/` (no ensaio estavam fora do app); funcionam igual, pois recebem `-Pasta`.

## Fica para a janela (não é código do repositório)
Arquivo de credenciais fora da pasta do app com ACL restrita; tarefa agendada "ao iniciar o sistema" com conta dedicada;
escuta no IP interno e firewall da porta restrito à rede interna (ajustes 3 e 4 do P3).
