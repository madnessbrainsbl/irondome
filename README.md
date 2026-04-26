# madnessbrains

This directory is a staging area for the future GitHub version.

It is not a direct export of the live machine.
It contains safe templates and CLI scaffolding that can be turned into a public repository without exposing runtime state, secrets, or machine-specific paths.

## Product Direction

The public version is being shaped as:

- a terminal-only interactive CLI
- a reusable anonymity core
- optional integrations on top of that core

The core should not depend on any app-specific integration.
`unproxy` is treated as an optional local gateway profile.

That means:

- the core must stay usable without `unproxy`
- integration-specific files must live under `integrations/`
- the setup wizard must support a `core-only` profile

## Included So Far

- `bin/` — terminal CLI entrypoint
- `lib/` — command implementations and helpers
- `templates/` — core config templates
- `systemd/` — service templates
- `scripts/` — helper examples
- `docs/` — architecture and setup notes
- `integrations/` — optional integration examples
- `PUBLISHING_TODO.md` — remaining cleanup list before publication

## CLI Status

Current CLI entrypoint:

```bash
./bin/irondome --help
```

Currently working:

- English help output
- interactive `setup`
- `bridges`
- `outline`
- `status`
- `render`
- `install --root <path>`
- basic `doctor`

Still incomplete:

- full production-grade installer/apply flow
- richer doctor checks and troubleshooting output

## Intentionally Excluded

- real auth files
- real `ss://` keys
- runtime files from `/run`
- cookies / keyring / local GUI state
- frozen backup copies from `work/`
- live system-specific paths and secrets

## Status

This is a staging product skeleton, not the final public release.
