# Contents

## docs/

- `ARCHITECTURE.md` — core chain and optional integrations
- `SETUP.md` — setup overview
- `INTEGRATIONS.md` — optional integrations on top of the core

## templates/

- `torrc.strict.example`
- `outline.json.example`

## systemd/

- `iron-tor.service.example`
- `iron-ss-outline.service.example`
- `iron-transparent.service.example`
- `iron-dome-lock.service.example`

## integrations/

- `unproxy/` — optional local gateway integration reference

## scripts/

- `tor-bridges.example.sh`
- `ss-key.example.sh`
- `iron-dome-start.example.sh`
- `iron-dome-stop.example.sh`

## bin/

- `irondome` — main terminal entrypoint

## lib/

- command implementations and helpers
- current working commands:
  - `setup`
  - `bridges`
  - `outline`
  - `status`
  - `render`
  - `install`
  - `doctor`

## top-level

- `README.md`
- `PUBLISHING_TODO.md`

## Note

This is a staging directory for the future public GitHub version.
Live frozen/runtime files are intentionally excluded.
