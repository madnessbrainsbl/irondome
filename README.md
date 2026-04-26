
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
<img width="762" height="472" alt="iron" src="https://github.com/user-attachments/assets/fbb9a75a-d8bd-4de4-b126-49bf0f0f6edf" />


`irondome` is a terminal CLI for layered anonymity: Tor, bridges, Outline/Shadowsocks, transparent routing, and systemd service management.

It is designed as a reusable core with optional integrations: no GUI, no embedded secrets, no hardcoded runtime state.

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
```

- Tor hides your origin from the Outline/Shadowsocks server.
- Outline/Shadowsocks hides the Tor exit from the destination.
- Strict mode blocks traffic that attempts to bypass the chain.

## Installation

All commands must be executed from the project root:

```bash
cd ~/Desktop/vremen/iron_shield/git
chmod +x ./bin/irondome ./lib/*.sh
```

Install required packages:

```bash
sudo apt update
sudo apt install -y tor obfs4proxy torsocks shadowsocks-libev privoxy socat sing-box curl python3 sqlite3 netcat-openbsd
```

## Usage

Display help:

```bash
./bin/irondome
```

or:

```bash
./bin/irondome help
```

Example output:

```text
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

## Stop

```bash
sudo iron-dome-stop
```

## Dry run

Use dry-run installation when you want to render and install into a temporary root without modifying the live system:

```bash
./bin/irondome render
./bin/irondome install --root /tmp/irondome-test-root
```

Generated files will be placed under:

```text
/tmp/irondome-test-root
```

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

Interactive configuration wizard. Use it to define protected user, install prefix, integration profile, Tor bridges, and Outline/Shadowsocks key.

### Render configuration

```bash
./bin/irondome render
```

Generates config files from templates.

### Install generated files

```bash
sudo ./bin/irondome install
```

Installs generated files and systemd services.

Custom installation root:

```bash
./bin/irondome install --root /tmp/irondome-test-root
```

### Start strict mode

```bash
sudo iron-dome-start
```

or:

```bash
sudo ./bin/irondome start
```

### Start open mode

```bash
sudo ./bin/irondome open
```

### Status

```bash
./bin/irondome status
```

### Doctor

```bash
./bin/irondome doctor
```

### Update Tor bridges

```bash
./bin/irondome bridges
```

### Update Outline/Shadowsocks key

```bash
./bin/irondome outline
```

### Backup and restore

```bash
./bin/irondome backup
./bin/irondome restore
```

## Configuration

You need to provide:

1. A working `ss://` Outline/Shadowsocks key
2. Tor bridges
3. The protected Linux user
4. Integration profile

Recommended first test:

```text
Integration profile: none
```

After core mode works, test optional integrations:

```text
Integration profile: unproxy
```

## Project structure

```text
bin/irondome          CLI entrypoint
lib/                  command implementations
templates/            config templates
systemd/              service unit templates
scripts/              helper scripts
docs/                 architecture and setup docs
integrations/         optional integration examples
state/                runtime state
generated/            rendered output
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Setup](docs/SETUP.md)
- [Integrations](docs/INTEGRATIONS.md)

## License

MIT
