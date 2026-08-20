<#
.SYNOPSIS
  Prepara esta máquina Windows como worker "My Machines" para Cursor Cloud Agent.

.DESCRIPTION
  Instala o Cursor CLI, verifica login, valida o repositório e inicia o worker
  com conexão de saída para api2.cursor.sh (sem abrir portas inbound).

  Documentação: https://cursor.com/docs/cloud-agent/self-hosted-guides/my-machines

.PARAMETER Install
  Instala ou atualiza o Cursor CLI (agent).

.PARAMETER Login
  Abre login no browser (agent login).

.PARAMETER Start
  Inicia o worker neste checkout do repositório.

.PARAMETER Name
  Nome amigável da máquina no dropdown de ambientes (default: filhos-local).

.PARAMETER Debug
  Passa --debug ao worker (preflight de auth, repo labels, visibilidade).

.PARAMETER Status
  Apenas verifica CLI, login e conectividade de saída.

.EXAMPLE
  .\scripts\setup-cursor-worker.ps1 -Install -Login -Start

.EXAMPLE
  .\scripts\setup-cursor-worker.ps1 -Status
#>
param(
  [switch]$Install,
  [switch]$Login,
  [switch]$Start,
  [switch]$Debug,
  [switch]$Status,
  [string]$Name = "filhos-local"
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

function Write-Step([string]$msg) {
  Write-Host "`n==> $msg" -ForegroundColor Cyan
}

function Test-Command([string]$name) {
  return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Get-AgentExe {
  if (Test-Command "agent") { return "agent" }
  $local = Join-Path $env:LOCALAPPDATA "cursor-agent\agent.exe"
  if (Test-Path $local) { return $local }
  return $null
}

function Test-OutboundHttps([string]$hostName) {
  try {
    $uri = "https://$hostName"
    $null = Invoke-WebRequest -Uri $uri -Method Head -TimeoutSec 10 -UseBasicParsing
    return $true
  }
  catch {
    return $false
  }
}

function Assert-RepoRoot {
  Push-Location $root
  try {
    if (-not (Test-Path (Join-Path $root ".git"))) {
      throw "Diretório do projeto não é um repositório git: $root"
    }
    $remote = (git remote get-url origin 2>$null)
    if (-not $remote) {
      throw "Sem remote 'origin'. Configure o git remote antes de iniciar o worker."
    }
    Write-Host "Repo: $root" -ForegroundColor DarkGray
    Write-Host "Remote origin: $remote" -ForegroundColor DarkGray
    return $remote
  }
  finally {
    Pop-Location
  }
}

if (-not ($Install -or $Login -or $Start -or $Status)) {
  Write-Host @"
Uso rápido (PowerShell, na raiz do projeto):

  .\scripts\setup-cursor-worker.ps1 -Install -Login -Start

Depois, em https://cursor.com/agents escolha a máquina '$Name' no dropdown de ambiente.

Mantenha o terminal do worker aberto enquanto usar Cloud Agents nesta máquina.
"@ -ForegroundColor Yellow
  exit 0
}

if ($Install) {
  Write-Step "Instalando Cursor CLI"
  irm 'https://cursor.com/install?win32=true' | iex
}

$agent = Get-AgentExe
if (-not $agent) {
  throw "Cursor CLI (agent) não encontrado. Rode com -Install primeiro."
}

Write-Step "CLI: $(& $agent --version 2>&1)"

if ($Status -or $Start) {
  Write-Step "Verificando conectividade de saída"
  $hosts = @("api2.cursor.sh", "api2direct.cursor.sh")
  foreach ($h in $hosts) {
    $ok = Test-OutboundHttps $h
    $color = if ($ok) { "Green" } else { "Red" }
    Write-Host ("  {0,-30} {1}" -f $h, $(if ($ok) { "OK" } else { "FALHOU" })) -ForegroundColor $color
    if (-not $ok) {
      Write-Host "  Libere HTTPS de saída para api2.cursor.sh no firewall/proxy." -ForegroundColor Yellow
    }
  }
  Assert-RepoRoot | Out-Null
}

if ($Login) {
  Write-Step "Login no Cursor (browser)"
  Write-Host "Complete o login na janela que abrir. Use a mesma conta do Cursor Desktop." -ForegroundColor DarkGray
  & $agent login
}

if ($Start) {
  Assert-RepoRoot | Out-Null
  Write-Step "Iniciando worker '$Name'"
  Write-Host @"
O worker fica conectado até você fechar este terminal (Ctrl+C).
Cloud Agents usarão ESTA máquina para terminal, arquivos, browser e MCP stdio.

Próximo passo:
  1. Abra https://cursor.com/agents
  2. Selecione a máquina '$Name' no dropdown de ambiente
  3. Envie a tarefa (ex.: sync Amil, subir serviços com scripts/up.ps1)

Para GitHub/Slack: @cursoragent worker=$Name <tarefa>
"@ -ForegroundColor Green

  Push-Location $root
  try {
    $args = @("worker", "start", "--name", $Name, "--worker-dir", $root)
    if ($Debug) { $args += "--debug" }
    & $agent @args
  }
  finally {
    Pop-Location
  }
}

if ($Status -and -not $Start) {
  Write-Step "Status"
  Write-Host "CLI instalado: sim ($agent)" -ForegroundColor Green
  Write-Host "Para testar login/worker: .\scripts\setup-cursor-worker.ps1 -Login -Start -Debug" -ForegroundColor DarkGray
}
