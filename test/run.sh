#!/usr/bin/env bash
# owl.nvim — full test entry point.
# Runs Node unit + integration tests, then Lua unit tests via nvim --headless.
# Exits non-zero on any failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

C_R='\033[1;31m'; C_G='\033[1;32m'; C_Y='\033[1;33m'; C_C='\033[1;36m'; C_0='\033[0m'
fail=0

section() { printf "\n${C_C}=== %s ===${C_0}\n" "$*"; }

# ---------------------------------------------------------------------------
section "Node — unit + integration"
if ! command -v node >/dev/null; then
  printf "${C_R}x node not found${C_0}\n"; exit 1
fi
if [ ! -d "$ROOT/server/node_modules" ]; then
  printf "${C_Y}! server/node_modules missing — running npm install...${C_0}\n"
  ( cd "$ROOT/server" && npm install --no-audit --no-fund )
fi

# node:test resolves relative to the CWD; run from server/
if ( cd "$ROOT/server" && npm test ); then
  printf "${C_G}v node tests passed${C_0}\n"
else
  printf "${C_R}x node tests failed${C_0}\n"
  fail=1
fi

# ---------------------------------------------------------------------------
section "Lua — headless nvim"
if ! command -v nvim >/dev/null; then
  printf "${C_Y}! nvim not found — skipping Lua tests${C_0}\n"
else
  if nvim --headless -l "$ROOT/test/lua/harness.lua" \
      "$ROOT/test/lua/config_spec.lua" \
      "$ROOT/test/lua/os_spec.lua" \
      "$ROOT/test/lua/window_spec.lua"; then
    printf "${C_G}v lua tests passed${C_0}\n"
  else
    printf "${C_R}x lua tests failed${C_0}\n"
    fail=1
  fi
fi

# ---------------------------------------------------------------------------
if [ $fail -eq 0 ]; then
  printf "\n${C_G}all green${C_0}\n"
else
  printf "\n${C_R}failures detected${C_0}\n"
fi
exit $fail
