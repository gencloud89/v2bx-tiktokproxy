# Changelog

## v1.0.0 - 2026-06-30

Initial release.

### Added

- One-command V2bX installer based on official V2bX binary releases.
- TikTok/ByteDance residential HTTP proxy routing layer.
- Install-time prompt for proxy host, port, username, and password.
- Menu command `V2bX tiktok` to configure or replace TikTok proxy settings.
- Menu command `V2bX tiktok-status` to inspect recent TikTok routing and proxy connections.
- Menu command `V2bX update` to update the official V2bX binary and re-apply existing TikTok logic.
- Menu command `V2bX update-script` to update this manager layer from GitHub.
- `RouteConfigPath` and `OutboundConfigPath` patching for `/etc/V2bX/config.json`.
- `tiktok-residential` outbound generation in `/etc/V2bX/custom_outbound.json`.
- Expanded TikTok/ByteDance route list with `geosite:tiktok`, `geosite:bytedance`, and manual CDN fallback domains.
- TikTok/ByteDance UDP/443 blocking and global UDP/443 blocking to prevent QUIC/IP-only bypass.
- Daily `geosite.dat` and `geoip.dat` updater cron.
- Safe backups before applying TikTok config changes.

### Notes

- This release does not fork or modify the V2bX binary.
- Customer data, panel database data, subscription links, and node users are not modified by the installer.
