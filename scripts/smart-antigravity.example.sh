#!/usr/bin/env bash
set -euo pipefail

export DONT_PROMPT_WSL_INSTALL=1

PROXY_ENV="${IRON_ANTIGRAVITY_PROXY_ENV:-$HOME/.config/iron-dome/antigravity-proxy.env}"
if [[ -f "$PROXY_ENV" ]]; then
  # This file is user-owned configuration for IRON_ANTIGRAVITY_PROXY only.
  # shellcheck disable=SC1090
  . "$PROXY_ENV"
fi

PROXY="${IRON_ANTIGRAVITY_PROXY:-${ANTIGRAVITY_PROXY:-}}"
NO_PROXY_VALUE="${IRON_ANTIGRAVITY_NO_PROXY:-localhost,127.0.0.1,127.0.0.0/8,::1}"
ANTIGRAVITY_BIN="${IRON_ANTIGRAVITY_BIN:-/usr/share/antigravity/antigravity}"

if [[ -z "$PROXY" ]]; then
  echo "smart-antigravity: IRON_ANTIGRAVITY_PROXY is not set; launching without per-app proxy" >&2
  exec "$ANTIGRAVITY_BIN" "$@"
fi

CHROMIUM_PROXY="$PROXY"
if [[ "$CHROMIUM_PROXY" == socks5h://* ]]; then
  CHROMIUM_PROXY="socks5://${CHROMIUM_PROXY#socks5h://}"
fi

if [[ "${IRON_ANTIGRAVITY_EXPORT_PROXY_ENV:-no}" == "yes" ]]; then
  export HTTP_PROXY="$PROXY"
  export HTTPS_PROXY="$PROXY"
  export ALL_PROXY="$PROXY"
  export http_proxy="$PROXY"
  export https_proxy="$PROXY"
  export all_proxy="$PROXY"
  export NO_PROXY="$NO_PROXY_VALUE"
  export no_proxy="$NO_PROXY_VALUE"
  export GRPC_PROXY="$PROXY"
  export grpc_proxy="$PROXY"
  export GOPROXY="direct"
fi

exec "$ANTIGRAVITY_BIN" \
  --proxy-server="$CHROMIUM_PROXY" \
  --proxy-bypass-list="<local>;localhost;127.0.0.1;127.0.0.0/8;[::1]" \
  "$@"
