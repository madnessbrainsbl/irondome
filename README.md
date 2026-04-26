# irondome

Terminal CLI for layered anonymity: chains Tor through Shadowsocks/Outline proxies with transparent routing and systemd service management. Reusable core with optional integrations — no secrets, no GUI, no runtime state.

## How it works

Traffic flows through a multi-hop chain so no single node sees both your real IP and your destination:

```
App → transparent strict route (optional) → SOCKS5 (127.0.0.1:1080) → Tor (127.0.0.1:9050) → Outline server → Internet
```

- **Tor** hides your origin from the Outline server
- **Outline/Shadowsocks** hides the Tor exit from the destination
- **Strict mode** blocks any traffic that tries to bypass the chain

### Modes

| Mode       | Description                                                             |
| ---------- | ----------------------------------------------------------------------- |
| **Open**   | Stack is up, direct egress still allowed — useful for diagnostics       |
| **Strict** | Transparent route active, bypass rejected — fail-closed for web traffic |

## Quick start

```bash
./bin/irondome setup        # interactive configuration wizard
./bin/irondome bridges      # manage Tor bridges
./bin/irondome outline      # set Outline/Shadowsocks key
./bin/irondome render       # generate config files from templates
./bin/irondome install --root /opt/irondome   # install generated files
./bin/irondome start        # start all services
./bin/irondome status       # check chain health
./bin/irondome doctor       # diagnose common issues
./bin/irondome stop         # stop all services
```

## Prerequisites

Required:

- `tor`, `obfs4proxy`, `torsocks`
- `shadowsocks-libev` or `sing-box`
- `iptables` / `ip6tables`

Optional:

- `privoxy` — local HTTP proxy
- `cliproxy`, `socat` — gateway integrations

You need to provide:

1. A working `ss://` Outline/Shadowsocks key
2. A list of Tor bridges

## Project structure

```
bin/irondome          CLI entrypoint
lib/                  command implementations
templates/            config templates (torrc, outline, privoxy)
systemd/              service unit templates
scripts/              helper script examples
docs/                 architecture, setup, integrations
integrations/         optional integration examples (unproxy, etc.)
state/                runtime state (env, keys, bridges)
generated/            rendered output from templates
```

## Integrations

The core is self-contained. Integrations are optional layers on top:

- `integrations/unproxy/` — local API gateway example
- Future: browser profiles, curl/git configs, LLM gateway

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — chain layout and modes
- [Setup](docs/SETUP.md) — prerequisites and recommended flow
- [Integrations](docs/INTEGRATIONS.md) — optional layers

## License

MIT
