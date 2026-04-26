#!/bin/bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ROOT_DIR:-$(cd "$LIB_DIR/.." && pwd)}"
IRONDOME_VERSION="0.1.0-staging"
STATE_DIR="$ROOT_DIR/state"
GENERATED_DIR="$ROOT_DIR/generated"
TEMPLATES_DIR="$ROOT_DIR/templates"
SYSTEMD_TEMPLATES_DIR="$ROOT_DIR/systemd"
CONFIG_FILE="$STATE_DIR/irondome.env"
BRIDGES_FILE="$STATE_DIR/bridges.txt"
OUTLINE_KEY_FILE="$STATE_DIR/outline_ss_key.txt"

ensure_dirs() {
  mkdir -p "$STATE_DIR" "$GENERATED_DIR" "$GENERATED_DIR/systemd"
}

print_header() {
  local title="$1"
  printf '\n%s\n\n' "$title"
}

irondome_banner() {
  printf '\n\033[1;31m'
  cat <<'EOF'
███╗   ███╗ █████╗ ██████╗ ███╗   ██╗███████╗███████╗███████╗
████╗ ████║██╔══██╗██╔══██╗████╗  ██║██╔════╝██╔════╝██╔════╝
██╔████╔██║███████║██║  ██║██╔██╗ ██║█████╗  ███████╗███████╗
██║╚██╔╝██║██╔══██║██║  ██║██║╚██╗██║██╔══╝  ╚════██║╚════██║
██║ ╚═╝ ██║██║  ██║██████╔╝██║ ╚████║███████╗███████║███████║
╚═╝     ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═══╝╚══════╝╚══════╝╚══════╝

██████╗ ██████╗  █████╗ ██╗███╗   ██╗███████╗
██╔══██╗██╔══██╗██╔══██╗██║████╗  ██║██╔════╝
██████╔╝██████╔╝███████║██║██╔██╗ ██║███████╗
██╔══██╗██╔══██╗██╔══██║██║██║╚██╗██║╚════██║
██████╔╝██║  ██║██║  ██║██║██║ ╚████║███████║
╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝╚══════╝
EOF
  printf '\033[0m\n  v%s\n\n' "$IRONDOME_VERSION"
}

irondome_notice() {
  :
}

prompt_default() {
  local label="$1"
  local default_value="$2"
  local answer
  read -r -p "$label [$default_value]: " answer
  if [[ -z "$answer" ]]; then
    printf '%s\n' "$default_value"
  else
    printf '%s\n' "$answer"
  fi
}

prompt_yes_no() {
  local label="$1"
  local default_value="$2"
  local prompt="[y/N]"
  local answer
  if [[ "$default_value" == "yes" ]]; then
    prompt="[Y/n]"
  fi
  read -r -p "$label $prompt: " answer
  answer="${answer,,}"
  if [[ -z "$answer" ]]; then
    answer="$default_value"
  fi
  case "$answer" in
    y|yes) printf 'yes\n' ;;
    n|no) printf 'no\n' ;;
    *) printf '%s\n' "$default_value" ;;
  esac
}

collect_multiline() {
  local target_file="$1"
  local title="$2"
  print_header "$title"
  echo "Enter one line per entry."
  echo "Submit an empty line to finish."
  : > "$target_file"
  while IFS= read -r line; do
    [[ -z "$line" ]] && break
    printf '%s\n' "$line" >> "$target_file"
  done
}

save_config() {
  ensure_dirs
  cat > "$CONFIG_FILE" <<EOF
PROTECTED_USER="$PROTECTED_USER"
INTEGRATION_PROFILE="$INTEGRATION_PROFILE"
ENABLE_LOCAL_HTTP_PROXY="$ENABLE_LOCAL_HTTP_PROXY"
INSTALL_PREFIX="$INSTALL_PREFIX"
CLIPROXY_BIN="$CLIPROXY_BIN"
CLIPROXY_WORKDIR="$CLIPROXY_WORKDIR"
CLIPROXY_AUTH_DIR="$CLIPROXY_AUTH_DIR"
CLIPROXY_STORAGE_DIR="$CLIPROXY_STORAGE_DIR"
ENABLE_STRICT="$ENABLE_STRICT"
ENABLE_OPEN="$ENABLE_OPEN"
ENABLE_GOOGLE_FORWARD="$ENABLE_GOOGLE_FORWARD"
ENABLE_BOOT_CLEANUP="$ENABLE_BOOT_CLEANUP"
INCLUDE_ROOT_WEB="$INCLUDE_ROOT_WEB"
TRANSPARENT_MTU="$TRANSPARENT_MTU"
EOF
}

load_config() {
  ensure_dirs
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
  fi
  PROTECTED_USER="${PROTECTED_USER:-kali}"
  INTEGRATION_PROFILE="${INTEGRATION_PROFILE:-none}"
  ENABLE_LOCAL_HTTP_PROXY="${ENABLE_LOCAL_HTTP_PROXY:-yes}"
  INSTALL_PREFIX="${INSTALL_PREFIX:-/opt/madnessbrains/irondome}"
  CLIPROXY_BIN="${CLIPROXY_BIN:-/opt/CLIProxyAPIPlus/cliproxy}"
  CLIPROXY_WORKDIR="${CLIPROXY_WORKDIR:-/opt/CLIProxyAPIPlus}"
  CLIPROXY_AUTH_DIR="${CLIPROXY_AUTH_DIR:-/var/lib/cliproxy/auth}"
  CLIPROXY_STORAGE_DIR="${CLIPROXY_STORAGE_DIR:-/var/lib/cliproxy}"
  ENABLE_STRICT="${ENABLE_STRICT:-yes}"
  ENABLE_OPEN="${ENABLE_OPEN:-yes}"
  ENABLE_GOOGLE_FORWARD="${ENABLE_GOOGLE_FORWARD:-yes}"
  ENABLE_BOOT_CLEANUP="${ENABLE_BOOT_CLEANUP:-yes}"
  INCLUDE_ROOT_WEB="${INCLUDE_ROOT_WEB:-yes}"
  TRANSPARENT_MTU="${TRANSPARENT_MTU:-1200}"
}

require_state_file() {
  local path="$1"
  local message="$2"
  if [[ ! -s "$path" ]]; then
    echo "$message" >&2
    exit 1
  fi
}

render_template_file() {
  local src="$1"
  local dst="$2"
  python3 - "$src" "$dst" <<'PY'
from pathlib import Path
import os, sys
src = Path(sys.argv[1]).read_text()
mapping = {
    '__PROJECT_ROOT__': os.environ['ROOT_DIR'],
    '__INSTALL_ROOT__': os.environ['INSTALL_PREFIX'],
    '__CLIPROXY_BIN__': os.environ['CLIPROXY_BIN'],
    '__CLIPROXY_WORKDIR__': os.environ['CLIPROXY_WORKDIR'],
  }
for k, v in mapping.items():
    src = src.replace(k, v)
Path(sys.argv[2]).write_text(src)
PY
}

parse_ss_key_to_outline_json() {
  local output_file="$1"
  python3 - "$output_file" <<'PY'
import os, base64, json, urllib.parse, sys
from pathlib import Path

key = Path(os.environ['OUTLINE_KEY_FILE']).read_text().strip()
if not key:
    raise SystemExit('Outline ss:// key is empty')

u = urllib.parse.urlsplit(key)
if u.scheme != 'ss':
    raise SystemExit('Not an ss:// key')

if '@' not in u.netloc:
    raise SystemExit('Invalid ss:// key: missing @host:port section')

try:
    userinfo, hostport = u.netloc.rsplit('@', 1)
    host, port = hostport.rsplit(':', 1)
except ValueError as exc:
    raise SystemExit('Invalid ss:// key: unable to parse host/port') from exc
userinfo = urllib.parse.unquote(userinfo)
if ':' in userinfo:
    method, password = userinfo.split(':', 1)
else:
    pad = '=' * (-len(userinfo) % 4)
    try:
        decoded = base64.urlsafe_b64decode((userinfo + pad).encode()).decode('utf-8')
        method, password = decoded.split(':', 1)
    except Exception as exc:
        raise SystemExit('Invalid ss:// key: unable to decode credentials') from exc

cfg = {
    'server': host,
    'server_port': int(port),
    'password': password,
    'method': method,
    'local_address': '127.0.0.1',
    'local_port': 1080,
    'timeout': 300,
}
Path(sys.argv[1]).write_text(json.dumps(cfg, indent=2) + '\n')
PY
}

irondome_help() {
  cat <<'EOF'
Usage:
  irondome <command>

Commands:
  setup      Run interactive setup wizard
  install    Install generated files and services
  start      Start strict mode
  stop       Stop stack and restore normal networking
  open       Start stack without strict lock
  status     Show current status
  doctor     Run connectivity and leak checks
  bridges    Update Tor bridges
  outline    Update Outline key
  render     Render configuration only
  backup     Backup current configuration
  restore    Restore configuration backup
  help       Show this help
EOF
}

not_implemented() {
  local command="$1"
  cat <<EOF
$command is not implemented yet.

This is a staging CLI skeleton for the future MadnessBrains Iron Dome product.
EOF
}
