#!/bin/bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$LIB_DIR/common.sh"

ensure_dirs
collect_multiline "$BRIDGES_FILE" "Tor bridges"
echo
echo "Saved bridges to: $BRIDGES_FILE"
