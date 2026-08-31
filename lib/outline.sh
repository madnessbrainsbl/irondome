#!/bin/bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$LIB_DIR/common.sh"

ensure_dirs
print_header "Outline key"
outline_key="$(read_ss_key "${1:-}")"
write_secret_file "$OUTLINE_KEY_FILE" "$outline_key"
echo
echo "Saved key to: $OUTLINE_KEY_FILE"
