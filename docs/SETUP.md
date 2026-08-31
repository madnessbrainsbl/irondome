# Setup Overview

## Prerequisites

Required components:

- `tor`
- `obfs4proxy`
- `torsocks`
- `shadowsocks-libev`
- `sing-box`
- `iptables` / `ip6tables`

Optional components:

- `privoxy`
- `socat`
- a local API gateway binary (only for the `unproxy` integration profile)

`socat` is required when `WINDOWS_PROXY_ENABLED=yes` because `iron-windows-proxy` forwards the host-facing listener to `127.0.0.1:8119`.

## Required Inputs

You need to provide:

1. A working `ss://` Outline/Shadowsocks key.
2. A working list of Tor bridges.

Optional integration inputs:

3. A local API gateway binary path.
4. A valid gateway auth state.

`setup` stores both inputs under `state/` with mode `0600`. `state/` and
`generated/` are gitignored — they hold your live key. See
[THREAT_MODEL.md](THREAT_MODEL.md) for what the resulting chain does and does
not cover.

## Files to Customize

- `templates/torrc.strict.example`
- `templates/outline.json.example`
- `systemd/*.example`
- `scripts/*.example.sh`

Optional integration templates live under `integrations/`.

## Recommended Flow

1. Fill in the config templates.
2. Install the generated files into system paths.
3. Start `iron-tor.service`.
4. Verify `9050`.
5. Start `iron-ss-outline.service`.
6. Verify `1080`.
7. Optionally start local helper proxies/gateways.
8. Verify their loopback endpoints if enabled.
9. If exposing the host proxy, verify `127.0.0.1:18119` from Kali and `KALI_VM_IP:18119` from Windows.
10. Enable strict routing only after the full chain is healthy.
