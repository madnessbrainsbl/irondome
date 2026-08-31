#!/bin/bash
set -euo pipefail

CONFIG_FILE="${IRON_SS_CONFIG:-__OUTLINE_CONFIG__}"
SERVICE_NAME="${IRON_SS_SERVICE:-iron-ss-outline.service}"
LOCAL_HOST="${IRON_SS_LOCAL_HOST:-127.0.0.1}"
LOCAL_PORT="${IRON_SS_LOCAL_PORT:-1080}"

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

KEY="${1:-}"
if [[ -z "$KEY" ]]; then
  printf 'Paste ss:// key and press Enter:\n' >&2
  IFS= read -r KEY
fi

export SS_KEY_INPUT="$KEY"

eval "$({
python3 <<'PY'
import base64
import os
import urllib.parse

key = os.environ.get('SS_KEY_INPUT', '').strip()
if not key:
    print("echo 'Key missing.'; exit 1")
    raise SystemExit

u = urllib.parse.urlsplit(key)
if u.scheme != 'ss':
    print("echo 'Not an ss:// key.'; exit 1")
    raise SystemExit

netloc = u.netloc
if '@' not in netloc:
    print("echo 'Invalid ss:// key: missing @host:port section.'; exit 1")
    raise SystemExit

userinfo, hostport = netloc.rsplit('@', 1)
if ':' not in hostport:
    print("echo 'Invalid ss:// key: unable to parse host/port.'; exit 1")
    raise SystemExit

host, port = hostport.rsplit(':', 1)
userinfo = urllib.parse.unquote(userinfo)
if ':' in userinfo:
    method, password = userinfo.split(':', 1)
else:
    pad = '=' * (-len(userinfo) % 4)
    try:
        decoded = base64.urlsafe_b64decode((userinfo + pad).encode()).decode('utf-8')
        method, password = decoded.split(':', 1)
    except Exception:
        print("echo 'Invalid ss:// key: unable to decode credentials.'; exit 1")
        raise SystemExit

try:
    int(port)
except ValueError:
    print("echo 'Invalid ss:// key: port must be numeric.'; exit 1")
    raise SystemExit

def sh(value):
    return "'" + value.replace("'", "'\"'\"'") + "'"

print(f"HOST={sh(host)}")
print(f"PORT={sh(str(port))}")
print(f"METHOD={sh(method)}")
print(f"PASS={sh(password)}")
print(f"TAG={sh(urllib.parse.unquote(u.fragment))}")
PY
})"

if [[ -z "${HOST:-}" || -z "${PORT:-}" || -z "${METHOD:-}" || -z "${PASS:-}" ]]; then
  echo "Invalid ss:// key."
  exit 1
fi

BACKUP_FILE="$(mktemp /tmp/outline.json.XXXXXX)"
COMMITTED="no"

if [[ -f "$CONFIG_FILE" ]]; then
  cp -a "$CONFIG_FILE" "$BACKUP_FILE"
else
  install -d -m 0755 "$(dirname "$CONFIG_FILE")"
  : > "$BACKUP_FILE"
fi

rollback() {
  if [[ "$COMMITTED" != "yes" ]]; then
    cp -a "$BACKUP_FILE" "$CONFIG_FILE" 2>/dev/null || true
    systemctl restart "$SERVICE_NAME" 2>/dev/null || true
  fi
  rm -f "$BACKUP_FILE"
}

print_exit_geo() {
  local geo_file geo_vars country_code country_name city region asn org
  geo_file="$(mktemp /tmp/outline-geo.XXXXXX)"

  if ! curl --socks5-hostname "${LOCAL_HOST}:${LOCAL_PORT}" -sS --connect-timeout 8 --max-time 20 https://ipapi.co/json/ >"$geo_file" 2>/dev/null; then
    rm -f "$geo_file"
    return 0
  fi

  if ! geo_vars="$(python3 - "$geo_file" <<'PY'
import json
import shlex
import sys
from pathlib import Path

try:
    data = json.loads(Path(sys.argv[1]).read_text())
except Exception:
    raise SystemExit(1)

def emit(name, value):
    print(f"{name}={shlex.quote(str(value or ''))}")

emit('country_code', data.get('country_code'))
emit('country_name', data.get('country_name'))
emit('city', data.get('city'))
emit('region', data.get('region'))
emit('asn', data.get('asn'))
emit('org', data.get('org'))
PY
)"; then
    rm -f "$geo_file"
    return 0
  fi
  rm -f "$geo_file"

  eval "$geo_vars"

  echo "Exit geo: ${country_code:-unknown} ${country_name:-unknown}, ${city:-unknown}${region:+, $region}; ASN ${asn:-unknown}; org ${org:-unknown}"
  if [[ -n "${TAG:-}" ]]; then
    echo "Key label: $TAG"
  fi

  case "${country_code:-}" in
    US|CA|GB|AU|NZ|JP|KR|SG)
      echo "Antigravity geo hint: better chance, but API test below is authoritative."
      ;;
    "")
      echo "Antigravity geo hint: unknown; API test below is authoritative."
      ;;
    *)
      echo "Antigravity geo hint: RISK - ${country_code} may be rejected by Gemini/Antigravity."
      ;;
  esac
}

check_antigravity_gemini() {
  local model req resp_file http_code message curl_status
  model="${IRON_SS_KEY_ANTIGRAVITY_MODEL:-gemini-3.1-flash-lite}"

  if ! curl --noproxy '*' -sS --connect-timeout 3 --max-time 5 http://127.0.0.1:8317/v1/models >/dev/null 2>&1; then
    echo "Antigravity Gemini check: SKIP (local gateway 127.0.0.1:8317 is not ready)"
    return 0
  fi

  req="$(python3 - "$model" <<'PY'
import json
import sys

print(json.dumps({
    'model': sys.argv[1],
    'messages': [{'role': 'user', 'content': 'ping'}],
    'max_tokens': 1,
    'stream': False,
}, separators=(',', ':')))
PY
)"

  resp_file="$(mktemp /tmp/antigravity-gemini-check.XXXXXX)"
  curl_status=0
  http_code="$(curl --noproxy '*' -sS --connect-timeout 5 --max-time 45 \
    -o "$resp_file" -w '%{http_code}' \
    http://127.0.0.1:8317/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d "$req" 2>/dev/null)" || curl_status=$?

  if [[ "$curl_status" -ne 0 ]]; then
    echo "Antigravity Gemini check: FAIL (curl error $curl_status)"
    rm -f "$resp_file"
    return 0
  fi

  message="$(python3 - "$resp_file" <<'PY'
import json
import sys
from pathlib import Path

try:
    data = json.loads(Path(sys.argv[1]).read_text())
except Exception:
    print('')
    raise SystemExit(0)

err = data.get('error') if isinstance(data, dict) else None
if isinstance(err, dict):
    print(err.get('message') or err.get('status') or '')
PY
)"
  rm -f "$resp_file"

  case "$http_code" in
    2*)
      echo "Antigravity Gemini check ($model): OK"
      ;;
    *)
      if [[ "$message" == *"User location is not supported"* ]]; then
        echo "Antigravity Gemini check ($model): BLOCKED - location is not supported"
      elif [[ -n "$message" ]]; then
        echo "Antigravity Gemini check ($model): FAIL HTTP $http_code - $message"
      else
        echo "Antigravity Gemini check ($model): FAIL HTTP $http_code"
      fi
      ;;
  esac
}

trap rollback INT TERM EXIT

CONFIG_FILE="$CONFIG_FILE" HOST="$HOST" PORT="$PORT" PASS="$PASS" METHOD="$METHOD" LOCAL_HOST="$LOCAL_HOST" LOCAL_PORT="$LOCAL_PORT" python3 <<'PY'
import json
import os
from pathlib import Path

cfg = {
    'server': os.environ['HOST'],
    'server_port': int(os.environ['PORT']),
    'password': os.environ['PASS'],
    'method': os.environ['METHOD'],
    'local_address': os.environ['LOCAL_HOST'],
    'local_port': int(os.environ['LOCAL_PORT']),
    'timeout': 300,
}

Path(os.environ['CONFIG_FILE']).write_text(json.dumps(cfg, indent=2) + '\n')
PY
chmod 0644 "$CONFIG_FILE"

systemctl daemon-reload
if systemctl list-unit-files "$SERVICE_NAME" >/dev/null 2>&1; then
  systemctl restart "$SERVICE_NAME"
fi

sleep 5
echo -n "${LOCAL_PORT} check: "
if EXIT_IP="$(curl --socks5-hostname "${LOCAL_HOST}:${LOCAL_PORT}" -sS --max-time 20 https://api.ipify.org)"; then
  printf '%s\n' "$EXIT_IP"
  COUNTRY_CODE="$(curl --socks5-hostname "${LOCAL_HOST}:${LOCAL_PORT}" -sS --max-time 12 https://ipapi.co/country_code/ 2>/dev/null || true)"
  print_exit_geo
  check_antigravity_gemini
  if [[ "$COUNTRY_CODE" == "RU" ]]; then
    echo "Warning: Outline exit country is $COUNTRY_CODE ($EXIT_IP); Antigravity API may reject this location." >&2
    echo "For Antigravity, configure a separate supported-region proxy instead of blocking this RU key." >&2
  fi
  COMMITTED="yes"
  rm -f "$BACKUP_FILE"
  trap - INT TERM EXIT
  if [[ -n "$COUNTRY_CODE" ]]; then
    echo "Outline config updated. Exit country: $COUNTRY_CODE"
  else
    echo "Outline config updated."
  fi
else
  echo
  echo "${LOCAL_PORT} check failed; restoring previous Outline config." >&2
  exit 1
fi
