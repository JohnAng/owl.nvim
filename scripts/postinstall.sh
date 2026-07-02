#!/usr/bin/env bash
# Lazy `build` hook (Linux / macOS / WSL). Installs the bundled Node server deps.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="$ROOT/server"

if ! command -v node >/dev/null 2>&1; then
  echo "! owl.nvim: node not found. Install Node.js >= 18 and re-run the plugin's build hook." >&2
  exit 0
fi

echo "> owl.nvim: installing server dependencies in $SERVER"
cd "$SERVER"
if command -v npm >/dev/null 2>&1; then
  npm install --omit=dev --no-audit --no-fund
elif command -v pnpm >/dev/null 2>&1; then
  pnpm install --prod
elif command -v yarn >/dev/null 2>&1; then
  yarn install --production
else
  echo "! owl.nvim: no package manager found (npm/pnpm/yarn). Install one and re-run." >&2
  exit 0
fi
echo "v owl.nvim: server ready"
