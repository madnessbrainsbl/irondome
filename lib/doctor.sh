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

echo
echo "=== LOCK ==="
if ip route get 1.1.1.1 uid "$(id -u)" 2>/dev/null | grep -q 'dev iron0'; then
  echo "ROUTE iron0: OK"
else
  echo "ROUTE iron0: FAILED"
fi

DIRECT_IF="$(ip -4 route show default 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')"
if [[ -n "$DIRECT_IF" ]] && curl --interface "$DIRECT_IF" -s --connect-timeout 2 --max-time 3 https://api.ipify.org >/dev/null 2>&1; then
  echo "DIRECT EGRESS: LEAK"
else
  echo "DIRECT EGRESS: BLOCKED"
fi

if curl -6 -s --connect-timeout 2 --max-time 3 https://api64.ipify.org >/dev/null 2>&1; then
  echo "IPv6: LEAK"
else
  echo "IPv6: BLOCKED"
fi
