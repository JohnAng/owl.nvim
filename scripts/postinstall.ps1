# Lazy `build` hook (Windows). Installs the bundled Node server deps.
$ErrorActionPreference = 'Continue'
$root   = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$server = Join-Path $root 'server'

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Host "! owl.nvim: node not found. Install Node.js >= 18." -ForegroundColor Yellow
  exit 0
}
Write-Host "> owl.nvim: installing server dependencies in $server" -ForegroundColor Cyan
Push-Location $server
try {
  if (Get-Command npm -ErrorAction SilentlyContinue) {
    npm install --omit=dev --no-audit --no-fund
  } elseif (Get-Command pnpm -ErrorAction SilentlyContinue) {
    pnpm install --prod
  } elseif (Get-Command yarn -ErrorAction SilentlyContinue) {
    yarn install --production
  } else {
    Write-Host "! owl.nvim: no package manager found." -ForegroundColor Yellow
    exit 0
  }
  Write-Host "v owl.nvim: server ready" -ForegroundColor Green
} finally {
  Pop-Location
}
