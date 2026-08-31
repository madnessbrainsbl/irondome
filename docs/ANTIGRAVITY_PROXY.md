# Antigravity Proxy

Optional integration. Antigravity rejects Google API requests when the active
Outline exit is in an unsupported country. This integration gives Antigravity a
separate egress without touching the core Outline route.

The default is **direct mode**: no app-wide proxy and no `/etc/hosts` redirect
for Google hosts. An app-wide `http.proxy` breaks Electron webviews and leaks
proxy settings into child processes, so do not enable one unless you mean to.

## User Wrapper

```bash
install -m 0755 scripts/smart-antigravity.example.sh ~/.local/bin/smart-antigravity
```

Point the desktop launcher at `~/.local/bin/smart-antigravity`, and the
`antigravity://` URL handler at `~/.local/bin/smart-antigravity --open-url %U`.

## Direct Mode (default)

```bash
install -d -m 0700 ~/.config/iron-dome
install -m 0600 integrations/antigravity/antigravity-proxy.env.example \
  ~/.config/iron-dome/antigravity-proxy.env
```

```bash
IRON_ANTIGRAVITY_PROXY=
IRON_ANTIGRAVITY_NO_PROXY=localhost,127.0.0.1,127.0.0.0/8,::1
IRON_ANTIGRAVITY_EXPORT_PROXY_ENV=no
```

Direct mode requires `/etc/hosts` to contain no `IRON DOME GOOGLE HOSTS` block.
`iron-dome-start` clears that block on every start.

## Fallback: Antigravity-only Tor

Only when direct mode cannot reach a supported region. This runs a second Tor
instance on `9150` plus a Privoxy on `8120`, used by Antigravity alone.

The `.conf` and `torrc` files carry a `__HOME__` placeholder; systemd user units
use `%h` and need no substitution:

```bash
install -d -m 0700 ~/.config/iron-dome ~/.local/state/iron-dome
for f in antigravity-privoxy.conf antigravity-torrc; do
  sed "s|__HOME__|$HOME|g" "integrations/antigravity/$f.example" > ~/.config/iron-dome/$f
done
install -m 0644 integrations/antigravity/antigravity-tor.service.example \
  ~/.config/systemd/user/antigravity-tor.service
install -m 0644 integrations/antigravity/antigravity-tor-privoxy.service.example \
  ~/.config/systemd/user/antigravity-tor-privoxy.service
systemctl --user daemon-reload
systemctl --user enable --now antigravity-tor.service antigravity-tor-privoxy.service
```

Add your obfs4 bridges to `~/.config/iron-dome/antigravity-torrc`, then point the
wrapper at the per-app proxy:

```bash
IRON_ANTIGRAVITY_PROXY=http://127.0.0.1:8120
IRON_ANTIGRAVITY_NO_PROXY=localhost,127.0.0.1,127.0.0.0/8,::1
IRON_ANTIGRAVITY_EXPORT_PROXY_ENV=no
```

`socks5h://127.0.0.1:9150` is also accepted.

Verify the path before launching:

```bash
curl --socks5-hostname 127.0.0.1:9150 https://oauth2.googleapis.com/.well-known/openid-configuration
```

Keep Google API hosts out of `NO_PROXY`, or the app bypasses this proxy and hits
`User location is not supported for the API use` again.

## Limitation

The wrapper only wires Antigravity to a per-app proxy. It does not provide a
supported-region exit itself — a Tor exit in an unsupported country fails the
same way. Supply an egress you know is supported.
