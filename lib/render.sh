#!/bin/bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$LIB_DIR/common.sh"

load_config
ensure_dirs

require_state_file "$BRIDGES_FILE" "Bridges file is missing. Run: irondome bridges"
require_state_file "$OUTLINE_KEY_FILE" "Outline key is missing. Run: irondome outline"

rm -rf "$GENERATED_DIR"
mkdir -p "$GENERATED_DIR/systemd" "$GENERATED_DIR/bin" "$GENERATED_DIR/libexec" "$GENERATED_DIR/config"

cp "$TEMPLATES_DIR/torrc.strict.example" "$GENERATED_DIR/config/torrc.strict"
while IFS= read -r bridge; do
  [[ -z "$bridge" ]] && continue
  [[ "$bridge" =~ ^Bridge[[:space:]] ]] || bridge="Bridge $bridge"
  printf '%s\n' "$bridge" >> "$GENERATED_DIR/config/torrc.strict"
done < "$BRIDGES_FILE"

OUTLINE_KEY_FILE="$OUTLINE_KEY_FILE" parse_ss_key_to_outline_json "$GENERATED_DIR/config/outline.json"

if [[ "$ENABLE_LOCAL_HTTP_PROXY" == "yes" || "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  cp "$TEMPLATES_DIR/privoxy.conf.example" "$GENERATED_DIR/config/privoxy.conf"
fi

export ROOT_DIR INSTALL_PREFIX CLIPROXY_BIN CLIPROXY_WORKDIR
for template in "$SYSTEMD_TEMPLATES_DIR"/*.example; do
  name="$(basename "$template" .example)"
  case "$name" in
    iron-cliproxy.service|iron-google-forward.service)
      continue
      ;;
  esac
  if [[ "$name" == "iron-privoxy.service" && "$ENABLE_LOCAL_HTTP_PROXY" != "yes" && "$INTEGRATION_PROFILE" != "unproxy" ]]; then
    continue
  fi
  render_template_file "$template" "$GENERATED_DIR/systemd/$name"
done

cat > "$GENERATED_DIR/libexec/iron-transparent-generate" <<EOF
#!/bin/bash
set -euo pipefail

RUN_DIR="/run/iron-dome"
CONFIG_FILE="\$RUN_DIR/sing-box.json"
KUID="\$(id -u $PROTECTED_USER)"
INCLUDE_UIDS="[\$KUID"
if [[ "$INCLUDE_ROOT_WEB" == "yes" ]]; then
  INCLUDE_UIDS+=", 0"
fi
INCLUDE_UIDS+="]"

install -d -m 0755 "\$RUN_DIR"

cat > "\$CONFIG_FILE" <<JSON
{
  "log": {"level": "warn"},
  "dns": {
    "servers": [
      {
        "type": "https",
        "tag": "remote-dns",
        "server": "1.1.1.1",
        "server_port": 443,
        "path": "/dns-query",
        "detour": "outline-socks"
      }
    ],
    "final": "remote-dns",
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "iron-tun",
      "interface_name": "iron0",
      "address": ["172.19.0.1/30"],
      "mtu": $TRANSPARENT_MTU,
      "auto_route": true,
      "auto_redirect": true,
      "strict_route": true,
      "stack": "system",
      "include_uid": \$INCLUDE_UIDS
    }
  ],
  "outbounds": [
    {"type": "socks", "tag": "outline-socks", "server": "127.0.0.1", "server_port": 1080, "version": "5"},
    {"type": "direct", "tag": "direct"}
  ],
  "route": {
    "auto_detect_interface": true,
    "final": "outline-socks",
    "rules": [
      {"action": "sniff"},
      {"type": "logical", "mode": "or", "rules": [{"protocol": "dns"}, {"port": 53}], "action": "hijack-dns"},
      {"network": "udp", "action": "reject"}
    ]
  }
}
JSON

chmod 0644 "\$CONFIG_FILE"
EOF
chmod 0755 "$GENERATED_DIR/libexec/iron-transparent-generate"

cat > "$GENERATED_DIR/libexec/iron-dome-lock-apply" <<EOF
#!/bin/bash
set -euo pipefail

KUID="\$(id -u $PROTECTED_USER)"
CUID="\$(id -u cliproxysvc)"
PUID="\$(id -u privoxy)"
OUTLINE_IP="\$(python3 - <<'PY'
import json
from pathlib import Path
cfg=json.loads(Path('$INSTALL_PREFIX/config/outline.json').read_text())
print(cfg['server'])
PY
)"
OUTLINE_PORT="\$(python3 - <<'PY'
import json
from pathlib import Path
cfg=json.loads(Path('$INSTALL_PREFIX/config/outline.json').read_text())
print(cfg['server_port'])
PY
)"
TRANSPARENT_MARK_A="0x2023/0xffffffff"
TRANSPARENT_MARK_B="0x2024/0xffffffff"
INCLUDE_ROOT_WEB="$INCLUDE_ROOT_WEB"

delete_rule() {
  local tool="\$1"; shift
  while "\$tool" -C OUTPUT "\$@" 2>/dev/null; do "\$tool" -D OUTPUT "\$@"; done
}

delete_mangle_rule() {
  local tool="\$1"; shift
  while "\$tool" -t mangle -C OUTPUT "\$@" 2>/dev/null; do "\$tool" -t mangle -D OUTPUT "\$@"; done
}

insert_pair() {
  local tool="\$1"; local uid="\$2"
  delete_rule "\$tool" -m owner --uid-owner "\$uid" ! -o lo -j REJECT
  delete_rule "\$tool" -m owner --uid-owner "\$uid" -o lo -j ACCEPT
  "\$tool" -I OUTPUT 1 -m owner --uid-owner "\$uid" ! -o lo -j REJECT
  "\$tool" -I OUTPUT 1 -m owner --uid-owner "\$uid" -o lo -j ACCEPT
}

insert_user_ipv4() {
  local uid="\$1"
  delete_mangle_rule iptables -m owner --uid-owner "\$uid" ! -o lo -j MARK --set-xmark "\$TRANSPARENT_MARK_A"
  delete_rule iptables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
  delete_rule iptables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
  delete_rule iptables -m owner --uid-owner "\$uid" ! -o lo -j REJECT
  delete_rule iptables -m owner --uid-owner "\$uid" -o lo -j ACCEPT
  iptables -t mangle -I OUTPUT 1 -m owner --uid-owner "\$uid" ! -o lo -j MARK --set-xmark "\$TRANSPARENT_MARK_A"
  iptables -I OUTPUT 1 -m owner --uid-owner "\$uid" ! -o lo -j REJECT
  iptables -I OUTPUT 1 -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
  iptables -I OUTPUT 1 -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
  iptables -I OUTPUT 1 -m owner --uid-owner "\$uid" -o lo -j ACCEPT
}

insert_user_ipv6() {
  local uid="\$1"
  delete_mangle_rule ip6tables -m owner --uid-owner "\$uid" ! -o lo -j MARK --set-xmark "\$TRANSPARENT_MARK_A"
  delete_rule ip6tables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
  delete_rule ip6tables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
  delete_rule ip6tables -m owner --uid-owner "\$uid" ! -o lo -j REJECT
  delete_rule ip6tables -m owner --uid-owner "\$uid" -o lo -j ACCEPT
  ip6tables -t mangle -I OUTPUT 1 -m owner --uid-owner "\$uid" ! -o lo -j MARK --set-xmark "\$TRANSPARENT_MARK_A"
  ip6tables -I OUTPUT 1 -m owner --uid-owner "\$uid" ! -o lo -j REJECT
  ip6tables -I OUTPUT 1 -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
  ip6tables -I OUTPUT 1 -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
  ip6tables -I OUTPUT 1 -m owner --uid-owner "\$uid" -o lo -j ACCEPT
}

insert_cliproxy_ipv4() {
  delete_rule iptables -m owner --uid-owner "\$CUID" -d "\$OUTLINE_IP" -p tcp --dport "\$OUTLINE_PORT" -j ACCEPT
  delete_rule iptables -m owner --uid-owner "\$CUID" ! -o lo -j REJECT
  delete_rule iptables -m owner --uid-owner "\$CUID" -o lo -j ACCEPT
  iptables -I OUTPUT 1 -m owner --uid-owner "\$CUID" ! -o lo -j REJECT
  iptables -I OUTPUT 1 -m owner --uid-owner "\$CUID" -d "\$OUTLINE_IP" -p tcp --dport "\$OUTLINE_PORT" -j ACCEPT
  iptables -I OUTPUT 1 -m owner --uid-owner "\$CUID" -o lo -j ACCEPT
}

insert_cliproxy_ipv6() {
  delete_rule ip6tables -m owner --uid-owner "\$CUID" ! -o lo -j REJECT
  delete_rule ip6tables -m owner --uid-owner "\$CUID" -o lo -j ACCEPT
  ip6tables -I OUTPUT 1 -m owner --uid-owner "\$CUID" ! -o lo -j REJECT
  ip6tables -I OUTPUT 1 -m owner --uid-owner "\$CUID" -o lo -j ACCEPT
}

insert_pair iptables "\$PUID"
insert_pair ip6tables "\$PUID"
insert_user_ipv4 "\$KUID"
insert_user_ipv6 "\$KUID"
if [[ "\$INCLUDE_ROOT_WEB" == "yes" ]]; then
  insert_user_ipv4 0
  insert_user_ipv6 0
fi
insert_cliproxy_ipv4
insert_cliproxy_ipv6
EOF
chmod 0755 "$GENERATED_DIR/libexec/iron-dome-lock-apply"

cat > "$GENERATED_DIR/libexec/iron-dome-lock-clear" <<EOF
#!/bin/bash
set -euo pipefail

KUID="\$(id -u $PROTECTED_USER)"
CUID="\$(id -u cliproxysvc)"
PUID="\$(id -u privoxy)"
OUTLINE_IP="\$(python3 - <<'PY'
import json
from pathlib import Path
cfg=json.loads(Path('$INSTALL_PREFIX/config/outline.json').read_text())
print(cfg['server'])
PY
)"
OUTLINE_PORT="\$(python3 - <<'PY'
import json
from pathlib import Path
cfg=json.loads(Path('$INSTALL_PREFIX/config/outline.json').read_text())
print(cfg['server_port'])
PY
)"
TRANSPARENT_MARK_A="0x2023/0xffffffff"
TRANSPARENT_MARK_B="0x2024/0xffffffff"
INCLUDE_ROOT_WEB="$INCLUDE_ROOT_WEB"

delete_rule() {
  local tool="\$1"; shift
  while "\$tool" -C OUTPUT "\$@" 2>/dev/null; do "\$tool" -D OUTPUT "\$@"; done
}

delete_mangle_rule() {
  local tool="\$1"; shift
  while "\$tool" -t mangle -C OUTPUT "\$@" 2>/dev/null; do "\$tool" -t mangle -D OUTPUT "\$@"; done
}

for tool in iptables ip6tables; do
  delete_rule "\$tool" -m owner --uid-owner "\$PUID" ! -o lo -j REJECT
  delete_rule "\$tool" -m owner --uid-owner "\$PUID" -o lo -j ACCEPT
done

for uid in "\$KUID"; do
  delete_mangle_rule iptables -m owner --uid-owner "\$uid" ! -o lo -j MARK --set-xmark "\$TRANSPARENT_MARK_A"
  delete_rule iptables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
  delete_rule iptables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
  delete_rule iptables -m owner --uid-owner "\$uid" ! -o lo -j REJECT
  delete_rule iptables -m owner --uid-owner "\$uid" -o lo -j ACCEPT
  delete_mangle_rule ip6tables -m owner --uid-owner "\$uid" ! -o lo -j MARK --set-xmark "\$TRANSPARENT_MARK_A"
  delete_rule ip6tables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
  delete_rule ip6tables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
  delete_rule ip6tables -m owner --uid-owner "\$uid" ! -o lo -j REJECT
  delete_rule ip6tables -m owner --uid-owner "\$uid" -o lo -j ACCEPT
done

if [[ "\$INCLUDE_ROOT_WEB" == "yes" ]]; then
  for uid in 0; do
    delete_mangle_rule iptables -m owner --uid-owner "\$uid" ! -o lo -j MARK --set-xmark "\$TRANSPARENT_MARK_A"
    delete_rule iptables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
    delete_rule iptables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
    delete_rule iptables -m owner --uid-owner "\$uid" ! -o lo -j REJECT
    delete_rule iptables -m owner --uid-owner "\$uid" -o lo -j ACCEPT
    delete_mangle_rule ip6tables -m owner --uid-owner "\$uid" ! -o lo -j MARK --set-xmark "\$TRANSPARENT_MARK_A"
    delete_rule ip6tables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
    delete_rule ip6tables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
    delete_rule ip6tables -m owner --uid-owner "\$uid" ! -o lo -j REJECT
    delete_rule ip6tables -m owner --uid-owner "\$uid" -o lo -j ACCEPT
  done
fi

delete_rule iptables -m owner --uid-owner "\$CUID" -d "\$OUTLINE_IP" -p tcp --dport "\$OUTLINE_PORT" -j ACCEPT
delete_rule iptables -m owner --uid-owner "\$CUID" ! -o lo -j REJECT
delete_rule iptables -m owner --uid-owner "\$CUID" -o lo -j ACCEPT
delete_rule ip6tables -m owner --uid-owner "\$CUID" ! -o lo -j REJECT
delete_rule ip6tables -m owner --uid-owner "\$CUID" -o lo -j ACCEPT
EOF
chmod 0755 "$GENERATED_DIR/libexec/iron-dome-lock-clear"

cat > "$GENERATED_DIR/libexec/iron-dome-cleanup" <<'EOF'
#!/bin/bash
set -euo pipefail
systemctl stop iron-dome-lock.service iron-transparent.service iron-ss-outline.service iron-tor.service iron-privoxy.service 2>/dev/null || true
/usr/local/libexec/iron-dome-lock-clear 2>/dev/null || true
EOF
chmod 0755 "$GENERATED_DIR/libexec/iron-dome-cleanup"

if [[ "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  cat >> "$GENERATED_DIR/libexec/iron-dome-cleanup" <<'EOF'
systemctl stop iron-cliproxy.service iron-google-forward.service google-forward 2>/dev/null || true
/usr/local/libexec/iron-hosts-clear 2>/dev/null || true
for i in 2 3 4 5 6 7 8; do
  ip addr del 127.0.0.$i/32 dev lo 2>/dev/null || true
done
EOF
fi

cat > "$GENERATED_DIR/bin/iron-dome-start" <<EOF
#!/bin/bash
set -euo pipefail

LOCK_MODE="strict"
if [[ "\${1:-}" == "--no-lock" ]]; then
  LOCK_MODE="open"
fi

probe_user_network() {
  runuser -u "$PROTECTED_USER" -- sh -lc "curl -k -s --max-time 8 https://1.1.1.1 >/dev/null 2>&1 && curl -s --max-time 8 https://example.com >/dev/null 2>&1"
}

print_status() {
  local label="\$1"
  local cmd="\$2"
  printf "%-20s " "\$label"
  if eval "\$cmd" >/dev/null 2>&1; then echo OK; else echo FAILED; fi
}

echo "[IRON DOME] reloading units"
systemctl daemon-reload
echo "[IRON DOME] stopping legacy units"
systemctl stop iron-transparent.service iron-dome-lock.service iron-ss-outline.service iron-tor.service iron-privoxy.service 2>/dev/null || true
EOF

if [[ "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  cat >> "$GENERATED_DIR/bin/iron-dome-start" <<'EOF'
systemctl stop iron-google-forward.service iron-cliproxy.service google-forward 2>/dev/null || true
EOF
fi

cat >> "$GENERATED_DIR/bin/iron-dome-start" <<'EOF'

echo "[IRON DOME] starting Tor with bridges"
systemctl restart iron-tor.service
echo -n "[IRON DOME] waiting for Tor"
for i in $(seq 1 45); do
  if curl --socks5-hostname 127.0.0.1:9050 -s --max-time 10 https://check.torproject.org/api/ip >/dev/null; then echo " OK"; break; fi
  if [[ "$i" -eq 45 ]]; then echo " FAIL"; exit 1; fi
  echo -n "."; sleep 2
done

echo "[IRON DOME] starting Outline over Tor"
systemctl restart iron-ss-outline.service
echo -n "[IRON DOME] waiting for 1080"
for i in $(seq 1 30); do
  if curl --socks5-hostname 127.0.0.1:1080 -s --max-time 10 https://api.ipify.org >/dev/null; then echo " OK"; break; fi
  if [[ "$i" -eq 30 ]]; then echo " FAIL"; exit 1; fi
  echo -n "."; sleep 2
done
EOF

if [[ "$ENABLE_LOCAL_HTTP_PROXY" == "yes" || "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  cat >> "$GENERATED_DIR/bin/iron-dome-start" <<'EOF'

echo "[IRON DOME] starting local HTTP proxy"
systemctl restart iron-privoxy.service
echo -n "[IRON DOME] waiting for 8119"
for i in $(seq 1 20); do
  if curl -x http://127.0.0.1:8119 -s --max-time 5 https://api.ipify.org >/dev/null 2>&1; then echo " OK"; break; fi
  if [[ "$i" -eq 20 ]]; then echo " FAIL"; exit 1; fi
  echo -n "."; sleep 2
done
EOF
fi

if [[ "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  cat >> "$GENERATED_DIR/bin/iron-dome-start" <<'EOF'
echo "[IRON DOME] starting integration endpoints"
systemctl restart iron-google-forward.service
if ! /usr/local/libexec/iron-unproxy-refresh; then
  echo "[IRON DOME] integration auth refresh failed, continuing with existing auth state"
fi
systemctl restart iron-cliproxy.service
echo -n "[IRON DOME] waiting for gateway models"
for i in $(seq 1 35); do
  MODELS_COUNT="$(curl --noproxy '*' -s --max-time 5 http://127.0.0.1:8317/v1/models 2>/dev/null | python3 -c 'import json,sys
try:
    print(len(json.load(sys.stdin).get("data", [])))
except Exception:
    raise SystemExit(1)')" || true
  if [[ -n "$MODELS_COUNT" && "$MODELS_COUNT" -gt 0 ]]; then echo " OK"; break; fi
  if [[ "$i" -eq 35 ]]; then echo " FAIL"; exit 1; fi
  echo -n "."; sleep 2
done
EOF
else
  cat >> "$GENERATED_DIR/bin/iron-dome-start" <<'EOF'
MODELS_COUNT="disabled"
EOF
fi

cat >> "$GENERATED_DIR/bin/iron-dome-start" <<EOF

if [[ "\$LOCK_MODE" == "strict" ]]; then
  echo "[IRON DOME] starting transparent route"
  systemctl restart iron-transparent.service
  systemctl restart iron-dome-lock.service
else
  systemctl stop iron-transparent.service 2>/dev/null || true
  systemctl stop iron-dome-lock.service 2>/dev/null || true
fi

echo
echo "=== SERVICES ==="
for s in iron-tor.service iron-ss-outline.service iron-transparent.service iron-dome-lock.service; do
  printf "%-24s %s\n" "\$s" "\$(systemctl is-active "\$s" 2>/dev/null || true)"
done
EOF

if [[ "$ENABLE_LOCAL_HTTP_PROXY" == "yes" || "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  cat >> "$GENERATED_DIR/bin/iron-dome-start" <<'EOF'
printf "%-24s %s\n" "iron-privoxy.service" "$(systemctl is-active iron-privoxy.service 2>/dev/null || true)"
EOF
fi

if [[ "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  cat >> "$GENERATED_DIR/bin/iron-dome-start" <<'EOF'
for s in iron-google-forward.service iron-cliproxy.service; do
  printf "%-24s %s\n" "$s" "$(systemctl is-active "$s" 2>/dev/null || true)"
done
EOF
fi

cat >> "$GENERATED_DIR/bin/iron-dome-start" <<'EOF'

echo
echo "=== ROUTES ==="
print_status "TOR 9050:" "curl --socks5-hostname 127.0.0.1:9050 -s --max-time 10 https://check.torproject.org/api/ip | grep -q '\"IsTor\":true'"
print_status "OUTLINE 1080:" "curl --socks5-hostname 127.0.0.1:1080 -s --max-time 10 https://api.ipify.org"
EOF

if [[ "$ENABLE_LOCAL_HTTP_PROXY" == "yes" || "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  cat >> "$GENERATED_DIR/bin/iron-dome-start" <<'EOF'
print_status "PRIVOXY 8119:" "curl -x http://127.0.0.1:8119 -s --max-time 10 https://api.ipify.org"
EOF
fi

if [[ "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  cat >> "$GENERATED_DIR/bin/iron-dome-start" <<'EOF'

echo
echo "=== LOCAL GATEWAY ==="
echo "models: ${MODELS_COUNT:-FAILED}"
EOF
fi

cat >> "$GENERATED_DIR/bin/iron-dome-start" <<EOF

echo
if [[ "\$LOCK_MODE" == "strict" ]]; then
  echo "=== USER NETWORK ($PROTECTED_USER) ==="
  printf "NETWORK:            "
  if probe_user_network; then echo OK; else echo FAILED; fi
else
  echo "=== DIRECT EGRESS ($PROTECTED_USER) ==="
  printf "DIRECT:             "
  if probe_user_network; then echo OPEN; else echo BLOCKED; fi
fi

echo
if [[ "\$LOCK_MODE" == "strict" ]]; then
  echo "[IRON DOME] strict mode active"
else
  echo "[IRON DOME] open mode active (no lock)"
fi
EOF
chmod 0755 "$GENERATED_DIR/bin/iron-dome-start"

cat > "$GENERATED_DIR/bin/iron-dome-stop" <<EOF
#!/bin/bash
set -euo pipefail

probe_user_network() {
  runuser -u "$PROTECTED_USER" -- sh -lc "curl -k -s --max-time 8 https://1.1.1.1 >/dev/null 2>&1 && curl -s --max-time 8 https://example.com >/dev/null 2>&1"
}

echo "[IRON DOME] stopping strict stack"
systemctl stop iron-dome-lock.service iron-transparent.service iron-ss-outline.service iron-tor.service iron-privoxy.service 2>/dev/null || true
EOF

if [[ "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  cat >> "$GENERATED_DIR/bin/iron-dome-stop" <<'EOF'
systemctl stop iron-cliproxy.service iron-google-forward.service google-forward 2>/dev/null || true
EOF
fi

cat >> "$GENERATED_DIR/bin/iron-dome-stop" <<EOF

echo
echo "=== SERVICES ==="
for s in iron-tor.service iron-ss-outline.service iron-transparent.service iron-dome-lock.service iron-privoxy.service; do
  printf "%-24s %s\n" "\$s" "\$(systemctl is-active "\$s" 2>/dev/null || true)"
done
EOF

if [[ "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  cat >> "$GENERATED_DIR/bin/iron-dome-stop" <<'EOF'
for s in iron-google-forward.service iron-cliproxy.service google-forward; do
  printf "%-24s %s\n" "$s" "$(systemctl is-active "$s" 2>/dev/null || true)"
done
EOF
fi

cat >> "$GENERATED_DIR/bin/iron-dome-stop" <<EOF

echo
echo "=== DIRECT INTERNET ($PROTECTED_USER) ==="
printf "DIRECT:             "
if probe_user_network; then echo OPEN; else echo FAILED; fi

echo
echo "[IRON DOME] direct internet restored"
EOF
chmod 0755 "$GENERATED_DIR/bin/iron-dome-stop"

cat > "$GENERATED_DIR/bin/iron-dome-open" <<'EOF'
#!/bin/bash
set -euo pipefail
exec /usr/local/bin/iron-dome-start --no-lock
EOF
chmod 0755 "$GENERATED_DIR/bin/iron-dome-open"

if [[ "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  mkdir -p "$GENERATED_DIR/integrations/unproxy"

  cat > "$GENERATED_DIR/integrations/unproxy/cliproxy.strict.yaml" <<EOF
host: "127.0.0.1"
port: 8317
debug: false
proxy-url: "http://127.0.0.1:8119"
auth-dir: "$CLIPROXY_AUTH_DIR"
storage-dir: "$CLIPROXY_STORAGE_DIR"
EOF

  export ROOT_DIR INSTALL_PREFIX CLIPROXY_BIN CLIPROXY_WORKDIR
  for template in "$ROOT_DIR/integrations/unproxy"/*.example; do
    name="$(basename "$template" .example)"
    render_template_file "$template" "$GENERATED_DIR/integrations/unproxy/$name"
  done

  cat > "$GENERATED_DIR/libexec/iron-hosts-apply" <<'EOF'
#!/bin/bash
set -euo pipefail
HOSTS_FILE="/etc/hosts"
TMP_FILE="$(mktemp)"
cleanup(){ rm -f "$TMP_FILE"; }
trap cleanup EXIT
python3 - <<'PY' "$HOSTS_FILE" "$TMP_FILE"
from pathlib import Path
import sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2])
remove_hosts={'cloudcode-pa.googleapis.com','daily-cloudcode-pa.googleapis.com','daily-cloudcode-pa.sandbox.googleapis.com','play.googleapis.com','oauth2.googleapis.com','accounts.google.com','www.googleapis.com'}
lines=src.read_text(encoding='utf-8',errors='replace').splitlines(); out=[]; inside=False
for line in lines:
    stripped=line.strip()
    if stripped == '# BEGIN IRON DOME GOOGLE HOSTS': inside=True; continue
    if stripped == '# END IRON DOME GOOGLE HOSTS': inside=False; continue
    if inside: continue
    parts=stripped.split()
    if len(parts)>=2 and any(host in remove_hosts for host in parts[1:]): continue
    out.append(line)
if out and out[-1] != '': out.append('')
out.extend([
  '# BEGIN IRON DOME GOOGLE HOSTS',
  '127.0.0.2 daily-cloudcode-pa.googleapis.com',
  '127.0.0.3 play.googleapis.com',
  '127.0.0.4 oauth2.googleapis.com',
  '127.0.0.5 accounts.google.com',
  '127.0.0.6 www.googleapis.com',
  '127.0.0.7 cloudcode-pa.googleapis.com',
  '127.0.0.8 daily-cloudcode-pa.sandbox.googleapis.com',
  '# END IRON DOME GOOGLE HOSTS',
])
dst.write_text('\n'.join(out) + '\n', encoding='utf-8')
PY
install -m 0644 "$TMP_FILE" "$HOSTS_FILE"
EOF
  chmod 0755 "$GENERATED_DIR/libexec/iron-hosts-apply"

  cat > "$GENERATED_DIR/libexec/iron-hosts-clear" <<'EOF'
#!/bin/bash
set -euo pipefail
HOSTS_FILE="/etc/hosts"
TMP_FILE="$(mktemp)"
cleanup(){ rm -f "$TMP_FILE"; }
trap cleanup EXIT
python3 - <<'PY' "$HOSTS_FILE" "$TMP_FILE"
from pathlib import Path
import sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2])
remove_hosts={'cloudcode-pa.googleapis.com','daily-cloudcode-pa.googleapis.com','daily-cloudcode-pa.sandbox.googleapis.com','play.googleapis.com','oauth2.googleapis.com','accounts.google.com','www.googleapis.com'}
lines=src.read_text(encoding='utf-8',errors='replace').splitlines(); out=[]; inside=False
for line in lines:
    stripped=line.strip()
    if stripped == '# BEGIN IRON DOME GOOGLE HOSTS': inside=True; continue
    if stripped == '# END IRON DOME GOOGLE HOSTS': inside=False; continue
    if inside: continue
    parts=stripped.split()
    if len(parts)>=2 and any(host in remove_hosts for host in parts[1:]): continue
    out.append(line)
dst.write_text('\n'.join(out).rstrip() + '\n', encoding='utf-8')
PY
install -m 0644 "$TMP_FILE" "$HOSTS_FILE"
EOF
  chmod 0755 "$GENERATED_DIR/libexec/iron-hosts-clear"

  cat > "$GENERATED_DIR/libexec/iron-unproxy-refresh" <<EOF
#!/bin/bash
set -euo pipefail
AUTH_DIR="$CLIPROXY_AUTH_DIR"
AUTH_FILE="\$(ls "\$AUTH_DIR"/*.json 2>/dev/null | head -n 1 || true)"
if [[ -z "\$AUTH_FILE" || ! -f "\$AUTH_FILE" ]]; then
  echo "[IRON DOME] integration auth file not found, skipping refresh"
  exit 0
fi
AUTH_FILE="\$AUTH_FILE" python3 - <<'PY'
import json, subprocess, urllib.parse, time, os
from pathlib import Path
auth_file = Path(os.environ['AUTH_FILE'])
meta = json.loads(auth_file.read_text())
refresh = str(meta.get('refresh_token', '')).strip()
if not refresh:
    raise SystemExit(1)
body = urllib.parse.urlencode({
    'client_id': '1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com',
    'client_secret': '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',
    'grant_type': 'refresh_token',
    'refresh_token': refresh,
})
resp_file = Path('/tmp/unproxy_refresh.json')
cmd = ['curl','--proxy','http://127.0.0.1:8119','-sS','--max-time','30','-o',str(resp_file),'-w','%{http_code}','-X','POST','https://oauth2.googleapis.com/token','-H','Content-Type: application/x-www-form-urlencoded','-d',body]
r = subprocess.run(cmd, capture_output=True, text=True)
if r.returncode != 0 or r.stdout.strip() != '200':
    raise SystemExit(1)
resp = json.loads(resp_file.read_text())
meta['access_token'] = resp['access_token']
if resp.get('refresh_token'):
    meta['refresh_token'] = resp['refresh_token']
meta['expires_in'] = int(resp.get('expires_in', 3599))
meta['timestamp'] = int(time.time()*1000)
meta['expired'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time()+meta['expires_in']))
auth_file.write_text(json.dumps(meta, ensure_ascii=False, indent=2)+'\n')
PY
EOF
  chmod 0755 "$GENERATED_DIR/libexec/iron-unproxy-refresh"
fi

cat > "$GENERATED_DIR/summary.txt" <<EOF
Iron Dome rendered configuration

Protected user:        $PROTECTED_USER
Install prefix:        $INSTALL_PREFIX
Integration profile:   $INTEGRATION_PROFILE
Local HTTP proxy:      $ENABLE_LOCAL_HTTP_PROXY
Strict mode:           $ENABLE_STRICT
Open mode:             $ENABLE_OPEN
Google forward:        $ENABLE_GOOGLE_FORWARD
Boot cleanup:          $ENABLE_BOOT_CLEANUP
Root web traffic:      $INCLUDE_ROOT_WEB
Transparent MTU:       $TRANSPARENT_MTU

Gateway binary:        $CLIPROXY_BIN
Gateway workdir:       $CLIPROXY_WORKDIR
Gateway auth dir:      $CLIPROXY_AUTH_DIR
Gateway storage dir:   $CLIPROXY_STORAGE_DIR

Generated files:
- $GENERATED_DIR/config/torrc.strict
- $GENERATED_DIR/config/outline.json
- $GENERATED_DIR/bin/iron-dome-start
- $GENERATED_DIR/bin/iron-dome-stop
- $GENERATED_DIR/bin/iron-dome-open
- $GENERATED_DIR/libexec/iron-transparent-generate
- $GENERATED_DIR/libexec/iron-dome-lock-apply
- $GENERATED_DIR/libexec/iron-dome-lock-clear
- $GENERATED_DIR/libexec/iron-dome-cleanup
- $GENERATED_DIR/systemd/*.service
EOF

if [[ -f "$GENERATED_DIR/config/privoxy.conf" ]]; then
  cat >> "$GENERATED_DIR/summary.txt" <<EOF
- $GENERATED_DIR/config/privoxy.conf
EOF
fi

if [[ "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  cat >> "$GENERATED_DIR/summary.txt" <<EOF
- $GENERATED_DIR/integrations/unproxy/cliproxy.strict.yaml
- $GENERATED_DIR/integrations/unproxy/*.service
- $GENERATED_DIR/libexec/iron-hosts-apply
- $GENERATED_DIR/libexec/iron-hosts-clear
- $GENERATED_DIR/libexec/iron-unproxy-refresh
EOF
fi

echo "Rendered files written to: $GENERATED_DIR"
echo "Summary: $GENERATED_DIR/summary.txt"
