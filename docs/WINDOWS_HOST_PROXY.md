# Windows Host Proxy

Iron Dome can expose the local HTTP proxy to the host OS or a trusted VM/LAN network. This is for cases where the browser or app runs on Windows, while the Iron Dome chain runs inside Kali/Linux.

## Flow

```text
Windows browser
  -> Kali VM:18119
  -> Privoxy 127.0.0.1:8119
  -> Outline SOCKS 127.0.0.1:1080
  -> Tor 127.0.0.1:9050
  -> Internet
```

## Configuration

Enable it during `./bin/irondome setup`, or set these values in `state/irondome.env` before rendering:

```bash
WINDOWS_PROXY_ENABLED="yes"
WINDOWS_PROXY_BIND="0.0.0.0"
WINDOWS_PROXY_PORT="18119"
WINDOWS_PROXY_NET="192.168.98.0/24"
```

`WINDOWS_PROXY_NET` must be the trusted host-only/VM network that contains the Windows client. The generated helper passes it to `socat` as `range=`, so connections from outside that network are dropped.

That is a source-address filter, not authentication: any host on that network can use your Tor → Outline tunnel. Do not point this at an untrusted LAN or a bridged/public network.

Render and install:

```bash
./bin/irondome render
sudo ./bin/irondome install
sudo iron-dome-start
```

The generated helper is installed as `iron-windows-proxy`. It forwards `0.0.0.0:18119` to `127.0.0.1:8119` by default.

## Windows Setup

Replace `192.168.98.133` with the Kali VM IP on the host-only/VM network:

```powershell
$proxy = "192.168.98.133:18119"
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyEnable -Value 1
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyServer -Value "http=$proxy;https=$proxy"
```

Disable it later with:

```powershell
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyEnable -Value 0
```

## Verification

From Kali:

```bash
curl -x http://127.0.0.1:18119 -sS https://api.ipify.org
curl -x http://127.0.0.1:8119 -sS https://api.ipify.org
curl --socks5-hostname 127.0.0.1:1080 -sS https://api.ipify.org
```

All three should return the same protected Outline egress IP.

From Windows, open `https://api.ipify.org` in the configured browser. It should match the Kali proxy result, not the real ISP IP.

## Strict Mode

Strict mode stays fail-closed. The rendered lock helper only permits TCP replies from the configured proxy source port back to `WINDOWS_PROXY_NET`; other protected-user/root traffic is still routed through `iron0` or rejected.

`sudo iron-dome-stop` stops the stack and stops `iron-windows-proxy`.
