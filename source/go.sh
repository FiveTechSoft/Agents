#!/bin/bash
# Build the Agents console for Linux (static, gttrm).
set -e
cd "$(dirname "$0")"
export PATH="${HB_BIN:-$HOME/harbour/bin/linux/gcc}:$PATH"
hbmk2 agents_linux.hbp "$@"
echo "OK -> $(cd .. && pwd)/agents"
