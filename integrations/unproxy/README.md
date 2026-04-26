# unproxy Integration

This integration is optional.

`unproxy` is a generic local gateway profile that can be placed on top of the core anonymity stack.
It is not part of the core itself.

Typical optional layers:

- local HTTP proxy on `127.0.0.1:8119`
- local gateway on `127.0.0.1:8317`
- optional loopback forwarding for external auth/API domains if required
