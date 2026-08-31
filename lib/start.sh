#!/bin/bash
set -euo pipefail

if [[ -x /usr/local/bin/iron-dome-start ]]; then
  exec sudo /usr/local/bin/iron-dome-start "$@"
fi
echo "iron-dome-start is not installed. Run: irondome setup && irondome render && sudo irondome install" >&2
exit 1
