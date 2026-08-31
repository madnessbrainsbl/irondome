<p align="center">
  <img src="https://github.com/user-attachments/assets/fbb9a75a-d8bd-4de4-b126-49bf0f0f6edf" alt="irondome" width="620">
</p>

<h3 align="center">Layered anonymity CLI for Tor → Outline/Shadowsocks routing</h3>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#modes">Modes</a> •
  <a href="#configuration">Configuration</a> •
  <a href="#documentation">Documentation</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-linux-informational">
  <img src="https://img.shields.io/badge/shell-bash-informational">
  <img src="https://img.shields.io/badge/license-MIT-green">
  <img src="https://img.shields.io/badge/status-staging-orange">
</p>

---

# irondome

`irondome` is a terminal CLI for layered anonymity: Tor, bridges,
Outline/Shadowsocks, transparent routing, and systemd service management.

It is a reusable core with optional integrations: no GUI, no embedded secrets,
no hardcoded runtime state.

**Read [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) before relying on this for
anything that matters.** It lists what the chain does not protect against.

## Features

- Tor → Outline/Shadowsocks chained routing
- Optional transparent strict mode
- Fail-closed network lock
- Tor bridge management
- Outline/Shadowsocks key management
- Template-based config rendering
- systemd service installation
- Dry-run installation root
- Doctor checks for connectivity and leaks
- Optional host-OS/Windows proxy bridge
- Optional integration profiles

## How it works

```text
App
  ↓
transparent strict route (optional)
  ↓
SOCKS5 127.0.0.1:1080
  ↓
Tor 127.0.0.1:9050
  ↓
Outline/Shadowsocks server
  ↓
Internet

Windows browser (optional)
  ↓
Kali VM:18119
  ↓
HTTP proxy 127.0.0.1:8119
  ↓
same Tor → Outline chain
```

- Tor hides your origin from the Outline/Shadowsocks server.
- Outline/Shadowsocks hides the Tor exit from the destination.
- Strict mode blocks traffic that attempts to bypass the chain.

## Installation

```bash
git clone https://github.com/madnessbrainsbl/irondome.git
cd irondome
chmod +x ./bin/irondome ./lib/*.sh
```

Install required packages:

```bash
sudo apt update
sudo apt install -y tor obfs4proxy torsocks shadowsocks-libev privoxy socat sing-box curl python3
```

## Usage

```bash
./bin/irondome            # help
./bin/irondome menu       # interactive menu
```

```text
Usage:
  irondome <command>

Commands:
  menu       Show interactive menu
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
```

## First-time setup

```bash
./bin/irondome setup
./bin/irondome render
sudo ./bin/irondome install
sudo iron-dome-start
./bin/irondome status
./bin/irondome doctor
```

Stop:

```bash
sudo iron-dome-stop
```

### What lands where

`setup` writes your real `ss://` key and bridges to `state/`; `render` writes the
Shadowsocks password in cleartext to `generated/config/outline.json`. Both
directories are gitignored and the files are created `0600`. Do not commit them
and do not copy them into issue reports.

## Dry run

Render and install into a temporary root without touching the live system:

```bash
./bin/irondome render
./bin/irondome install --root /tmp/irondome-test-root
```

`scripts/smoke-test.sh` does exactly this end to end and needs no root.

## Modes

| Mode    | Description                                                                       |
| ------- | --------------------------------------------------------------------------------- |
| `open`  | Starts the stack without strict traffic lock. Useful for diagnostics.             |
| `start` | Starts strict mode. Transparent routing is active and bypass traffic is rejected. |
| `stop`  | Stops the stack and restores normal networking.                                   |

## Commands

### Setup wizard

```bash
./bin/irondome setup
```

Interactive configuration wizard: protected user, install prefix, integration
profile, Tor bridges, Outline/Shadowsocks key.

### Render configuration

```bash
./bin/irondome render
```

Generates config files from templates into `generated/`.

### Install generated files

```bash
sudo ./bin/irondome install
sudo ./bin/irondome install --root /tmp/irondome-test-root   # dry run
```

### Start, stop, status, doctor

```bash
sudo ./bin/irondome start     # strict mode (or: sudo iron-dome-start)
sudo ./bin/irondome open      # no strict lock
./bin/irondome status
./bin/irondome doctor
```

### Update Tor bridges / Outline key

```bash
./bin/irondome bridges
./bin/irondome outline
```

After installation the generated `ss-key` helper can replace the live key and
verify the new egress:

```bash
sudo ss-key 'ss://...'
```

It writes the Outline config, restarts `iron-ss-outline.service`, checks
`127.0.0.1:1080`, prints GeoIP/ASN details, and rolls back if `1080` stays dead.

### Backup and restore

```bash
./bin/irondome backup                 # -> backups/<timestamp>/
./bin/irondome restore                # newest backup
./bin/irondome restore backups/20260501_120000
```

Backups contain your `ss://` key. They are gitignored and written `0600`.

## Configuration

You need to provide:

1. A working `ss://` Outline/Shadowsocks key
2. Tor bridges — `render` currently requires at least one; get them from
   <https://bridges.torproject.org> or by emailing `bridges@torproject.org`
3. The protected Linux user
4. An integration profile

Recommended first run: `Integration profile: none`. Test optional integrations
(`unproxy`) only after the core chain works.

`state/*.example` shows the shape of every state file.

## Host OS / Windows Proxy

When the browser runs on the Windows host and Iron Dome runs in Kali/VMware,
enable the host proxy during setup:

```text
Expose HTTP proxy to host OS/LAN: yes
Windows/host proxy bind address: 0.0.0.0
Windows/host proxy listen port: 18119
Windows/host proxy client network: 192.168.98.0/24
```

`WINDOWS_PROXY_NET` is enforced by the listener (`socat … range=`), so only that
network can use the tunnel. It is still an **unauthenticated** proxy — point it
at a host-only/VM network, never at an untrusted LAN.

After `sudo iron-dome-start`, set Windows to use `KALI_VM_IP:18119` as its
HTTP/HTTPS proxy and verify `https://api.ipify.org` from Windows matches the Kali
proxy result, not your ISP IP.

See [Windows Host Proxy](docs/WINDOWS_HOST_PROXY.md) for PowerShell commands.

## Optional integrations

- `unproxy` — local API gateway on `127.0.0.1:8317`, see [Integrations](docs/INTEGRATIONS.md)
- Antigravity per-app egress, see [Antigravity Proxy](docs/ANTIGRAVITY_PROXY.md)

Both are optional and off by default. The core chain does not need them.

## Troubleshooting

### Startup stops at `waiting for 1080`

Tor is up but Outline has no egress. Check the key:

```bash
scripts/check-ss-key-health.example.sh
```

`SS_KEY_STATUS=expired_or_invalid ACTION=replace_key` means the key is dead —
replace it with `sudo ss-key <ss://key>`.

### Strict start hangs after `starting transparent route`

```bash
systemctl status iron-dome-lock.service --no-pager
journalctl -u iron-dome-lock.service --no-pager -n 80
```

`iptables ... host/network '<outline-host>' not found` means the Outline server
is configured as a domain name. The rendered lock helper resolves it to IPv4
before installing rules — re-render and reinstall:

```bash
./bin/irondome render
sudo ./bin/irondome install
sudo iron-dome-start
```

Healthy markers:

```text
iron-dome-lock.service active
curl --socks5-hostname 127.0.0.1:1080 https://api.ipify.org
```

## Project structure

```text
bin/irondome          CLI entrypoint
lib/                  command implementations
templates/            config templates
systemd/              service unit templates
scripts/              helper scripts
docs/                 architecture, threat model, setup
integrations/         optional integration examples
state/                runtime state (gitignored; *.example is tracked)
generated/            rendered output (gitignored)
```

## Documentation

- [Threat Model](docs/THREAT_MODEL.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Setup](docs/SETUP.md)
- [Integrations](docs/INTEGRATIONS.md)
- [Antigravity Proxy](docs/ANTIGRAVITY_PROXY.md)
- [Windows Host Proxy](docs/WINDOWS_HOST_PROXY.md)

## License

[MIT](LICENSE)
