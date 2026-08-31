#!/bin/bash
set -euo pipefail

if [[ -x /usr/local/bin/iron-dome-stop ]]; then
  exec sudo /usr/local/bin/iron-dome-stop "$@"
fi
echo "iron-dome-stop is not installed. Run: irondome setup && irondome render && sudo irondome install" >&2
exit 1
