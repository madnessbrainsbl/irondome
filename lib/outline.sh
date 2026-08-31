#!/bin/bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$LIB_DIR/common.sh"

ensure_dirs
print_header "Outline key"
echo "Paste your Outline ss:// key and press Enter:"
IFS= read -r outline_key
write_secret_file "$OUTLINE_KEY_FILE" "$outline_key"
echo
echo "Saved key to: $OUTLINE_KEY_FILE"
