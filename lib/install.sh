#!/bin/bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$LIB_DIR/common.sh"

load_config

require_state_file "$GENERATED_DIR/summary.txt" "Nothing has been rendered yet. Run: irondome render"

check_dependency() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing dependency: $cmd" >&2
    exit 1
  }
}

check_core_dependencies() {
  for cmd in tor obfs4proxy torsocks ss-local sing-box curl python3; do
    check_dependency "$cmd"
  done

  if [[ "$ENABLE_LOCAL_HTTP_PROXY" == "yes" || "$INTEGRATION_PROFILE" == "unproxy" ]]; then
    check_dependency privoxy
  fi

  if [[ "$INTEGRATION_PROFILE" == "unproxy" ]]; then
    check_dependency socat
  fi
}

TARGET_ROOT="/"
if [[ "${1:-}" == "--root" ]]; then
  TARGET_ROOT="${2:-}"
  [[ -n "$TARGET_ROOT" ]] || { echo "Missing --root path" >&2; exit 1; }
fi

prefix_path() {
  local rel="$1"
  if [[ "$TARGET_ROOT" == "/" ]]; then
    printf '%s\n' "$rel"
  else
    printf '%s\n' "$TARGET_ROOT$rel"
  fi
}

BIN_DIR="$(prefix_path /usr/local/bin)"
LIBEXEC_DIR="$(prefix_path /usr/local/libexec)"
SYSTEMD_DIR="$(prefix_path /etc/systemd/system)"
INSTALL_ROOT_DIR="$(prefix_path "$INSTALL_PREFIX")"
CONFIG_DIR="$INSTALL_ROOT_DIR/config"
INTEGRATIONS_DIR="$INSTALL_ROOT_DIR/integrations"

if [[ "$TARGET_ROOT" == "/" ]]; then
  check_core_dependencies
fi

install -d -m 0755 "$BIN_DIR" "$LIBEXEC_DIR" "$SYSTEMD_DIR" "$CONFIG_DIR" "$INTEGRATIONS_DIR"

if [[ "$TARGET_ROOT" == "/" && "$INTEGRATION_PROFILE" == "unproxy" ]]; then
  id cliproxysvc >/dev/null 2>&1 || useradd --system --home /var/lib/cliproxy --shell /usr/sbin/nologin cliproxysvc
  install -d -m 0755 /var/lib/cliproxy
  install -d -m 0755 /var/lib/cliproxy/auth
  chown -R cliproxysvc:cliproxysvc /var/lib/cliproxy
fi

for file in "$GENERATED_DIR/bin"/*; do
  [[ -f "$file" ]] || continue
  install -m 0755 "$file" "$BIN_DIR/$(basename "$file")"
done

for file in "$GENERATED_DIR/libexec"/*; do
  [[ -f "$file" ]] || continue
  install -m 0755 "$file" "$LIBEXEC_DIR/$(basename "$file")"
done

for file in "$GENERATED_DIR/systemd"/*; do
  [[ -f "$file" ]] || continue
  install -m 0644 "$file" "$SYSTEMD_DIR/$(basename "$file")"
done

for file in "$GENERATED_DIR/config"/*; do
  [[ -f "$file" ]] || continue
  install -m 0644 "$file" "$CONFIG_DIR/$(basename "$file")"
done

if [[ -d "$GENERATED_DIR/integrations" ]]; then
  mkdir -p "$INTEGRATIONS_DIR"
  cp -a "$GENERATED_DIR/integrations/." "$INTEGRATIONS_DIR/"
  find "$GENERATED_DIR/integrations" -type f -name '*.service' -print0 | while IFS= read -r -d '' file; do
    install -m 0644 "$file" "$SYSTEMD_DIR/$(basename "$file")"
  done
fi

if [[ "$TARGET_ROOT" == "/" ]]; then
  systemctl daemon-reload
  if [[ "$ENABLE_BOOT_CLEANUP" == "yes" && -f "$SYSTEMD_DIR/iron-dome-cleanup.service" ]]; then
    systemctl enable iron-dome-cleanup.service || true
  fi
fi

cat <<EOF
Install completed.

Target root: $TARGET_ROOT
Install prefix: $INSTALL_PREFIX

Installed:
  $BIN_DIR/iron-dome-start
  $BIN_DIR/iron-dome-stop
  $BIN_DIR/iron-dome-open
  $LIBEXEC_DIR/*
  $SYSTEMD_DIR/*.service
  $CONFIG_DIR/*
EOF
