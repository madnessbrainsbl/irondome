#!/bin/bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$LIB_DIR/common.sh"

load_config

echo "Config file:     $CONFIG_FILE"
echo "Bridges file:    $BRIDGES_FILE"
echo "Outline key:     $OUTLINE_KEY_FILE"
echo "Generated dir:   $GENERATED_DIR"
echo
echo "Protected user:  $PROTECTED_USER"
echo "Install prefix:  $INSTALL_PREFIX"
echo "Integration:     $INTEGRATION_PROFILE"
echo "HTTP proxy:      $ENABLE_LOCAL_HTTP_PROXY"
echo "Strict mode:     $ENABLE_STRICT"
echo "Open mode:       $ENABLE_OPEN"
echo "Google forward:  $ENABLE_GOOGLE_FORWARD"
echo "Boot cleanup:    $ENABLE_BOOT_CLEANUP"
echo "Root web route:  $INCLUDE_ROOT_WEB"
echo "MTU:             $TRANSPARENT_MTU"

echo
echo "Generated files present:"
for path in "$GENERATED_DIR/torrc.strict" "$GENERATED_DIR/outline.json"; do
  if [[ -f "$path" ]]; then
    echo "  OK  $path"
  else
    echo "  MISSING  $path"
  fi
done

if [[ "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  path="$GENERATED_DIR/integrations/unproxy/local-gateway.yaml"
  if [[ -f "$path" ]]; then
    echo "  OK  $path"
  else
    echo "  MISSING  $path"
  fi
fi
