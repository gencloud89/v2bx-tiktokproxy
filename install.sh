#!/usr/bin/env bash
set -euo pipefail

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

REPO='gencloud89/v2bx-tiktokproxy'
RAW_BASE='https://raw.githubusercontent.com/gencloud89/v2bx-tiktokproxy/main'
V2BX_DIR='/usr/local/V2bX'
ETC_DIR='/etc/V2bX'
GITHUB_ENV_FILE="$ETC_DIR/tiktokproxy-github.env"

[[ $EUID -ne 0 ]] && echo -e "${red}Lỗi:${plain} vui lòng chạy bằng root." && exit 1

release=''
if [[ -f /etc/redhat-release ]]; then
    release='centos'
elif grep -Eqi 'alpine' /etc/issue 2>/dev/null; then
    release='alpine'
elif grep -Eqi 'debian' /etc/issue 2>/dev/null || grep -Eqi 'debian' /proc/version 2>/dev/null; then
    release='debian'
elif grep -Eqi 'ubuntu' /etc/issue 2>/dev/null || grep -Eqi 'ubuntu' /proc/version 2>/dev/null; then
    release='ubuntu'
elif grep -Eqi 'centos|red hat|redhat|rocky|alma|oracle linux' /etc/issue 2>/dev/null || grep -Eqi 'centos|red hat|redhat|rocky|alma|oracle linux' /proc/version 2>/dev/null; then
    release='centos'
elif grep -Eqi 'arch' /proc/version 2>/dev/null; then
    release='arch'
else
    echo -e "${red}Unsupported OS.${plain}"
    exit 1
fi


load_github_token() {
    if [[ -f "$GITHUB_ENV_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$GITHUB_ENV_FILE"
    fi
    : "${GITHUB_TOKEN:=}"
}

save_github_token() {
    mkdir -p "$ETC_DIR"
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        umask 077
        printf 'GITHUB_TOKEN=%q\n' "$GITHUB_TOKEN" > "$GITHUB_ENV_FILE"
        chmod 600 "$GITHUB_ENV_FILE"
    fi
}

fetch_url() {
    local url="$1" out="$2"
    load_github_token
    if [[ -n "$GITHUB_TOKEN" ]]; then
        curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" "$url" -o "$out"
    else
        curl -fsSL "$url" -o "$out"
    fi
}

arch=$(uname -m)
case "$arch" in
    x86_64|x64|amd64) arch='64' ;;
    aarch64|arm64) arch='arm64-v8a' ;;
    s390x) arch='s390x' ;;
    *) arch='64'; echo -e "${yellow}Unknown arch, using 64.${plain}" ;;
esac

install_base() {
    if [[ "$release" == 'centos' ]]; then
        yum install -y epel-release wget curl unzip tar crontabs socat ca-certificates python3 >/dev/null 2>&1 || yum install -y wget curl unzip tar crontabs socat ca-certificates python3
        update-ca-trust force-enable >/dev/null 2>&1 || true
    elif [[ "$release" == 'alpine' ]]; then
        apk add --no-cache wget curl unzip tar socat ca-certificates python3 openrc >/dev/null
        update-ca-certificates >/dev/null 2>&1 || true
    elif [[ "$release" == 'debian' || "$release" == 'ubuntu' ]]; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y wget curl unzip tar cron socat ca-certificates python3 >/dev/null
        update-ca-certificates >/dev/null 2>&1 || true
    elif [[ "$release" == 'arch' ]]; then
        pacman -Sy --noconfirm >/dev/null 2>&1
        pacman -S --noconfirm --needed wget curl unzip tar cronie socat ca-certificates python >/dev/null
    fi
}

install_v2bx_binary() {
    local version zip_url
    mkdir -p "$V2BX_DIR" "$ETC_DIR"
    version="${1:-}"
    if [[ -z "$version" ]]; then
        version=$(curl -fsSL 'https://api.github.com/repos/wyx2685/V2bX/releases/latest' | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    fi
    [[ -z "$version" ]] && echo -e "${red}Cannot detect V2bX latest version.${plain}" && exit 1
    zip_url="https://github.com/wyx2685/V2bX/releases/download/${version}/V2bX-linux-${arch}.zip"
    echo -e "${green}Installing V2bX ${version} (${arch})${plain}"
    curl -fL --retry 3 "$zip_url" -o /tmp/V2bX-linux.zip
    if [[ -f "$V2BX_DIR/V2bX" ]]; then
        local backup_dir
        backup_dir="/root/v2bx-binary-backup-$(date +%F_%H%M%S)"
        mkdir -p "$backup_dir"
        cp -a "$V2BX_DIR/V2bX" "$backup_dir/V2bX" 2>/dev/null || true
    fi
    unzip -o /tmp/V2bX-linux.zip -d "$V2BX_DIR" >/dev/null
    rm -f /tmp/V2bX-linux.zip
    chmod +x "$V2BX_DIR/V2bX"
    cp -n "$V2BX_DIR/geoip.dat" "$ETC_DIR/geoip.dat" 2>/dev/null || true
    cp -n "$V2BX_DIR/geosite.dat" "$ETC_DIR/geosite.dat" 2>/dev/null || true
    cp -n "$V2BX_DIR/config.json" "$ETC_DIR/config.json" 2>/dev/null || true
    cp -n "$V2BX_DIR/dns.json" "$ETC_DIR/dns.json" 2>/dev/null || true
    cp -n "$V2BX_DIR/custom_inbound.json" "$ETC_DIR/custom_inbound.json" 2>/dev/null || true
}

install_service() {
    if [[ "$release" == 'alpine' ]]; then
        cat > /etc/init.d/V2bX <<'EOF_OPENRC'
#!/sbin/openrc-run
name="V2bX"
description="V2bX"
command="/usr/local/V2bX/V2bX"
command_args="server"
command_user="root"
pidfile="/run/V2bX.pid"
command_background="yes"
depend() { need net; }
EOF_OPENRC
        chmod +x /etc/init.d/V2bX
        rc-update add V2bX default
    else
        cat > /etc/systemd/system/V2bX.service <<'EOF_SERVICE'
[Unit]
Description=V2bX Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=/usr/local/V2bX/
ExecStart=/usr/local/V2bX/V2bX server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF_SERVICE
        systemctl daemon-reload
        systemctl enable V2bX >/dev/null 2>&1 || true
    fi
}

install_manager() {
    save_github_token
    fetch_url "$RAW_BASE/bin/V2bX.sh" /usr/bin/V2bX
    chmod +x /usr/bin/V2bX
    ln -sf /usr/bin/V2bX /usr/bin/v2bx
    fetch_url "$RAW_BASE/install.sh" "$V2BX_DIR/install-tiktokproxy.sh" || true
}

quick_config_wizard() {
    fetch_url "$RAW_BASE/templates/quick-config.py" /tmp/v2bx-quick-config.py
    python3 /tmp/v2bx-quick-config.py
    rm -f /tmp/v2bx-quick-config.py
}

main() {
    load_github_token
    save_github_token
    echo -e "${green}Bắt đầu cài V2bX TikTokProxy${plain}"
    install_base
    install_v2bx_binary "${1:-}"
    install_service
    install_manager
    echo
    read -rp "Bạn có muốn thiết lập server config nhanh không? [y/n]: " setup_server_config
    if [[ "$setup_server_config" == "y" || "$setup_server_config" == "Y" ]]; then
        quick_config_wizard
    else
        echo -e "${yellow}Bỏ qua thiết lập server config nhanh, tiếp tục cài đặt bình thường.${plain}"
    fi
    if [[ -f "$ETC_DIR/tiktok-proxy.env" ]]; then
        echo -e "${yellow}Đã có cấu hình proxy TikTok, tự áp dụng lại logic cũ.${plain}"
        /usr/bin/V2bX tiktok-apply
    else
        echo
        read -rp "Bạn có muốn cài proxy TikTok không? [y/n]: " install_tiktok_proxy
        if [[ "$install_tiktok_proxy" == "y" || "$install_tiktok_proxy" == "Y" ]]; then
            echo -e "${yellow}Bây giờ cấu hình proxy xoay/cư dân cho TikTok.${plain}"
            /usr/bin/V2bX tiktok
        else
            echo -e "${yellow}Bỏ qua cấu hình proxy TikTok. Bạn có thể cấu hình sau bằng mục 18 trong menu hoặc lệnh: V2bX tiktok${plain}"
            if [[ "$release" == 'alpine' ]]; then
                service V2bX start || true
            else
                systemctl start V2bX || true
            fi
        fi
    fi
    echo -e "${green}Cài đặt hoàn tất.${plain}"
    echo "Lệnh sử dụng:"
    echo "  V2bX                Hiển thị menu"
    echo "  V2bX tiktok         Cấu hình proxy TikTok"
    echo "  V2bX tiktok-status  Kiểm tra route TikTok"
    echo "  V2bX update         Cập nhật V2bX và giữ logic TikTok"
    echo "  V2bX update-script  Cập nhật script quản lý"
}

main "$@"
