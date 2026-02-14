#!/bin/bash
# Test runner for Life-Simulator-Game
# Usage: ./run_tests.sh

set -euo pipefail
export PATH="$HOME/.luarocks/bin:$PATH"
busted Tests/Specs/*.lua
