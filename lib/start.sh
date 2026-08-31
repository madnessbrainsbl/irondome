#!/bin/bash
set -euo pipefail

if command -v iron-dome-start >/dev/null 2>&1; then
  exec sudo iron-dome-start "$@"
else
  echo "iron-dome-start is not installed on this system." >&2
  exit 1
fi
