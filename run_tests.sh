#!/bin/bash
# Test runner for Life-Simulator-Game
# Usage: ./run_tests.sh

set -euo pipefail
export PATH="$HOME/.luarocks/bin:$PATH"
if command -v luarocks >/dev/null 2>&1; then
  eval "$(luarocks --lua-version=5.1 --tree="$HOME/.luarocks" path)"
fi

LUA_BIN="${LUA_BIN:-}"
if [[ -z "$LUA_BIN" ]]; then
  if command -v lua5.1 >/dev/null 2>&1; then
    LUA_BIN="lua5.1"
  elif command -v lua >/dev/null 2>&1; then
    LUA_BIN="lua"
  else
    echo "Lua interpreter not found. Install Lua 5.1+."
    exit 1
  fi
fi

busted Tests/Specs/*.lua

if [[ "${RUN_LEMUR_TESTS:-1}" == "1" ]]; then
  if [[ ! -d vendor/lemur || ! -d vendor/testez ]]; then
    echo "Skipping Lemur smoke tests: missing vendor submodules. Run: git submodule update --init --recursive"
    exit 1
  fi

  "$LUA_BIN" Tests/Lemur/lemur_runner.lua
fi
