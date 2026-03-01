#!/bin/bash
# Test runner for Life-Simulator-Game
# Usage: ./run_tests.sh

set -euo pipefail
export PATH="$HOME/.luarocks/bin:$PATH"
if command -v luarocks >/dev/null 2>&1; then
  eval "$(luarocks --lua-version=5.1 --tree="$HOME/.luarocks" path)"
fi

busted Tests/Specs/*.lua
