<#
.SYNOPSIS
  Verificação rápida do ambiente local para Cursor My Machines worker.
#>
param(
  [string]$Name = "filhos-local"
)

$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent

function Test-Cmd($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }

Write-Host "`nCursor My Machines — checklist local`n" -ForegroundColor Cyan

# CLI
if (Test-Cmd "agent") {
  $ver = & agent --version 2>&1
  Write-Host "[OK]  agent CLI: $ver" -ForegroundColor Green
}
else {
  $local = Join-Path $env:LOCALAPPDATA "cursor-agent\agent.exe"
  if (Test-Path $local) {
    $ver = & $local --version 2>&1
    Write-Host "[OK]  agent CLI (local): $ver" -ForegroundColor Green
  }
  else {
    Write-Host "[--]  agent CLI ausente — rode: .\scripts\setup-cursor-worker.ps1 -Install" -ForegroundColor Yellow
  }
}

# Git
Push-Location $root
try {
  if (Test-Path ".git") {
    $remote = git remote get-url origin 2>$null
    Write-Host "[OK]  git remote origin: $remote" -ForegroundColor Green
  }
  else {
    Write-Host "[!!]  não é repositório git" -ForegroundColor Red
  }
}
finally { Pop-Location }

# Serviços locais do projeto (opcionais)
$checks = @(
  @{ Label = "API health"; Url = "http://127.0.0.1:3010/health" },
  @{ Label = "Web Vite"; Url = "http://localhost:5173" },
  @{ Label = "Chrome CDP (Amil)"; Url = "http://127.0.0.1:9222/json/version" }
)
foreach ($c in $checks) {
  try {
    $r = Invoke-WebRequest -Uri $c.Url -UseBasicParsing -TimeoutSec 3
    Write-Host "[OK]  $($c.Label): $($c.Url)" -ForegroundColor Green
  }
  catch {
    Write-Host "[--]  $($c.Label): offline ($($c.Url))" -ForegroundColor DarkGray
  }
}

# Outbound
foreach ($h in @("api2.cursor.sh")) {
  try {
    $null = Invoke-WebRequest -Uri "https://$h" -Method Head -TimeoutSec 8 -UseBasicParsing
    Write-Host "[OK]  outbound HTTPS: $h" -ForegroundColor Green
  }
  catch {
    Write-Host "[!!]  outbound HTTPS bloqueado: $h" -ForegroundColor Red
  }
}

Write-Host @"

Para registrar esta máquina como worker '$Name':

  .\scripts\setup-cursor-worker.ps1 -Install -Login -Start

Depois selecione '$Name' em https://cursor.com/agents
"@ -ForegroundColor Cyan
