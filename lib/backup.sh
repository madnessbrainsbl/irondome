#!/bin/bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$LIB_DIR/common.sh"

ensure_dirs
BACKUP_DIR="$ROOT_DIR/backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

for file in "$CONFIG_FILE" "$BRIDGES_FILE" "$OUTLINE_KEY_FILE"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/"
done

echo "Saved backup to: $BACKUP_DIR"
