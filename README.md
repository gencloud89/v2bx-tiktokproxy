# v2bx-tiktokproxy

One-command V2bX installer with built-in TikTok/ByteDance residential proxy routing.

This project keeps the official V2bX binary from `wyx2685/V2bX`, then adds a dedicated configuration layer for TikTok:

- asks for rotating/residential HTTP proxy host, port, username, and password during install;
- creates `tiktok-residential` outbound;
- routes TikTok and ByteDance domains to the residential proxy;
- blocks UDP/443 so TikTok falls back from QUIC/IP-only traffic to TCP that can pass through the HTTP proxy;
- installs a menu with TikTok-specific options;
- installs daily `geosite.dat` and `geoip.dat` update cron;
- keeps TikTok proxy logic when updating V2bX.

## One-Line Install

```bash
wget -N https://raw.githubusercontent.com/gencloud89/v2bx-tiktokproxy/main/install.sh && bash install.sh
```

Install a specific official V2bX version:

```bash
wget -N https://raw.githubusercontent.com/gencloud89/v2bx-tiktokproxy/main/install.sh && bash install.sh v0.4.0
```

## Menu

After installation:

```bash
V2bX
```

Useful commands:

```bash
V2bX tiktok          # configure proxy and apply TikTok routing
V2bX tiktok-apply    # re-apply current TikTok routing without changing proxy
V2bX tiktok-status   # check recent TikTok detours and proxy connections
V2bX update-rules    # update geosite.dat and geoip.dat
V2bX update          # update official V2bX binary and preserve TikTok logic
V2bX update-script   # update this installer/menu layer from GitHub
```

## Files Installed On Server

- `/etc/V2bX/config.json`
- `/etc/V2bX/route.json`
- `/etc/V2bX/custom_outbound.json`
- `/etc/V2bX/tiktok-proxy.env` with mode `600`
- `/usr/local/V2bX/update-rules-dat.sh`
- `/etc/cron.d/v2bx-rules-dat`
- `/usr/bin/V2bX`
- `/usr/bin/v2bx`

## TikTok Routing Logic

Rule order:

1. block private IP ranges;
2. block BitTorrent;
3. block TikTok/ByteDance UDP/443;
4. route TikTok/ByteDance domains to `tiktok-residential`;
5. block global UDP/443 to prevent QUIC/IP-only bypass;
6. route Netflix to IPv6 outbound;
7. route all remaining traffic to IPv4 outbound.

The route contains `geosite:tiktok`, `geosite:bytedance`, and a manual fallback list for TikTok/ByteDance CDN domains such as `ibyteimg.com`, `byteimg.com`, `tiktokcdn.com`, `tiktokv.com`, `amemv.com`, and related domains.

## Auto Update

The installer creates:

```cron
17 4 * * * root /usr/local/V2bX/update-rules-dat.sh >> /var/log/v2bx-rules-dat.log 2>&1
```

The updater downloads the latest `geosite.dat` and `geoip.dat` from Loyalsoldier releases and restarts V2bX only if files changed.

## Verify TikTok Traffic

```bash
V2bX tiktok-status
journalctl -u V2bX --since "2 minutes ago" --no-pager -l | grep -Ei 'tiktok|ibyte|byteimg|tiktok-residential|8779|Limited'
ss -tnp | grep ':8779'
```

Good signs:

```text
taking detour [tiktok-residential]
dialing TCP to tcp:<proxy-host>:<proxy-port>
accepted ... -> tiktok-residential
```

## Notes

- Proxy credentials are saved locally on the node in `/etc/V2bX/tiktok-proxy.env` and are not printed by the docs.
- If TikTok still fails while detours are visible, check `Limited ... by conn or ip` and proxy quality/region.
- Global UDP/443 blocking is intentional for TikTok compatibility, but it can reduce QUIC performance for other applications.
