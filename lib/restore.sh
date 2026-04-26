#!/bin/bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$LIB_DIR/common.sh"

if [[ $# -ne 1 ]]; then
  echo "Usage: irondome restore <backup-directory>" >&2
  exit 1
fi

BACKUP_DIR="$1"
[[ -d "$BACKUP_DIR" ]] || { echo "Backup directory not found: $BACKUP_DIR" >&2; exit 1; }

ensure_dirs
[[ -f "$BACKUP_DIR/unproxy.env" ]] && cp -a "$BACKUP_DIR/unproxy.env" "$CONFIG_FILE"
[[ -f "$BACKUP_DIR/bridges.txt" ]] && cp -a "$BACKUP_DIR/bridges.txt" "$BRIDGES_FILE"
[[ -f "$BACKUP_DIR/outline_ss_key.txt" ]] && cp -a "$BACKUP_DIR/outline_ss_key.txt" "$OUTLINE_KEY_FILE"

echo "Restored state from: $BACKUP_DIR"
