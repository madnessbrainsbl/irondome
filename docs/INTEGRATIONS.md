# Integrations

The public product should expose a reusable anonymity core.
Integrations are optional layers on top of that core.

## Core-first rule

The following features belong to the core:

- Tor bridges
- Outline over Tor
- optional local HTTP proxy layer
- strict/open mode
- transparent strict route
- fail-closed lock
- cleanup on boot

The following features must stay optional:

- app-specific OAuth forwarding
- local API gateway examples
- app-specific settings files
- GUI-specific auth recovery flows
- app-specific supported-region egress wrappers

## Current optional integration

### unproxy

Reference files are stored under:

- `integrations/unproxy/`

This includes:

- `local-gateway.yaml.example` — local API gateway config
- `local-gateway.service.example`
- `external-auth-forward.service.example`
- `README.md` — a short integration note

### Antigravity proxy wrapper

Reference files:

- `docs/ANTIGRAVITY_PROXY.md`
- `scripts/smart-antigravity.example.sh`
- `integrations/antigravity/antigravity-proxy.env.example`
- `integrations/antigravity/antigravity-privoxy.conf.example`
- `integrations/antigravity/antigravity-torrc.example`
- `integrations/antigravity/antigravity-tor.service.example`
- `integrations/antigravity/antigravity-tor-privoxy.service.example`

This keeps the core RU-capable Outline route unchanged while allowing Antigravity to use a separate supported-region proxy.

## Future integrations

Possible future optional integrations:

- generic browser profile
- curl/git/client examples
- local LLM gateway
- custom API client
