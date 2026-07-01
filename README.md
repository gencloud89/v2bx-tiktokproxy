# v2bx-tiktokproxy

Bản cài V2bX riêng cho nhu cầu dùng TikTok qua proxy xoay/cư dân.

Repo này **không sửa binary V2bX gốc**. Script vẫn tải V2bX chính thức từ release của `wyx2685/V2bX`, sau đó tự cấu hình thêm route/outbound để TikTok và ByteDance đi qua proxy cư dân.

## Cài đặt một lệnh

Chạy lệnh sau trên VPS bằng user `root`:

```bash
wget -N https://raw.githubusercontent.com/gencloud89/v2bx-tiktokproxy/main/install.sh && bash install.sh
```

Sau khi chạy, nếu là cài mới script sẽ hỏi:

```text
Bạn có muốn cài proxy TikTok không? [y/n]
```

Nếu chọn `y`, script sẽ hỏi tiếp:

- proxy xoay/cư dân dạng `host:port`;
- username proxy, có thể bỏ trống nếu proxy không cần auth;
- password proxy, chỉ hỏi khi có username.

Nếu chọn `n`, V2bX vẫn được cài bình thường. Bạn có thể cấu hình proxy TikTok sau bằng mục `18` trong menu hoặc lệnh `V2bX tiktok`.

## Chuyển node V2bX cũ sang bản TikTokProxy

Dùng lệnh này cho VPS **đã có V2bX đang chạy** và cần giữ nguyên cấu hình server/node hiện tại:

```bash
wget -N https://raw.githubusercontent.com/gencloud89/v2bx-tiktokproxy/main/migrate-existing.sh && bash migrate-existing.sh
```

Script migrate sẽ:

- kiểm tra node đã có `/etc/V2bX/config.json`;
- backup `/etc/V2bX`, binary V2bX, menu cũ và service vào `/root/v2bx-migrate-tiktokproxy-*`;
- cài menu quản lý mới `/usr/bin/V2bX` và `/usr/bin/v2bx`;
- không ghi đè `config.json`, token panel, node id, node type, API host, hoặc cấu hình server hiện có;
- hỏi có muốn cập nhật binary V2bX mới nhất không, mặc định là **không**;
- thêm `/etc/V2bX/route.json`, `/etc/V2bX/custom_outbound.json`, `/etc/V2bX/tiktok-proxy.env`;
- tự thêm `RouteConfigPath` và `OutboundConfigPath` vào config cũ;
- restart V2bX và giữ logic TikTok proxy.

Chạy nhanh không cần hỏi proxy:

```bash
TIKTOK_PROXY='s14.proxyxoay.net:8837' \
TIKTOK_PROXY_USER='sennet898' \
TIKTOK_PROXY_PASS='sennet898' \
UPDATE_V2BX=n \
bash <(curl -fsSL https://raw.githubusercontent.com/gencloud89/v2bx-tiktokproxy/main/migrate-existing.sh)
```

Nếu muốn đồng thời cập nhật binary V2bX lên bản mới nhất nhưng vẫn giữ `config.json` cũ:

```bash
UPDATE_V2BX=y bash migrate-existing.sh
```

## Menu quản lý

Sau khi cài xong, chạy:

```bash
V2bX
```

Menu giữ kiểu V2bX gốc, đã Việt hoá và thêm mục:

```text
18. Cấu hình proxy TikTok
```

Các lệnh nhanh:

```bash
V2bX tiktok          # cấu hình lại proxy TikTok
V2bX tiktok-apply    # áp dụng lại route/outbound TikTok bằng proxy đã lưu
V2bX tiktok-status   # xem log route TikTok và số kết nối proxy
V2bX update-rules    # cập nhật geosite.dat/geoip.dat
V2bX update          # cập nhật V2bX bản mới nhất và giữ logic TikTok
V2bX update-script   # cập nhật script menu từ repo private
```

## Cơ chế TikTok proxy

Script tự tạo/cập nhật các file:

- `/etc/V2bX/config.json`
- `/etc/V2bX/route.json`
- `/etc/V2bX/custom_outbound.json`
- `/etc/V2bX/tiktok-proxy.env`
- `/usr/local/V2bX/update-rules-dat.sh`
- `/etc/cron.d/v2bx-rules-dat`
- `/usr/bin/V2bX`
- `/usr/bin/v2bx`

Logic route:

1. Chặn IP private.
2. Chặn BitTorrent.
3. Chặn TikTok/ByteDance UDP/443.
4. Đưa TikTok/ByteDance TCP/domain qua outbound `tiktok-residential`.
5. Chặn UDP/443 tổng quát để tránh QUIC/IP-only đi lệch proxy.
6. Netflix đi IPv6 outbound.
7. Traffic còn lại đi IPv4 outbound.

Danh sách TikTok gồm:

- `geosite:tiktok`
- `geosite:bytedance`
- các domain CDN/media fallback như `ibyteimg.com`, `byteimg.com`, `tiktokcdn.com`, `tiktokv.com`, `amemv.com`, `ibytedtos.com`, `bytetos.com`, `pstatp.com`, `snssdk.com` và các domain liên quan.

## Cơ chế cập nhật thường xuyên

Script cài cron:

```cron
17 4 * * * root /usr/local/V2bX/update-rules-dat.sh >> /var/log/v2bx-rules-dat.log 2>&1
```

Mỗi ngày cron sẽ tải `geosite.dat` và `geoip.dat` mới từ Loyalsoldier release. Nếu file thay đổi, V2bX sẽ tự restart.

Khi chọn cập nhật V2bX trong menu hoặc chạy:

```bash
V2bX update
```

script sẽ tải binary V2bX mới nhất, sau đó tự áp dụng lại route/outbound TikTok bằng proxy đã lưu. Như vậy update không làm mất logic TikTok cũ.

## Kiểm tra TikTok có đi proxy không

```bash
V2bX tiktok-status
```

Hoặc kiểm tra thủ công:

```bash
journalctl -u V2bX --since "2 minutes ago" --no-pager -l | grep -Ei 'tiktok|ibyte|byteimg|tiktok-residential|8779|Limited'
ss -tnp | grep ':8779'
```

Dấu hiệu đúng:

```text
taking detour [tiktok-residential]
dialing TCP to tcp:<proxy-host>:<proxy-port>
accepted ... -> tiktok-residential
```

Nếu vẫn không dùng được TikTok dù đã thấy log đi proxy, cần kiểm tra thêm:

- proxy cư dân có bị TikTok chặn IP/region không;
- tốc độ và độ ổn định của proxy;
- log `Limited ... by conn or ip`, nghĩa là bị giới hạn kết nối/IP trước khi route ra proxy.

## Ghi chú bảo mật

- Không đưa proxy password hoặc API key vào README/release note.
- Proxy lưu tại `/etc/V2bX/tiktok-proxy.env`, quyền `600`.
