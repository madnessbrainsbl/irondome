#!/bin/bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$LIB_DIR/common.sh"

load_config

service_state() {
  local unit="$1"
  local value
  value="$(systemctl is-active "$unit" 2>/dev/null || true)"
  if [[ -z "$value" ]]; then
    echo unknown
  else
    echo "$value"
  fi
}

echo "=== SERVICES ==="
for s in iron-tor.service iron-ss-outline.service iron-transparent.service iron-dome-lock.service; do
  printf "%-24s %s\n" "$s" "$(service_state "$s")"
done

if [[ "$ENABLE_LOCAL_HTTP_PROXY" == "yes" || "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  printf "%-24s %s\n" "iron-privoxy.service" "$(service_state iron-privoxy.service)"
fi

if [[ "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  for s in iron-google-forward.service iron-cliproxy.service; do
    printf "%-24s %s\n" "$s" "$(service_state "$s")"
  done
fi

echo
echo "=== ENDPOINTS ==="
if curl --socks5-hostname 127.0.0.1:9050 -s --max-time 10 https://check.torproject.org/api/ip | grep -q '"IsTor":true'; then
  echo "TOR 9050: OK"
else
  echo "TOR 9050: FAILED"
fi

if curl --socks5-hostname 127.0.0.1:1080 -s --max-time 10 https://api.ipify.org >/dev/null; then
  echo "OUTLINE 1080: OK"
else
  echo "OUTLINE 1080: FAILED"
fi

if [[ "$ENABLE_LOCAL_HTTP_PROXY" == "yes" || "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  if curl -x http://127.0.0.1:8119 -s --max-time 10 https://api.ipify.org >/dev/null; then
    echo "PRIVOXY 8119: OK"
  else
    echo "PRIVOXY 8119: FAILED"
  fi
fi

if [[ "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  if curl --noproxy '*' -s --max-time 10 http://127.0.0.1:8317/v1/models >/dev/null; then
    echo "GATEWAY 8317: OK"
  else
    echo "GATEWAY 8317: FAILED"
  fi
fi
