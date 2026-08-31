#!/bin/bash
set -euo pipefail

if command -v iron-dome-open >/dev/null 2>&1; then
  exec sudo iron-dome-open "$@"
else
  echo "iron-dome-open is not installed on this system." >&2
  exit 1
fi
