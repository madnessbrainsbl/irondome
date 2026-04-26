#!/bin/bash
set -euo pipefail

KEY="${1:-}"
if [[ -z "$KEY" ]]; then
  printf 'Paste ss:// key and press Enter:\n' >&2
  IFS= read -r KEY
fi

export SS_KEY_INPUT="$KEY"

python3 <<'PY'
import os, base64, urllib.parse, json

key = os.environ.get('SS_KEY_INPUT', '').strip()
if not key:
    raise SystemExit('Key missing')

u = urllib.parse.urlsplit(key)
if u.scheme != 'ss':
    raise SystemExit('Not an ss:// key')

userinfo, hostport = u.netloc.rsplit('@', 1)
host, port = hostport.rsplit(':', 1)
userinfo = urllib.parse.unquote(userinfo)
if ':' in userinfo:
    method, password = userinfo.split(':', 1)
else:
    pad = '=' * (-len(userinfo) % 4)
    decoded = base64.urlsafe_b64decode((userinfo + pad).encode()).decode('utf-8')
    method, password = decoded.split(':', 1)

cfg = {
    'server': host,
    'server_port': int(port),
    'password': password,
    'method': method,
    'local_address': '127.0.0.1',
    'local_port': 1080,
    'timeout': 300,
}
print(json.dumps(cfg, indent=2))
PY
