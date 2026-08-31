#!/bin/bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$LIB_DIR/common.sh"

if [[ $# -gt 1 ]]; then
  echo "Usage: irondome restore [backup-directory]" >&2
  exit 1
fi

BACKUP_DIR="${1:-}"
if [[ -z "$BACKUP_DIR" ]]; then
  # No argument: take the newest backup. Names are timestamps, so sort order == time order.
  BACKUP_DIR="$(find "$ROOT_DIR/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -n 1)"
  [[ -n "$BACKUP_DIR" ]] || { echo "No backups found in $ROOT_DIR/backups" >&2; exit 1; }
fi
[[ -d "$BACKUP_DIR" ]] || { echo "Backup directory not found: $BACKUP_DIR" >&2; exit 1; }

ensure_dirs
restored=0
for name in irondome.env bridges.txt outline_ss_key.txt; do
  src="$BACKUP_DIR/$name"
  [[ -f "$src" ]] || continue
  case "$name" in
    irondome.env) cp -a "$src" "$CONFIG_FILE" ;;
    bridges.txt) cp -a "$src" "$BRIDGES_FILE" ;;
    outline_ss_key.txt) cp -a "$src" "$OUTLINE_KEY_FILE" ;;
  esac
  restored=$((restored + 1))
done

if [[ "$restored" -eq 0 ]]; then
  echo "Nothing to restore from: $BACKUP_DIR" >&2
  exit 1
fi

chmod 0600 "$OUTLINE_KEY_FILE" 2>/dev/null || true
echo "Restored $restored file(s) from: $BACKUP_DIR"
