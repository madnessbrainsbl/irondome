#!/bin/bash
set -euo pipefail

if command -v iron-dome-stop >/dev/null 2>&1; then
  exec sudo iron-dome-stop "$@"
else
  echo "iron-dome-stop is not installed on this system." >&2
  exit 1
fi
