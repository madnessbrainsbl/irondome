#!/bin/bash
set -euo pipefail

if [[ -x /usr/local/bin/iron-dome-open ]]; then
  exec sudo /usr/local/bin/iron-dome-open "$@"
fi
if [[ -x /usr/local/bin/iron-dome-start ]]; then
  exec sudo /usr/local/bin/iron-dome-start --no-lock "$@"
fi
echo "iron-dome-open is not installed. Run: irondome setup && irondome render && sudo irondome install" >&2
exit 1
