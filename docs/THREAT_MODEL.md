# Threat Model and Limitations

Read this before trusting the chain with anything that matters.

## What the chain is

```text
app -> [strict route] -> SOCKS 1080 -> Tor 9050 (obfs4 bridges) -> Outline/SS -> Internet
```

Two independent hops, in this order on purpose:

- **Tor first** hides your real IP from the Outline server. The Outline operator
  sees a Tor exit node, not you.
- **Outline second** hides the Tor exit from the destination. The destination
  sees a normal VPS IP, not a published Tor exit — which is what makes sites
  that block Tor usable.
- **obfs4 bridges** hide "this host speaks Tor" from your ISP and from DPI.

## What it protects against

| Adversary | Covered |
|---|---|
| ISP / national DPI reading your traffic | yes — obfs4 to an unlisted bridge |
| ISP knowing you use Tor | yes, as long as bridges stay unenumerated |
| Destination site learning your real IP | yes |
| Destination site blocking Tor exits | yes — it sees the Outline VPS |
| Outline/VPS operator learning your real IP | yes — they see a Tor exit |
| An app leaking around the tunnel | mostly — strict mode is fail-closed for the protected UID |

## What it does NOT protect against

This is the part that decides whether the setup is worth anything to you.

**Application-layer identity.** Logging into an account deanonymizes you
completely, regardless of routing. Cookies, browser fingerprint, canvas, fonts,
screen size, timezone, and WebRTC all survive the tunnel untouched. This project
routes packets; it does not make a browser anonymous. Use the Tor Browser for
browsing, not your daily browser through the proxy.

**A compromised VM or host.** Everything here runs as normal Linux services.
Root on the VM, or a keylogger on the Windows host, sees the plaintext before it
reaches the tunnel. There is no sandbox and no attempt at one.

**Global traffic correlation.** An adversary who observes both your uplink and
the Outline VPS uplink can correlate by timing and volume. Two hops do not fix
this; nothing at this layer does.

**A hostile Outline server.** It sees TLS metadata, timing, and every unencrypted
byte. It does not see your IP, but it does see your traffic pattern and, on
plain HTTP, content. Do not use a random public key for anything sensitive.

**Correlation across time.** The Outline exit IP is stable. Every request from
the same key is linkable, even if none of them is linkable to you.

**Traffic outside strict mode.** `open` mode allows direct egress by design.
Only the protected UID (and optionally root) is routed in strict mode — other
users on the same machine egress normally.

**Anything before the stack starts.** Boot-time traffic, DHCP, NTP, and system
updates that run before `iron-dome-start` go out directly. The cleanup service
handles leftover rules, not pre-start traffic.

**The host proxy listener.** `iron-windows-proxy` is unauthenticated. Its source
network is enforced by `socat range=`, but anyone on that network can use your
tunnel. Keep it on a host-only network.

## Known weak points in this implementation

- The lock is `iptables` OUTPUT-based plus policy routing. It is UID-scoped;
  a process running as another user is not covered.
- IPv6 is disabled rather than routed. Verify with `curl -6` that it actually
  fails.
- DNS goes through the transparent route in strict mode. In `open` mode it does
  not — check `/etc/resolv.conf` before assuming otherwise.
- `render` regenerates everything from `state/`; manual edits under
  `generated/` are lost on the next render.
- Tor over Shadowsocks adds latency on top of Tor's own. This is not a fast
  setup and is not meant to be.

## Verify, do not assume

```bash
./bin/irondome doctor
curl --socks5-hostname 127.0.0.1:1080 https://api.ipify.org   # Outline exit IP
curl -6 https://api64.ipify.org                                # must fail
```

If `doctor` reports `TOR 9050: OK` but `OUTLINE 1080: FAILED`, the chain is
broken and strict mode will fail closed — which is the intended behaviour.
