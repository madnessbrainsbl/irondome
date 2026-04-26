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

- app-specific-specific OAuth forwarding
- local API gateway examples
- app-specific settings files
- GUI-specific auth recovery flows

## Current optional integration

### unproxy

Reference files are stored under:

- `integrations/unproxy/`

This includes:

- local API gateway example config
- `iron-cliproxy.service.example`
- `iron-google-forward.service.example`
- a short integration note

## Future integrations

Possible future optional integrations:

- generic browser profile
- curl/git/client examples
- local LLM gateway
- custom API client
