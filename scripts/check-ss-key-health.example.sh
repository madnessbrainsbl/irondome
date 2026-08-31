#!/bin/bash
set -uo pipefail

CONFIG_FILE="${IRON_SS_CONFIG:-/etc/shadowsocks-libev/outline.json}"
LOG_DIR="${IRON_DOME_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/iron-dome}"
LOG_FILE="$LOG_DIR/ss-key-health.log"

mkdir -p "$LOG_DIR"

log() {
  local ts
  ts="$(date -Is)"
  printf '%s %s\n' "$ts" "$*" | tee -a "$LOG_FILE" >&2
}

read_cfg() {
  python3 - "$CONFIG_FILE" <<'PY'
import json, shlex, sys
from pathlib import Path

p = Path(sys.argv[1])
if not p.exists():
    raise SystemExit(2)
cfg = json.loads(p.read_text())
print('SERVER=' + shlex.quote(str(cfg.get('server', ''))))
print('PORT=' + shlex.quote(str(cfg.get('server_port', ''))))
print('METHOD=' + shlex.quote(str(cfg.get('method', ''))))
print('LOCAL=' + shlex.quote(str(cfg.get('local_port', '1080'))))
PY
}

if ! CFG_VARS="$(read_cfg 2>/dev/null)"; then
  log "SS_KEY_STATUS=missing_config ACTION=replace_key CONFIG=$CONFIG_FILE MESSAGE='Outline config missing or unreadable; run: sudo ss-key <ss://key>'"
  exit 2
fi

eval "$CFG_VARS"
SERVER="${SERVER:-}"
PORT="${PORT:-}"
METHOD="${METHOD:-}"
LOCAL="${LOCAL:-1080}"

log "SS_KEY_CHECK_BEGIN server=$SERVER port=$PORT method=$METHOD local=127.0.0.1:$LOCAL secret_logged=no"

SERVICE_OK=no
LISTENER_OK=no
TOR_OK=no
TCP_OK=no
SOCKS_OK=no

if systemctl is-active --quiet iron-ss-outline.service; then SERVICE_OK=yes; fi
if ss -ltn "sport = :$LOCAL" 2>/dev/null | grep -q "127.0.0.1:$LOCAL"; then LISTENER_OK=yes; fi
if curl --socks5-hostname 127.0.0.1:9050 -sS --connect-timeout 8 --max-time 20 https://check.torproject.org/api/ip >/dev/null 2>&1; then TOR_OK=yes; fi
if [[ -n "$SERVER" && -n "$PORT" ]] && nc -vz -x 127.0.0.1:9050 -X 5 -w 15 "$SERVER" "$PORT" >/dev/null 2>&1; then TCP_OK=yes; fi

CURL_ERR="$(mktemp /tmp/iron-ss-key-curl.XXXXXX)"
if curl --socks5-hostname "127.0.0.1:$LOCAL" -sS --connect-timeout 8 --max-time 20 https://api.ipify.org >/dev/null 2>"$CURL_ERR"; then SOCKS_OK=yes; fi

log "SS_KEY_PROBE service=$SERVICE_OK listener=$LISTENER_OK tor=$TOR_OK tcp_to_server=$TCP_OK socks_egress=$SOCKS_OK"

if [[ "$SOCKS_OK" == yes ]]; then
  log "SS_KEY_STATUS=ok MESSAGE='Outline/Shadowsocks key is working.'"
  rm -f "$CURL_ERR"
  exit 0
fi

CURL_MSG="$(tr '\n' ' ' <"$CURL_ERR" | cut -c1-240)"
rm -f "$CURL_ERR"

if [[ "$SERVICE_OK" == yes && "$LISTENER_OK" == yes && "$TOR_OK" == yes && "$TCP_OK" == yes ]]; then
  log "SS_KEY_STATUS=expired_or_invalid ACTION=replace_key MESSAGE='SS/Outline key is likely expired, revoked, invalid, or rejected by the server. Replace it with: sudo ss-key <ss://key>' curl_error='$CURL_MSG'"
  exit 2
fi

log "SS_KEY_STATUS=unknown_bad ACTION=inspect_logs MESSAGE='1080 is unhealthy; inspect journalctl -u iron-ss-outline.service and replace key if needed.' curl_error='$CURL_MSG'"
exit 5
