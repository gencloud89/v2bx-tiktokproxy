#!/usr/bin/env sh
set -eu

V2BX_DIR="${V2BX_DIR:-/etc/V2bX}"
SERVICE_NAME="${SERVICE_NAME:-V2bX}"
TMP_DIR="$(mktemp -d)"
BACKUP_DIR="${BACKUP_DIR:-/root/v2bx-rules-dat-backup}"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BACKUP_DIR"

download() {
    name="$1"
    url="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/$name"
    curl -fsSL --connect-timeout 20 --retry 3 --retry-delay 5 "$url" -o "$TMP_DIR/$name"
    test -s "$TMP_DIR/$name"
}

download geosite.dat
download geoip.dat

changed=0
for name in geosite.dat geoip.dat; do
    target="$V2BX_DIR/$name"
    if [ ! -f "$target" ] || ! cmp -s "$TMP_DIR/$name" "$target"; then
        if [ -f "$target" ]; then
            cp -a "$target" "$BACKUP_DIR/$name.$(date +%F_%H%M%S)"
        fi
        cp -a "$TMP_DIR/$name" "$target"
        changed=1
    fi
done

if [ "$changed" -eq 1 ]; then
    systemctl restart "$SERVICE_NAME"
    echo "rules dat updated and $SERVICE_NAME restarted"
else
    echo "rules dat already current"
fi
