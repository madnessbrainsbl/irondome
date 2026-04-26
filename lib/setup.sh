#!/bin/bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$LIB_DIR/common.sh"

load_config
ensure_dirs

CURRENT_USER="$(id -un)"
if [[ "$PROTECTED_USER" == "kali" && "$CURRENT_USER" != "kali" ]]; then
  PROTECTED_USER="$CURRENT_USER"
fi

print_header "setup wizard"

DEFAULT_USER="$PROTECTED_USER"
read -r -p "Protected user: " PROTECTED_USER_INPUT
PROTECTED_USER="${PROTECTED_USER_INPUT:-$DEFAULT_USER}"
INSTALL_PREFIX="$(prompt_default 'Install prefix' "$INSTALL_PREFIX")"
TRANSPARENT_MTU="$(prompt_default 'Transparent route MTU' "$TRANSPARENT_MTU")"
ENABLE_STRICT="$(prompt_yes_no 'Enable strict transparent mode' "$ENABLE_STRICT")"
ENABLE_OPEN="$(prompt_yes_no 'Enable open mode support' "$ENABLE_OPEN")"
ENABLE_BOOT_CLEANUP="$(prompt_yes_no 'Enable boot cleanup service' "$ENABLE_BOOT_CLEANUP")"
INCLUDE_ROOT_WEB="$(prompt_yes_no 'Route root web traffic through strict mode' "$INCLUDE_ROOT_WEB")"
ENABLE_LOCAL_HTTP_PROXY="$(prompt_yes_no 'Enable local HTTP proxy layer' "$ENABLE_LOCAL_HTTP_PROXY")"

print_header "Integration profile"
echo "Available profiles:"
echo "  none         Core only"
echo "  unproxy      Optional local gateway integration example"
INTEGRATION_PROFILE="$(prompt_default 'Integration profile' "$INTEGRATION_PROFILE")"

case "$INTEGRATION_PROFILE" in
  none)
    ENABLE_GOOGLE_FORWARD="no"
    ;;
  unproxy)
    CLIPROXY_BIN="$(prompt_default 'Local API gateway binary path' "$CLIPROXY_BIN")"
    CLIPROXY_WORKDIR="$(prompt_default 'Local API gateway working directory' "$CLIPROXY_WORKDIR")"
    CLIPROXY_AUTH_DIR="$(prompt_default 'Gateway auth directory' "$CLIPROXY_AUTH_DIR")"
    CLIPROXY_STORAGE_DIR="$(prompt_default 'Gateway storage directory' "$CLIPROXY_STORAGE_DIR")"
    ENABLE_GOOGLE_FORWARD="$(prompt_yes_no 'Enable Google/OAuth forward' "$ENABLE_GOOGLE_FORWARD")"
    ;;
  *)
    echo "Unknown integration profile: $INTEGRATION_PROFILE" >&2
    exit 1
    ;;
esac

collect_multiline "$BRIDGES_FILE" "Tor bridges"

print_header "Outline key"
echo "Paste your Outline ss:// key and press Enter:"
IFS= read -r outline_key
printf '%s\n' "$outline_key" > "$OUTLINE_KEY_FILE"

save_config

echo
echo "Configuration saved to: $CONFIG_FILE"
echo "Bridges saved to:       $BRIDGES_FILE"
echo "Outline key saved to:   $OUTLINE_KEY_FILE"

render_now="$(prompt_yes_no 'Render install-ready files now' 'yes')"
if [[ "$render_now" == "yes" ]]; then
  "$LIB_DIR/render.sh"
fi
