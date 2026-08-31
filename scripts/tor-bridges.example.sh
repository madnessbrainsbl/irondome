#!/bin/bash
set -euo pipefail

TORRC="${IRON_TORRC:-__TORRC__}"
STATE_BRIDGES="${IRON_STATE_BRIDGES:-__STATE_BRIDGES__}"
TOR_SERVICE="${IRON_TOR_SERVICE:-iron-tor.service}"
SS_SERVICE="${IRON_SS_SERVICE:-iron-ss-outline.service}"
TOR_PORT="${IRON_TOR_PORT:-9050}"
SS_PORT="${IRON_SS_PORT:-1080}"
BOOTSTRAP_TRIES="${IRON_TOR_BOOTSTRAP_TRIES:-45}"

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

[[ -f "$TORRC" ]] || { echo "torrc not found: $TORRC" >&2; exit 1; }

BRIDGES=()
if [[ "$#" -gt 0 ]]; then
  BRIDGES=("$@")
else
  echo "Paste bridge lines, one per line. Empty line ends input." >&2
  while IFS= read -r line; do
    [[ -z "$line" ]] && break
    BRIDGES+=("$line")
  done
fi

# Normalise: strip an optional leading "Bridge ", drop blanks, collect transports.
NORMALISED=()
TRANSPORTS=""
for raw in "${BRIDGES[@]}"; do
  line="${raw#Bridge }"
  line="${line#"${line%%[![:space:]]*}"}"
  [[ -z "$line" ]] && continue
  NORMALISED+=("$line")
  transport="${line%% *}"
  # A vanilla bridge starts with an address, not a transport name.
  if [[ "$transport" =~ ^[a-z][a-z0-9_]*$ ]]; then
    case " $TRANSPORTS " in
      *" $transport "*) ;;
      *) TRANSPORTS="${TRANSPORTS}${transport} " ;;
    esac
  fi
done

if [[ "${#NORMALISED[@]}" -eq 0 ]]; then
  echo "No bridges provided." >&2
  exit 1
fi

plugin_line() {
  case "$1" in
    obfs4|meek_lite) echo "ClientTransportPlugin $1 exec /usr/bin/obfs4proxy" ;;
    snowflake) echo "ClientTransportPlugin snowflake exec /usr/bin/snowflake-client" ;;
    *) echo "Unknown transport '$1': add its ClientTransportPlugin line to $TORRC by hand." >&2 ;;
  esac
}

BACKUP_FILE="$(mktemp /tmp/torrc.strict.XXXXXX)"
cp -a "$TORRC" "$BACKUP_FILE"
COMMITTED="no"

rollback() {
  if [[ "$COMMITTED" != "yes" ]]; then
    cp -a "$BACKUP_FILE" "$TORRC" 2>/dev/null || true
    systemctl restart "$TOR_SERVICE" 2>/dev/null || true
    systemctl restart "$SS_SERVICE" 2>/dev/null || true
  fi
  rm -f "$BACKUP_FILE"
}
trap rollback INT TERM EXIT

TMP_TORRC="$(mktemp /tmp/torrc.new.XXXXXX)"
grep -vE '^[[:space:]]*(UseBridges|ClientTransportPlugin|Bridge)[[:space:]]' "$TORRC" > "$TMP_TORRC"
{
  echo "UseBridges 1"
  for transport in $TRANSPORTS; do
    plugin_line "$transport"
  done
  for line in "${NORMALISED[@]}"; do
    echo "Bridge $line"
  done
} >> "$TMP_TORRC"

cat "$TMP_TORRC" > "$TORRC"
rm -f "$TMP_TORRC"

# Keep the CLI state in sync, otherwise the next `irondome render` silently
# reinstalls the old bridge list over this one.
if [[ -n "$STATE_BRIDGES" && -d "$(dirname "$STATE_BRIDGES")" ]]; then
  printf '%s\n' "${NORMALISED[@]}" > "$STATE_BRIDGES"
  chmod 0600 "$STATE_BRIDGES"
fi

systemctl restart "$TOR_SERVICE"

echo -n "Tor bootstrap: "
BOOTSTRAPPED="no"
for _ in $(seq 1 "$BOOTSTRAP_TRIES"); do
  if curl --socks5-hostname "127.0.0.1:${TOR_PORT}" -s --max-time 10 \
      https://check.torproject.org/api/ip | grep -q '"IsTor":true'; then
    BOOTSTRAPPED="yes"
    echo " OK"
    break
  fi
  echo -n "."
  sleep 2
done

if [[ "$BOOTSTRAPPED" != "yes" ]]; then
  echo " FAILED"
  echo "Bridges did not bootstrap; restoring the previous list." >&2
  exit 1
fi

# ss-local reaches the Outline server through Tor, so it has to follow the restart.
if systemctl list-unit-files "$SS_SERVICE" >/dev/null 2>&1; then
  systemctl restart "$SS_SERVICE"
  echo -n "${SS_PORT} check: "
  if EXIT_IP="$(curl --socks5-hostname "127.0.0.1:${SS_PORT}" -sS --max-time 25 https://api.ipify.org)"; then
    printf '%s\n' "$EXIT_IP"
  else
    echo
    echo "Tor came up but ${SS_PORT} has no egress; restoring the previous bridge list." >&2
    exit 1
  fi
fi

COMMITTED="yes"
rm -f "$BACKUP_FILE"
trap - INT TERM EXIT
echo "Bridges updated: ${#NORMALISED[@]} line(s) in $TORRC"
