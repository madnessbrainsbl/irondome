# Architecture

## Core Chain

```text
Application / Browser / CLI
-> transparent strict route (optional)
-> local SOCKS endpoint (127.0.0.1:1080)
-> Tor (127.0.0.1:9050)
-> Outline server
-> Internet
```

## Optional Local Layers

The core can be extended with local helper layers:

```text
Application / Browser / CLI
-> optional local HTTP proxy (127.0.0.1:8119)
-> optional local API gateway (example: 127.0.0.1:8317)
-> local SOCKS endpoint (127.0.0.1:1080)
-> Tor
-> Outline
-> Internet
```

## Optional Integrations

Examples of integrations that can sit on top of the core:

- unproxy local gateway
- browser profiles
- local API gateways
- custom automation clients
- generic HTTP tooling

## Modes

### Open Mode

- Stack is up
- Direct egress is still possible
- Useful for diagnostics and login flows

### Strict Mode

- Stack is up
- Transparent route is active
- Direct bypass is rejected
- Intended to provide fail-closed behaviour for normal web traffic

## Core Ideas

1. Tor hides the real origin.
2. Outline hides the Tor exit from the destination service.
3. Optional local proxies can provide stable loopback endpoints.
4. Strict mode rejects bypass traffic instead of allowing silent leaks.
