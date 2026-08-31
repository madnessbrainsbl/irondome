#!/bin/bash
# Renders and installs into a throwaway root and asserts the expected files
# exist. No root, no network, no live system changes. Run from the repo root.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Use a scratch copy so a real state/ is never touched.
REPO="$WORK/repo"
mkdir -p "$REPO"
for d in bin lib templates systemd scripts integrations; do
  cp -a "$ROOT_DIR/$d" "$REPO/"
done
mkdir -p "$REPO/state"

cat > "$REPO/state/irondome.env" <<'EOF'
PROTECTED_USER="smoke"
INTEGRATION_PROFILE="none"
ENABLE_LOCAL_HTTP_PROXY="yes"
INSTALL_PREFIX="/opt/irondome"
CLIPROXY_BIN="/opt/local-gateway/gateway"
CLIPROXY_WORKDIR="/opt/local-gateway"
CLIPROXY_AUTH_DIR="/var/lib/local-gateway/auth"
CLIPROXY_STORAGE_DIR="/var/lib/local-gateway"
ENABLE_STRICT="yes"
ENABLE_OPEN="yes"
ENABLE_GOOGLE_FORWARD="no"
ENABLE_BOOT_CLEANUP="yes"
INCLUDE_ROOT_WEB="yes"
TRANSPARENT_MTU="1200"
WINDOWS_PROXY_ENABLED="yes"
WINDOWS_PROXY_BIND="0.0.0.0"
WINDOWS_PROXY_PORT="18119"
WINDOWS_PROXY_NET="192.168.98.0/24"
EOF
printf 'obfs4 1.2.3.4:443 FINGERPRINT cert=TEST iat-mode=0\n' > "$REPO/state/bridges.txt"
SS_KEY='ss://YWVzLTI1Ni1nY206c3Ryb25ncGFzcw==@example.com:8388'   # aes-256-gcm:strongpass
printf '%s\n' "$SS_KEY" > "$REPO/state/outline_ss_key.txt"

fail=0
check() {
  if [[ -e "$1" ]]; then
    printf 'OK       %s\n' "${1#"$WORK"/}"
  else
    printf 'MISSING  %s\n' "${1#"$WORK"/}"
    fail=1
  fi
}

echo "=== syntax ==="
bash -n "$REPO/bin/irondome"
for f in "$REPO"/lib/*.sh "$ROOT_DIR"/scripts/*.sh; do bash -n "$f"; done
echo "all scripts parse"

echo
echo "=== render ==="
"$REPO/bin/irondome" render >/dev/null

for f in config/torrc.strict config/outline.json config/privoxy.conf \
         bin/iron-dome-start bin/iron-dome-stop bin/iron-dome-open \
         bin/iron-windows-proxy bin/ss-key bin/tor-bridges \
         libexec/iron-transparent-generate libexec/iron-dome-lock-apply \
         libexec/iron-dome-lock-clear libexec/iron-dome-cleanup \
         systemd/iron-tor.service systemd/iron-ss-outline.service \
         systemd/iron-transparent.service systemd/iron-dome-lock.service \
         systemd/iron-privoxy.service summary.txt; do
  check "$REPO/generated/$f"
done

echo
echo "=== rendered content ==="
grep -q '"password": "strongpass"' "$REPO/generated/config/outline.json" \
  && echo "OK       ss:// key decoded into outline.json" \
  || { echo "FAIL     ss:// key not decoded"; fail=1; }
grep -q '^Bridge obfs4 1.2.3.4:443' "$REPO/generated/config/torrc.strict" \
  && echo "OK       bridge line written to torrc" \
  || { echo "FAIL     bridge missing from torrc"; fail=1; }
# CLIENT_NET is expanded when the helper runs, so assert both halves separately.
grep -q 'CLIENT_NET="${IRON_WINDOWS_PROXY_NET:-192.168.98.0/24}"' "$REPO/generated/bin/iron-windows-proxy" \
  && grep -q 'range=${CLIENT_NET}' "$REPO/generated/bin/iron-windows-proxy" \
  && echo "OK       host proxy restricted to WINDOWS_PROXY_NET" \
  || { echo "FAIL     host proxy accepts any source"; fail=1; }
grep -q 'TORRC="${IRON_TORRC:-/opt/irondome/config/torrc.strict}"' "$REPO/generated/bin/tor-bridges" \
  && echo "OK       tor-bridges points at the installed torrc" \
  || { echo "FAIL     tor-bridges torrc path not substituted"; fail=1; }
grep -q '__PROJECT_ROOT__\|__INSTALL_ROOT__\|__CLIPROXY\|__TORRC__\|__STATE_BRIDGES__\|__OUTLINE_CONFIG__' -r "$REPO/generated" \
  && { echo "FAIL     unsubstituted placeholder in generated output"; fail=1; } \
  || echo "OK       no unsubstituted placeholders"

echo
echo "=== install --root ==="
"$REPO/bin/irondome" install --root "$WORK/target" >/dev/null
for f in usr/local/bin/iron-dome-start usr/local/bin/iron-dome-stop \
         usr/local/libexec/iron-dome-lock-apply \
         etc/systemd/system/iron-tor.service \
         opt/irondome/config/outline.json; do
  check "$WORK/target/$f"
done

# Git Bash on NTFS reports fake modes, so probe before trusting the assertion.
probe="$WORK/.probe"; : > "$probe"; chmod 0600 "$probe"
if [[ "$(stat -c '%a' "$probe")" == "600" ]]; then
  perms="$(stat -c '%a' "$WORK/target/opt/irondome/config/outline.json")"
  [[ "$perms" == "600" || "$perms" == "640" ]] \
    && echo "OK       outline.json installed $perms" \
    || { echo "FAIL     outline.json installed $perms (secret is world-readable)"; fail=1; }
else
  echo "SKIP     outline.json mode (filesystem has no POSIX permissions)"
fi

echo
echo "=== backup / restore ==="
"$REPO/bin/irondome" backup >/dev/null
printf 'ss://replaced\n' > "$REPO/state/outline_ss_key.txt"
"$REPO/bin/irondome" restore >/dev/null
# The stored key is base64; compare the whole line, not the decoded password.
grep -qxF "$SS_KEY" "$REPO/state/outline_ss_key.txt" \
  && echo "OK       restore recovered the key" \
  || { echo "FAIL     restore did not recover the key"; fail=1; }

echo
if [[ "$fail" -eq 0 ]]; then
  echo "smoke test passed"
else
  echo "smoke test FAILED"
fi
exit "$fail"
