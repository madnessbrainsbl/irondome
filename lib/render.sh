#!/bin/bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$LIB_DIR/common.sh"

load_config
ensure_dirs

if [[ "$WINDOWS_PROXY_ENABLED" == "yes" && "$ENABLE_LOCAL_HTTP_PROXY" != "yes" && "$INTEGRATION_PROFILE" != "unproxy" ]]; then
  echo "Windows/host proxy requires the local HTTP proxy layer. Enable ENABLE_LOCAL_HTTP_PROXY or use the unproxy profile." >&2
  exit 1
fi

require_state_file "$BRIDGES_FILE" "Bridges are missing. Run: irondome setup (or just: irondome bridges)"
require_state_file "$OUTLINE_KEY_FILE" "Outline key is missing. Run: irondome setup (or just: irondome outline 'ss://...')"

rm -rf "$GENERATED_DIR"
mkdir -p "$GENERATED_DIR/systemd" "$GENERATED_DIR/bin" "$GENERATED_DIR/libexec" "$GENERATED_DIR/config" "$GENERATED_DIR/etc/sudoers.d"

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
BYPASS_GROUP="\${IRON_ANTIGRAVITY_BYPASS_GROUP:-antigravity-direct}"
BYPASS_ENABLED="\${IRON_ANTIGRAVITY_STRICT_BYPASS:-no}"
BYPASS_GID="\$(getent group "\$BYPASS_GROUP" | cut -d: -f3 || true)"
WINDOWS_PROXY_ENABLED="$WINDOWS_PROXY_ENABLED"
WINDOWS_PROXY_BIND="${WINDOWS_PROXY_BIND}"
WINDOWS_PROXY_PORT="${WINDOWS_PROXY_PORT}"
WINDOWS_PROXY_NET="${WINDOWS_PROXY_NET}"
WINDOWS_PROXY_PRIORITY="999"
OUTLINE_HOST="\$(python3 - <<'PY'
import json
from pathlib import Path
cfg=json.loads(Path('$INSTALL_PREFIX/config/outline.json').read_text())
print(cfg['server'])
PY
)"
resolve_outline_ip() {
  python3 - "\$OUTLINE_HOST" <<'PY'
import ipaddress
import socket
import sys

host = sys.argv[1].strip()
try:
    ipaddress.ip_address(host)
    print(host)
    raise SystemExit(0)
except ValueError:
    pass

seen = []
for info in socket.getaddrinfo(host, None, socket.AF_INET, socket.SOCK_STREAM):
    ip = info[4][0]
    if ip not in seen:
        seen.append(ip)
if not seen:
    raise SystemExit(1)
print(seen[0])
PY
}
OUTLINE_IP="\$(resolve_outline_ip || true)"
OUTLINE_PORT="\$(python3 - <<'PY'
import json
from pathlib import Path
cfg=json.loads(Path('$INSTALL_PREFIX/config/outline.json').read_text())
print(cfg['server_port'])
PY
)"
if [[ -z "\$OUTLINE_IP" ]]; then
  echo "Failed to resolve Outline host: \$OUTLINE_HOST" >&2
  exit 1
fi
TRANSPARENT_MARK_A="0x2023/0xffffffff"
TRANSPARENT_MARK_B="0x2024/0xffffffff"
INCLUDE_ROOT_WEB="$INCLUDE_ROOT_WEB"
ROUTE_TABLE="2022"
BYPASS_PRIORITY="900"
USER_ROUTE_PRIORITY="1000"
ROOT_ROUTE_PRIORITY="1001"
DIRECT_IFACE="\$(ip -4 route show default | awk '{for (i=1; i<=NF; i++) if (\$i==\"dev\") {print \$(i+1); exit}}')"

delete_rule() {
  local tool="\$1"; shift
  while "\$tool" -C OUTPUT "\$@" 2>/dev/null; do "\$tool" -D OUTPUT "\$@"; done
}

delete_mangle_rule() {
  local tool="\$1"; shift
  while "\$tool" -t mangle -C OUTPUT "\$@" 2>/dev/null; do "\$tool" -t mangle -D OUTPUT "\$@"; done
}

delete_ip_rule() {
  while ip -4 rule del "\$@" 2>/dev/null; do true; done
}

insert_uid_routes() {
  # Policy routing closes forced-interface and unmarked OUTPUT bypasses.
  # The bypass mark stays earlier so sing-box can avoid routing loops.
  delete_ip_rule priority "\$WINDOWS_PROXY_PRIORITY" to "\$WINDOWS_PROXY_NET" lookup main
  delete_ip_rule priority "\$BYPASS_PRIORITY" fwmark 0x2024 goto 9002
  delete_ip_rule priority "\$USER_ROUTE_PRIORITY" uidrange "\$KUID-\$KUID" lookup "\$ROUTE_TABLE"
  if [[ "\$INCLUDE_ROOT_WEB" == "yes" ]]; then
    delete_ip_rule priority "\$ROOT_ROUTE_PRIORITY" uidrange 0-0 lookup "\$ROUTE_TABLE"
  fi
  if [[ "\$WINDOWS_PROXY_ENABLED" == "yes" ]]; then
    # Allow replies from the host-OS proxy listener to return through the VM/LAN interface.
    # The filter rules below still only permit traffic from the configured proxy port.
    ip -4 rule add priority "\$WINDOWS_PROXY_PRIORITY" to "\$WINDOWS_PROXY_NET" lookup main
  fi
  ip -4 rule add priority "\$BYPASS_PRIORITY" fwmark 0x2024 goto 9002
  ip -4 rule add priority "\$USER_ROUTE_PRIORITY" uidrange "\$KUID-\$KUID" lookup "\$ROUTE_TABLE"
  if [[ "\$INCLUDE_ROOT_WEB" == "yes" ]]; then
    ip -4 rule add priority "\$ROOT_ROUTE_PRIORITY" uidrange 0-0 lookup "\$ROUTE_TABLE"
  fi
}

delete_antigravity_bypass() {
  [[ -n "\$BYPASS_GID" ]] || return 0
  delete_mangle_rule iptables -m owner --gid-owner "\$BYPASS_GID" ! -o lo -j MARK --set-xmark "\$TRANSPARENT_MARK_B"
  delete_mangle_rule iptables -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
  delete_rule iptables -m owner --gid-owner "\$BYPASS_GID" -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
}

insert_antigravity_bypass() {
  delete_antigravity_bypass
  [[ "\$BYPASS_ENABLED" == "yes" && -n "\$BYPASS_GID" ]] || return 0
  iptables -t mangle -I OUTPUT 1 -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
  iptables -t mangle -I OUTPUT 1 -m owner --gid-owner "\$BYPASS_GID" ! -o lo -j MARK --set-xmark "\$TRANSPARENT_MARK_B"
  iptables -I OUTPUT 1 -m owner --gid-owner "\$BYPASS_GID" -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
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
  if [[ "\$WINDOWS_PROXY_ENABLED" == "yes" && ( "\$uid" == "\$KUID" || "\$uid" == "0" ) ]]; then
    delete_rule iptables -m owner --uid-owner "\$uid" -p tcp --sport "\$WINDOWS_PROXY_PORT" -d "\$WINDOWS_PROXY_NET" -j ACCEPT
  fi
  delete_mangle_rule iptables -m owner --uid-owner "\$uid" ! -o lo -j MARK --set-xmark "\$TRANSPARENT_MARK_A"
  if [[ -n "\$DIRECT_IFACE" ]]; then
    delete_rule iptables -m owner --uid-owner "\$uid" -o "\$DIRECT_IFACE" -m mark --mark "\$TRANSPARENT_MARK_A" -j REJECT
  fi
  delete_rule iptables -m owner --uid-owner "\$uid" -o iron0 -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
  delete_rule iptables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
  delete_rule iptables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
  delete_rule iptables -m owner --uid-owner "\$uid" ! -o lo -j REJECT
  delete_rule iptables -m owner --uid-owner "\$uid" -o lo -j ACCEPT
  iptables -t mangle -I OUTPUT 1 -m owner --uid-owner "\$uid" ! -o lo -j MARK --set-xmark "\$TRANSPARENT_MARK_A"
  iptables -I OUTPUT 1 -m owner --uid-owner "\$uid" ! -o lo -j REJECT
  iptables -I OUTPUT 1 -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
  if [[ -n "\$DIRECT_IFACE" ]]; then
    iptables -I OUTPUT 1 -m owner --uid-owner "\$uid" -o "\$DIRECT_IFACE" -m mark --mark "\$TRANSPARENT_MARK_A" -j REJECT
  fi
  if [[ "\$WINDOWS_PROXY_ENABLED" == "yes" && ( "\$uid" == "\$KUID" || "\$uid" == "0" ) ]]; then
    iptables -I OUTPUT 1 -m owner --uid-owner "\$uid" -p tcp --sport "\$WINDOWS_PROXY_PORT" -d "\$WINDOWS_PROXY_NET" -j ACCEPT
  fi
  iptables -I OUTPUT 1 -m owner --uid-owner "\$uid" -o lo -j ACCEPT
}

insert_user_ipv6() {
  local uid="\$1"
  delete_mangle_rule ip6tables -m owner --uid-owner "\$uid" ! -o lo -j MARK --set-xmark "\$TRANSPARENT_MARK_A"
  if [[ -n "\$DIRECT_IFACE" ]]; then
    delete_rule ip6tables -m owner --uid-owner "\$uid" -o "\$DIRECT_IFACE" -m mark --mark "\$TRANSPARENT_MARK_A" -j REJECT
  fi
  delete_rule ip6tables -m owner --uid-owner "\$uid" -o iron0 -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
  delete_rule ip6tables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
  delete_rule ip6tables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
  delete_rule ip6tables -m owner --uid-owner "\$uid" ! -o lo -j REJECT
  delete_rule ip6tables -m owner --uid-owner "\$uid" -o lo -j ACCEPT
  ip6tables -t mangle -I OUTPUT 1 -m owner --uid-owner "\$uid" ! -o lo -j MARK --set-xmark "\$TRANSPARENT_MARK_A"
  ip6tables -I OUTPUT 1 -m owner --uid-owner "\$uid" ! -o lo -j REJECT
  ip6tables -I OUTPUT 1 -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
  if [[ -n "\$DIRECT_IFACE" ]]; then
    ip6tables -I OUTPUT 1 -m owner --uid-owner "\$uid" -o "\$DIRECT_IFACE" -m mark --mark "\$TRANSPARENT_MARK_A" -j REJECT
  fi
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
insert_antigravity_bypass
insert_uid_routes
EOF
chmod 0755 "$GENERATED_DIR/libexec/iron-dome-lock-apply"

cat > "$GENERATED_DIR/libexec/iron-dome-lock-clear" <<EOF
#!/bin/bash
set -euo pipefail

KUID="\$(id -u $PROTECTED_USER)"
CUID="\$(id -u cliproxysvc)"
PUID="\$(id -u privoxy)"
BYPASS_GROUP="\${IRON_ANTIGRAVITY_BYPASS_GROUP:-antigravity-direct}"
BYPASS_GID="\$(getent group "\$BYPASS_GROUP" | cut -d: -f3 || true)"
WINDOWS_PROXY_ENABLED="$WINDOWS_PROXY_ENABLED"
WINDOWS_PROXY_PORT="${WINDOWS_PROXY_PORT}"
WINDOWS_PROXY_NET="${WINDOWS_PROXY_NET}"
WINDOWS_PROXY_PRIORITY="999"
OUTLINE_HOST="\$(python3 - <<'PY'
import json
from pathlib import Path
cfg=json.loads(Path('$INSTALL_PREFIX/config/outline.json').read_text())
print(cfg['server'])
PY
)"
resolve_outline_ip() {
  python3 - "\$OUTLINE_HOST" <<'PY'
import ipaddress
import socket
import sys

host = sys.argv[1].strip()
try:
    ipaddress.ip_address(host)
    print(host)
    raise SystemExit(0)
except ValueError:
    pass

seen = []
for info in socket.getaddrinfo(host, None, socket.AF_INET, socket.SOCK_STREAM):
    ip = info[4][0]
    if ip not in seen:
        seen.append(ip)
if not seen:
    raise SystemExit(1)
print(seen[0])
PY
}
OUTLINE_IP="\$(resolve_outline_ip || true)"
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
ROUTE_TABLE="2022"
BYPASS_PRIORITY="900"
USER_ROUTE_PRIORITY="1000"
ROOT_ROUTE_PRIORITY="1001"
DIRECT_IFACE="\$(ip -4 route show default | awk '{for (i=1; i<=NF; i++) if (\$i==\"dev\") {print \$(i+1); exit}}')"

delete_rule() {
  local tool="\$1"; shift
  while "\$tool" -C OUTPUT "\$@" 2>/dev/null; do "\$tool" -D OUTPUT "\$@"; done
}

delete_mangle_rule() {
  local tool="\$1"; shift
  while "\$tool" -t mangle -C OUTPUT "\$@" 2>/dev/null; do "\$tool" -t mangle -D OUTPUT "\$@"; done
}

delete_ip_rule() {
  while ip -4 rule del "\$@" 2>/dev/null; do true; done
}

delete_uid_routes() {
  delete_ip_rule priority "\$WINDOWS_PROXY_PRIORITY" to "\$WINDOWS_PROXY_NET" lookup main
  delete_ip_rule priority "\$BYPASS_PRIORITY" fwmark 0x2024 goto 9002
  delete_ip_rule priority "\$USER_ROUTE_PRIORITY" uidrange "\$KUID-\$KUID" lookup "\$ROUTE_TABLE"
  delete_ip_rule priority "\$ROOT_ROUTE_PRIORITY" uidrange 0-0 lookup "\$ROUTE_TABLE"
}

delete_uid_routes

if [[ -n "\$BYPASS_GID" ]]; then
  delete_mangle_rule iptables -m owner --gid-owner "\$BYPASS_GID" ! -o lo -j MARK --set-xmark "\$TRANSPARENT_MARK_B"
  delete_mangle_rule iptables -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
  delete_rule iptables -m owner --gid-owner "\$BYPASS_GID" -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
fi

for tool in iptables ip6tables; do
  delete_rule "\$tool" -m owner --uid-owner "\$PUID" ! -o lo -j REJECT
  delete_rule "\$tool" -m owner --uid-owner "\$PUID" -o lo -j ACCEPT
done

for uid in "\$KUID"; do
  delete_mangle_rule iptables -m owner --uid-owner "\$uid" ! -o lo -j MARK --set-xmark "\$TRANSPARENT_MARK_A"
  if [[ "\$WINDOWS_PROXY_ENABLED" == "yes" ]]; then
    delete_rule iptables -m owner --uid-owner "\$uid" -p tcp --sport "\$WINDOWS_PROXY_PORT" -d "\$WINDOWS_PROXY_NET" -j ACCEPT
  fi
  if [[ -n "\$DIRECT_IFACE" ]]; then
    delete_rule iptables -m owner --uid-owner "\$uid" -o "\$DIRECT_IFACE" -m mark --mark "\$TRANSPARENT_MARK_A" -j REJECT
  fi
  delete_rule iptables -m owner --uid-owner "\$uid" -o iron0 -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
  delete_rule iptables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
  delete_rule iptables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
  delete_rule iptables -m owner --uid-owner "\$uid" ! -o lo -j REJECT
  delete_rule iptables -m owner --uid-owner "\$uid" -o lo -j ACCEPT
  delete_mangle_rule ip6tables -m owner --uid-owner "\$uid" ! -o lo -j MARK --set-xmark "\$TRANSPARENT_MARK_A"
  if [[ -n "\$DIRECT_IFACE" ]]; then
    delete_rule ip6tables -m owner --uid-owner "\$uid" -o "\$DIRECT_IFACE" -m mark --mark "\$TRANSPARENT_MARK_A" -j REJECT
  fi
  delete_rule ip6tables -m owner --uid-owner "\$uid" -o iron0 -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
  delete_rule ip6tables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
  delete_rule ip6tables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
  delete_rule ip6tables -m owner --uid-owner "\$uid" ! -o lo -j REJECT
  delete_rule ip6tables -m owner --uid-owner "\$uid" -o lo -j ACCEPT
done

if [[ "\$INCLUDE_ROOT_WEB" == "yes" ]]; then
  for uid in 0; do
    delete_mangle_rule iptables -m owner --uid-owner "\$uid" ! -o lo -j MARK --set-xmark "\$TRANSPARENT_MARK_A"
    if [[ "\$WINDOWS_PROXY_ENABLED" == "yes" ]]; then
      delete_rule iptables -m owner --uid-owner "\$uid" -p tcp --sport "\$WINDOWS_PROXY_PORT" -d "\$WINDOWS_PROXY_NET" -j ACCEPT
    fi
    if [[ -n "\$DIRECT_IFACE" ]]; then
      delete_rule iptables -m owner --uid-owner "\$uid" -o "\$DIRECT_IFACE" -m mark --mark "\$TRANSPARENT_MARK_A" -j REJECT
    fi
    delete_rule iptables -m owner --uid-owner "\$uid" -o iron0 -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
    delete_rule iptables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
    delete_rule iptables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
    delete_rule iptables -m owner --uid-owner "\$uid" ! -o lo -j REJECT
    delete_rule iptables -m owner --uid-owner "\$uid" -o lo -j ACCEPT
    delete_mangle_rule ip6tables -m owner --uid-owner "\$uid" ! -o lo -j MARK --set-xmark "\$TRANSPARENT_MARK_A"
    if [[ -n "\$DIRECT_IFACE" ]]; then
      delete_rule ip6tables -m owner --uid-owner "\$uid" -o "\$DIRECT_IFACE" -m mark --mark "\$TRANSPARENT_MARK_A" -j REJECT
    fi
    delete_rule ip6tables -m owner --uid-owner "\$uid" -o iron0 -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
    delete_rule ip6tables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_A" -j ACCEPT
    delete_rule ip6tables -m owner --uid-owner "\$uid" -m mark --mark "\$TRANSPARENT_MARK_B" -j ACCEPT
    delete_rule ip6tables -m owner --uid-owner "\$uid" ! -o lo -j REJECT
    delete_rule ip6tables -m owner --uid-owner "\$uid" -o lo -j ACCEPT
  done
fi

if [[ -n "\$OUTLINE_IP" ]]; then
  delete_rule iptables -m owner --uid-owner "\$CUID" -d "\$OUTLINE_IP" -p tcp --dport "\$OUTLINE_PORT" -j ACCEPT
fi
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

cat > "$GENERATED_DIR/libexec/iron-ss-outline-start" <<EOF
#!/bin/bash
set -euo pipefail

SOURCE_CONFIG="$INSTALL_PREFIX/config/outline.json"
RESOLVED_CONFIG="/tmp/iron-outline-resolved-\$(id -u).json"

umask 077

python3 - "\$SOURCE_CONFIG" "\$RESOLVED_CONFIG" <<'PY'
import ipaddress
import json
import socket
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
cfg = json.loads(src.read_text())
host = str(cfg.get("server", "")).strip()

try:
    ipaddress.ip_address(host)
except ValueError:
    try:
        infos = socket.getaddrinfo(host, None, socket.AF_INET, socket.SOCK_STREAM)
        cfg["server"] = infos[0][4][0]
    except socket.gaierror:
        pass

dst.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\\n")
PY

exec /usr/bin/torsocks /usr/bin/ss-local -c "\$RESOLVED_CONFIG"
EOF
chmod 0755 "$GENERATED_DIR/libexec/iron-ss-outline-start"

if [[ "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  cat >> "$GENERATED_DIR/libexec/iron-dome-cleanup" <<'EOF'
systemctl stop iron-cliproxy.service iron-google-forward.service google-forward 2>/dev/null || true
/usr/local/libexec/iron-hosts-clear 2>/dev/null || true
for i in 2 3 4 5 6 7 8; do
  ip addr del 127.0.0.$i/32 dev lo 2>/dev/null || true
done
EOF
fi

cat > "$GENERATED_DIR/etc/sudoers.d/iron-dome" <<EOF
Defaults secure_path=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$PROTECTED_USER ALL=(root) NOPASSWD: /usr/local/bin/iron-dome-start
$PROTECTED_USER ALL=(root) NOPASSWD: /usr/local/bin/iron-dome-stop
$PROTECTED_USER ALL=(root) NOPASSWD: /usr/local/bin/tor-bridges
$PROTECTED_USER ALL=(root) NOPASSWD: /usr/local/bin/ss-key
EOF
chmod 0440 "$GENERATED_DIR/etc/sudoers.d/iron-dome"

cat > "$GENERATED_DIR/bin/iron-dome-start" <<EOF
#!/bin/bash
set -euo pipefail

LOCK_MODE="strict"
CHECK_USER="$PROTECTED_USER"
CHECK_UID="\$(id -u "\$CHECK_USER")"
if [[ "\${1:-}" == "--no-lock" ]]; then
  LOCK_MODE="open"
fi

probe_direct_network() {
  runuser -u "\$CHECK_USER" -- sh -lc 'curl -k -s --connect-timeout 10 --max-time 20 https://1.1.1.1 >/dev/null 2>&1'
}

probe_strict_user_network() {
  runuser -u "\$CHECK_USER" -- sh -lc '
    direct_if="\$(ip -4 route show default | awk '\''{for (i=1; i<=NF; i++) if (\$i=="dev") {print \$(i+1); exit}}'\'')"
    ip route get 1.1.1.1 uid '"\$CHECK_UID"' 2>/dev/null | grep -q "dev iron0" &&
    curl -k -s --connect-timeout 10 --max-time 20 https://1.1.1.1 >/dev/null 2>&1 &&
    { [ -z "\$direct_if" ] || ! curl -s --interface "\$direct_if" --connect-timeout 2 --max-time 3 https://ifconfig.me >/dev/null 2>&1; }
  '
}

print_status() {
  local label="\$1"
  local cmd="\$2"
  printf "%-20s " "\$label"
  if eval "\$cmd" >/dev/null 2>&1 || { sleep 3; eval "\$cmd" >/dev/null 2>&1; }; then echo OK; else echo FAILED; fi
}

wait_systemd_jobs() {
  local label="\$1"
  echo -n "[IRON DOME] waiting for \$label"
  for i in \$(seq 1 45); do
    if [ -z "\$(systemctl list-jobs --no-legend 2>/dev/null)" ]; then echo " OK"; return 0; fi
    echo -n "."; sleep 1
  done
  echo " WARN"
  systemctl list-jobs --no-pager || true
}

echo "[IRON DOME] reloading units"
systemctl daemon-reload
wait_systemd_jobs "pending jobs"
echo "[IRON DOME] stopping legacy units"
systemctl stop iron-transparent.service iron-dome-lock.service iron-ss-outline.service iron-tor.service iron-privoxy.service 2>/dev/null || true
wait_systemd_jobs "legacy stops"
EOF

if [[ "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  cat >> "$GENERATED_DIR/bin/iron-dome-start" <<'EOF'
systemctl stop iron-google-forward.service iron-cliproxy.service google-forward 2>/dev/null || true

ANTIGRAVITY_PROXY_ENV="/home/$CHECK_USER/.config/iron-dome/antigravity-proxy.env"

antigravity_direct_mode() {
  [ -f "$ANTIGRAVITY_PROXY_ENV" ] \
    && grep -Eq '^[[:space:]]*IRON_ANTIGRAVITY_PROXY=[[:space:]]*$' "$ANTIGRAVITY_PROXY_ENV" \
    && grep -Eq '^[[:space:]]*IRON_ANTIGRAVITY_EXPORT_PROXY_ENV=no[[:space:]]*$' "$ANTIGRAVITY_PROXY_ENV"
}

clear_google_hosts() {
  if [ -x /usr/local/libexec/iron-hosts-clear ]; then
    /usr/local/libexec/iron-hosts-clear
  fi
}
EOF
fi

cat >> "$GENERATED_DIR/bin/iron-dome-start" <<'EOF'

# The lock goes on before the chain comes up, not after. Every wait below can
# fail вЂ” dead bridges, dead Outline key, a service that will not start вЂ” and
# without this the protected user would sit on a direct route while we retry,
# and stay there after a failed start. Table 2022 is empty until sing-box fills
# it, so locking early means "no route", not "wrong route".
fail_closed() {
  echo " FAIL"
  echo "[IRON DOME] $1" >&2
  if [[ "$LOCK_MODE" == "strict" ]]; then
    echo "[IRON DOME] the lock stays applied: protected traffic is blocked, not leaking." >&2
    echo "[IRON DOME] run 'sudo iron-dome-stop' to restore normal networking." >&2
  fi
  exit 1
}

if [[ "$LOCK_MODE" == "strict" ]]; then
  echo "[IRON DOME] applying lock before starting the chain"
  systemctl restart iron-dome-lock.service
fi

echo "[IRON DOME] starting Tor with bridges"
systemctl restart iron-tor.service
echo -n "[IRON DOME] waiting for Tor"
for i in $(seq 1 90); do
  if curl --socks5-hostname 127.0.0.1:9050 -s --max-time 10 https://check.torproject.org/api/ip >/dev/null; then echo " OK"; break; fi
  if [[ "$i" -eq 90 ]]; then fail_closed "Tor did not bootstrap; check your bridges with: sudo tor-bridges"; fi
  echo -n "."; sleep 2
done

echo "[IRON DOME] starting Outline over Tor"
systemctl restart iron-ss-outline.service
echo -n "[IRON DOME] waiting for 1080"
for i in $(seq 1 30); do
  if curl --socks5-hostname 127.0.0.1:1080 -s --max-time 10 https://api.ipify.org >/dev/null; then echo " OK"; break; fi
  if [[ "$i" -eq 30 ]]; then fail_closed "no egress on 1080; the Outline key is probably dead: sudo ss-key <ss://key>"; fi
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
  if [[ "$i" -eq 20 ]]; then fail_closed "privoxy is not answering on 8119"; fi
  echo -n "."; sleep 2
done
EOF
fi

if [[ "$WINDOWS_PROXY_ENABLED" == "yes" ]]; then
  cat >> "$GENERATED_DIR/bin/iron-dome-start" <<'EOF'

echo "[IRON DOME] starting Windows host proxy"
if command -v iron-windows-proxy >/dev/null 2>&1; then
  iron-windows-proxy start || true
else
  "$(dirname "$0")/iron-windows-proxy" start || true
fi
EOF
fi

cat >> "$GENERATED_DIR/bin/iron-dome-start" <<EOF

wait_strict_ready() {
  echo -n "[IRON DOME] waiting for strict route"
  for i in \$(seq 1 8); do
    if ip route get 1.1.1.1 uid "\$CHECK_UID" 2>/dev/null | grep -q 'dev iron0' \
      && curl --socks5-hostname 127.0.0.1:1080 -s --connect-timeout 3 --max-time 8 https://api.ipify.org >/dev/null 2>&1 \
      && curl -x http://127.0.0.1:8119 -s --connect-timeout 3 --max-time 8 https://api.ipify.org >/dev/null 2>&1; then
      echo " OK"; return 0
    fi
    echo -n "."; sleep 2
  done
  echo " WARN"
  echo "[IRON DOME] strict diagnostics:"
  ip -4 rule show || true
  ip route get 1.1.1.1 uid "\$CHECK_UID" || true
  systemctl is-active iron-ss-outline.service iron-privoxy.service iron-transparent.service iron-dome-lock.service || true
  return 1
}
EOF

cat >> "$GENERATED_DIR/bin/iron-dome-start" <<EOF

if [[ "\$LOCK_MODE" == "strict" ]]; then
  echo "[IRON DOME] starting transparent route"
  systemctl restart iron-transparent.service
  systemctl restart iron-dome-lock.service
  wait_strict_ready || true
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

if [[ "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  cat >> "$GENERATED_DIR/bin/iron-dome-start" <<'EOF'
echo "[IRON DOME] starting integration endpoints"
if antigravity_direct_mode; then
  echo "[IRON DOME] Antigravity direct mode; stopping Google forwarder"
  systemctl stop iron-google-forward.service 2>/dev/null || true
  systemctl disable iron-google-forward.service 2>/dev/null || true
  if ! clear_google_hosts; then
    echo "[IRON DOME] warning: failed to clear Google hosts redirect"
  fi
else
  systemctl restart iron-google-forward.service
fi
if ! /usr/local/libexec/iron-unproxy-refresh; then
  echo "[IRON DOME] integration auth refresh failed, continuing with existing auth state"
fi
systemctl restart iron-cliproxy.service
MODELS_COUNT="failed"
for attempt in 1 2; do
  if [[ "$attempt" -gt 1 ]]; then
    echo "[IRON DOME] restarting gateway after empty model registry"
    systemctl restart iron-cliproxy.service
  fi
  echo -n "[IRON DOME] waiting for gateway models"
  for i in $(seq 1 35); do
    MODELS_COUNT="$(curl --noproxy '*' -s --max-time 5 http://127.0.0.1:8317/v1/models 2>/dev/null | python3 -c 'import json,sys
try:
    print(len(json.load(sys.stdin).get("data", [])))
except Exception:
    raise SystemExit(1)')" || true
    if [[ -n "$MODELS_COUNT" && "$MODELS_COUNT" -gt 0 ]]; then echo " OK"; break 2; fi
    echo -n "."; sleep 2
  done
  echo " FAIL"
done
if [[ -z "$MODELS_COUNT" || "$MODELS_COUNT" == "failed" ]]; then
  MODELS_COUNT="failed"
  echo "[IRON DOME] WARNING: gateway models are not ready (shield stays active)"
fi
EOF
else
  cat >> "$GENERATED_DIR/bin/iron-dome-start" <<'EOF'
MODELS_COUNT="disabled"
EOF
fi

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
  echo "=== USER NETWORK (\$CHECK_USER) ==="
  printf "NETWORK:            "
  if probe_strict_user_network || probe_strict_user_network; then echo OK; else echo FAILED; fi
else
  echo "=== DIRECT EGRESS ($PROTECTED_USER) ==="
  printf "DIRECT:             "
  if probe_direct_network; then echo OPEN; else echo BLOCKED; fi
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
  runuser -u "$PROTECTED_USER" -- sh -lc 'curl -k -s --connect-timeout 10 --max-time 20 https://1.1.1.1 >/dev/null 2>&1'
}

echo "[IRON DOME] stopping strict stack"
systemctl stop iron-dome-lock.service iron-transparent.service iron-ss-outline.service iron-tor.service iron-privoxy.service 2>/dev/null || true
if command -v iron-windows-proxy >/dev/null 2>&1; then
  iron-windows-proxy stop || true
elif [[ -x "\$(dirname "\$0")/iron-windows-proxy" ]]; then
  "\$(dirname "\$0")/iron-windows-proxy" stop || true
fi
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

cat > "$GENERATED_DIR/bin/iron-windows-proxy" <<EOF
#!/bin/bash
set -euo pipefail

LISTEN_BIND="\${IRON_WINDOWS_PROXY_BIND:-$WINDOWS_PROXY_BIND}"
LISTEN_PORT="\${IRON_WINDOWS_PROXY_PORT:-$WINDOWS_PROXY_PORT}"
UPSTREAM_HOST="\${IRON_WINDOWS_PROXY_UPSTREAM_HOST:-127.0.0.1}"
UPSTREAM_PORT="\${IRON_WINDOWS_PROXY_UPSTREAM_PORT:-8119}"
LOG_FILE="\${IRON_WINDOWS_PROXY_LOG:-/tmp/iron-windows-proxy.log}"
ACTION="\${1:-start}"
# range= keeps this from being an open proxy into the Tor -> Outline chain:
# without it any host that can reach the listener can use the tunnel.
CLIENT_NET="\${IRON_WINDOWS_PROXY_NET:-$WINDOWS_PROXY_NET}"
LISTEN_SPEC="TCP-LISTEN:\${LISTEN_PORT},bind=\${LISTEN_BIND},reuseaddr,fork,range=\${CLIENT_NET}"
PATTERN="socat \${LISTEN_SPEC} TCP:\${UPSTREAM_HOST}:\${UPSTREAM_PORT}"

case "\$ACTION" in
  start)
    if pgrep -f "\$PATTERN" >/dev/null 2>&1; then
      echo "Windows host proxy already listening on \${LISTEN_BIND}:\${LISTEN_PORT}"
      exit 0
    fi
    mkdir -p "\$(dirname "\$LOG_FILE")"
    nohup socat "\$LISTEN_SPEC" "TCP:\${UPSTREAM_HOST}:\${UPSTREAM_PORT}" >"\$LOG_FILE" 2>&1 &
    echo "Windows host proxy: \${LISTEN_BIND}:\${LISTEN_PORT} -> \${UPSTREAM_HOST}:\${UPSTREAM_PORT} (clients: \${CLIENT_NET})"
    ;;
  stop)
    pkill -f "\$PATTERN" 2>/dev/null || true
    ;;
  status)
    ss -ltn "sport = :\${LISTEN_PORT}" || true
    ;;
  *)
    echo "Usage: iron-windows-proxy [start|stop|status]" >&2
    exit 2
    ;;
esac
EOF
chmod 0755 "$GENERATED_DIR/bin/iron-windows-proxy"

# sed, not python3: on Git Bash the python binary is a native Windows program,
# so MSYS rewrites target paths like /opt/irondome/... into C:/Program Files/Git/opt/...
sed "s|__OUTLINE_CONFIG__|$INSTALL_PREFIX/config/outline.json|g" \
  "$ROOT_DIR/scripts/ss-key.example.sh" > "$GENERATED_DIR/bin/ss-key"
chmod 0755 "$GENERATED_DIR/bin/ss-key"

sed -e "s|__TORRC__|$INSTALL_PREFIX/config/torrc.strict|g" \
    -e "s|__STATE_BRIDGES__|$BRIDGES_FILE|g" \
  "$ROOT_DIR/scripts/tor-bridges.example.sh" > "$GENERATED_DIR/bin/tor-bridges"
chmod 0755 "$GENERATED_DIR/bin/tor-bridges"

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
cp "$TMP_FILE" "$HOSTS_FILE"
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
cp "$TMP_FILE" "$HOSTS_FILE"
EOF
  chmod 0755 "$GENERATED_DIR/libexec/iron-hosts-clear"

  cat > "$GENERATED_DIR/libexec/iron-unproxy-refresh" <<EOF
#!/bin/bash
set -euo pipefail
AUTH_DIR="$CLIPROXY_AUTH_DIR"
AUTH_FILE="\$(ls "\$AUTH_DIR"/*.json 2>/dev/null | head -n 1 || true)"
ANTIGRAVITY_PROXY_ENV="/home/$PROTECTED_USER/.config/iron-dome/antigravity-proxy.env"
antigravity_direct_mode() {
  [ -f "\$ANTIGRAVITY_PROXY_ENV" ] \
    && grep -Eq '^[[:space:]]*IRON_ANTIGRAVITY_PROXY=[[:space:]]*$' "\$ANTIGRAVITY_PROXY_ENV" \
    && grep -Eq '^[[:space:]]*IRON_ANTIGRAVITY_EXPORT_PROXY_ENV=no[[:space:]]*$' "\$ANTIGRAVITY_PROXY_ENV"
}
if [[ -z "\$AUTH_FILE" || ! -f "\$AUTH_FILE" ]]; then
  echo "[IRON DOME] integration auth file not found, skipping refresh"
  exit 0
fi
DIRECT_MODE=no
if antigravity_direct_mode; then
  DIRECT_MODE=yes
fi
AUTH_FILE="\$AUTH_FILE" IRON_ANTIGRAVITY_DIRECT_MODE="\$DIRECT_MODE" python3 - <<'PY'
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
proxy_args = [] if os.environ.get('IRON_ANTIGRAVITY_DIRECT_MODE') == 'yes' else ['--proxy','http://127.0.0.1:8119']
cmd = ['curl',*proxy_args,'-sS','--max-time','30','-o',str(resp_file),'-w','%{http_code}','-X','POST','https://oauth2.googleapis.com/token','-H','Content-Type: application/x-www-form-urlencoded','-d',body]
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
Windows/host proxy:    $WINDOWS_PROXY_ENABLED
Windows proxy bind:    $WINDOWS_PROXY_BIND:$WINDOWS_PROXY_PORT
Windows proxy net:     $WINDOWS_PROXY_NET

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
- $GENERATED_DIR/bin/iron-windows-proxy
- $GENERATED_DIR/bin/ss-key
- $GENERATED_DIR/bin/tor-bridges
- $GENERATED_DIR/libexec/iron-transparent-generate
- $GENERATED_DIR/libexec/iron-dome-lock-apply
- $GENERATED_DIR/libexec/iron-dome-lock-clear
- $GENERATED_DIR/libexec/iron-dome-cleanup
- $GENERATED_DIR/libexec/iron-ss-outline-start
- $GENERATED_DIR/etc/sudoers.d/iron-dome
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
