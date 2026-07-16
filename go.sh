#!/bin/bash
# Build console binary into repo root.
exec "$(dirname "$0")/source/go.sh" "$@"
