# Contents

## docs/

- `THREAT_MODEL.md` — what the chain protects against and what it does not
- `ARCHITECTURE.md` — core chain and optional integrations
- `SETUP.md` — setup overview
- `INTEGRATIONS.md` — optional integrations on top of the core
- `ANTIGRAVITY_PROXY.md` — per-app supported-region proxy wrapper for Antigravity
- `WINDOWS_HOST_PROXY.md` — host/Windows browser proxy through the Iron Dome chain

## templates/

- `torrc.strict.example`
- `outline.json.example`
- `privoxy.conf.example`

## systemd/

- `iron-tor.service.example`
- `iron-ss-outline.service.example`
- `iron-transparent.service.example`
- `iron-dome-lock.service.example`
- `iron-dome-cleanup.service.example`
- `iron-privoxy.service.example`

## integrations/

- `unproxy/` — optional local gateway integration reference
- `antigravity/` — user-level Antigravity proxy through supported Tor egress

## scripts/

- `smoke-test.sh` — render + dry-run install + assertions, no root needed
- `tor-bridges.example.sh`
- `ss-key.example.sh`
- `check-ss-key-health.example.sh`
- `smart-antigravity.example.sh`
- `iron-dome-start.example.sh`
- `iron-dome-stop.example.sh`

## bin/

- `irondome` — main terminal entrypoint

## lib/

- command implementations and helpers
- commands: `menu`, `setup`, `render`, `install`, `start`, `stop`, `open`,
  `status`, `doctor`, `bridges`, `outline`, `backup`, `restore`

## state/ (gitignored)

Runtime state written by `setup`, `bridges`, and `outline`. Contains your real
`ss://` key and bridges — never commit it. Only `state/*.example` is tracked.

## generated/ (gitignored)

Output of `render`. Contains the Shadowsocks password in cleartext.

## top-level

- `README.md`
- `LICENSE`
- `PUBLISHING_TODO.md`
