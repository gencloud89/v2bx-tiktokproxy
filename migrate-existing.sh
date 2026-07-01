#!/usr/bin/env bash
set -euo pipefail

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

RAW_BASE='https://raw.githubusercontent.com/gencloud89/v2bx-tiktokproxy/main'
V2BX_DIR='/usr/local/V2bX'
ETC_DIR='/etc/V2bX'
ENV_FILE="$ETC_DIR/tiktok-proxy.env"
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
    echo -e "${red}Không nhận diện được hệ điều hành.${plain}"
    exit 1
fi

arch=$(uname -m)
case "$arch" in
    x86_64|x64|amd64) arch='64' ;;
    aarch64|arm64) arch='arm64-v8a' ;;
    s390x) arch='s390x' ;;
    *) arch='64'; echo -e "${yellow}Không rõ kiến trúc CPU, dùng gói amd64.${plain}" ;;
esac

load_github_token() {
    if [[ -f "$GITHUB_ENV_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$GITHUB_ENV_FILE"
    fi
    : "${GITHUB_TOKEN:=}"
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

ensure_deps() {
    if command -v curl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1; then
        return 0
    fi
    echo -e "${yellow}Cài công cụ cần thiết: curl, unzip, python3...${plain}"
    if [[ "$release" == 'centos' ]]; then
        yum install -y wget curl unzip tar ca-certificates python3 >/dev/null
    elif [[ "$release" == 'alpine' ]]; then
        apk add --no-cache wget curl unzip tar ca-certificates python3 openrc >/dev/null
    elif [[ "$release" == 'debian' || "$release" == 'ubuntu' ]]; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y wget curl unzip tar ca-certificates python3 >/dev/null
    elif [[ "$release" == 'arch' ]]; then
        pacman -Sy --noconfirm >/dev/null 2>&1
        pacman -S --noconfirm --needed wget curl unzip tar ca-certificates python >/dev/null
    fi
}

check_space() {
    local avail
    avail=$(df -Pm / | awk 'NR==2 {print $4}')
    if [[ "${avail:-0}" -lt 80 ]]; then
        echo -e "${red}Ổ / còn dưới 80MB trống.${plain}"
        echo "Hãy dọn log trước, ví dụ:"
        echo "  : > /var/log/syslog; : > /var/log/daemon.log; : > /var/log/syslog.1; : > /var/log/daemon.log.1"
        echo "  journalctl --vacuum-size=100M"
        exit 1
    fi
}

backup_current() {
    BACKUP_DIR="/root/v2bx-migrate-tiktokproxy-$(date +%F_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp -a "$ETC_DIR" "$BACKUP_DIR/etc-V2bX" 2>/dev/null || true
    cp -a "$V2BX_DIR/V2bX" "$BACKUP_DIR/V2bX-binary" 2>/dev/null || true
    cp -a /usr/bin/V2bX "$BACKUP_DIR/V2bX-menu" 2>/dev/null || true
    cp -a /etc/systemd/system/V2bX.service "$BACKUP_DIR/V2bX.service" 2>/dev/null || true
    echo -e "${green}Backup:${plain} $BACKUP_DIR"
}

assert_existing_v2bx() {
    if [[ ! -f "$ETC_DIR/config.json" ]]; then
        echo -e "${red}Không thấy $ETC_DIR/config.json.${plain}"
        echo "Script migrate chỉ dùng cho node đã cài V2bX. Nếu là VPS mới, dùng install.sh."
        exit 1
    fi
    if [[ ! -x "$V2BX_DIR/V2bX" ]]; then
        echo -e "${yellow}Không thấy binary $V2BX_DIR/V2bX hoặc chưa có quyền chạy.${plain}"
        read -rp "Bạn có muốn tải binary V2bX mới nhất nhưng vẫn giữ config.json cũ không? [y/N]: " ans
        [[ "$ans" == "y" || "$ans" == "Y" ]] || exit 1
        update_binary
    fi
}

install_manager() {
    mkdir -p "$ETC_DIR" "$V2BX_DIR"
    fetch_url "$RAW_BASE/bin/V2bX.sh" /usr/bin/V2bX
    chmod +x /usr/bin/V2bX
    ln -sf /usr/bin/V2bX /usr/bin/v2bx
    fetch_url "$RAW_BASE/install.sh" "$V2BX_DIR/install-tiktokproxy.sh" || true
}

ensure_service() {
    if [[ "$release" == 'alpine' ]]; then
        if [[ ! -f /etc/init.d/V2bX ]]; then
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
            rc-update add V2bX default || true
        fi
    else
        if [[ ! -f /etc/systemd/system/V2bX.service ]]; then
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
        fi
        systemctl daemon-reload
        systemctl enable V2bX >/dev/null 2>&1 || true
    fi
}

update_binary() {
    local version zip_url backup_bin
    mkdir -p "$V2BX_DIR"
    version=$(curl -fsSL 'https://api.github.com/repos/wyx2685/V2bX/releases/latest' | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [[ -z "$version" ]] && echo -e "${red}Không lấy được phiên bản V2bX mới nhất.${plain}" && exit 1
    zip_url="https://github.com/wyx2685/V2bX/releases/download/${version}/V2bX-linux-${arch}.zip"
    backup_bin="/root/v2bx-binary-before-migrate-$(date +%F_%H%M%S)"
    mkdir -p "$backup_bin"
    cp -a "$V2BX_DIR/V2bX" "$backup_bin/V2bX" 2>/dev/null || true
    echo -e "${yellow}Tải V2bX ${version}, chỉ thay binary/dat, không ghi đè config.json.${plain}"
    curl -fL --retry 3 "$zip_url" -o /tmp/V2bX-linux.zip
    unzip -o /tmp/V2bX-linux.zip -d "$V2BX_DIR" >/dev/null
    rm -f /tmp/V2bX-linux.zip
    chmod +x "$V2BX_DIR/V2bX"
    cp -n "$V2BX_DIR/geoip.dat" "$ETC_DIR/geoip.dat" 2>/dev/null || true
    cp -n "$V2BX_DIR/geosite.dat" "$ETC_DIR/geosite.dat" 2>/dev/null || true
}

write_proxy_from_env() {
    if [[ -z "${TIKTOK_PROXY:-}" ]]; then
        return 1
    fi
    local host port
    if [[ "$TIKTOK_PROXY" == *:* ]]; then
        host="${TIKTOK_PROXY%:*}"
        port="${TIKTOK_PROXY##*:}"
    else
        echo -e "${red}TIKTOK_PROXY phải có dạng host:port.${plain}"
        exit 1
    fi
    [[ "$port" =~ ^[0-9]+$ ]] || { echo -e "${red}Proxy port phải là số.${plain}"; exit 1; }
    umask 077
    {
        printf 'TIKTOK_PROXY_HOST=%q\n' "$host"
        printf 'TIKTOK_PROXY_PORT=%q\n' "$port"
        printf 'TIKTOK_PROXY_USER=%q\n' "${TIKTOK_PROXY_USER:-}"
        printf 'TIKTOK_PROXY_PASS=%q\n' "${TIKTOK_PROXY_PASS:-}"
    } > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    return 0
}

main() {
    echo -e "${green}Chuyển node V2bX cũ sang V2bX TikTokProxy, giữ nguyên cấu hình server.${plain}"
    ensure_deps
    check_space
    assert_existing_v2bx
    backup_current
    install_manager
    ensure_service

    echo
    update_ans="${UPDATE_V2BX:-}"
    if [[ -z "$update_ans" ]]; then
        read -rp "Bạn có muốn cập nhật binary V2bX lên bản mới nhất không? Giữ nguyên config.json. [y/N]: " update_ans
    fi
    if [[ "$update_ans" == "y" || "$update_ans" == "Y" ]]; then
        update_binary
    fi

    if write_proxy_from_env; then
        echo -e "${green}Đã nhận proxy từ biến môi trường.${plain}"
        /usr/bin/V2bX tiktok-apply
    elif [[ -f "$ENV_FILE" ]]; then
        echo -e "${yellow}Đã có proxy TikTok cũ, áp dụng lại.${plain}"
        /usr/bin/V2bX tiktok-apply
    else
        echo -e "${yellow}Chưa có proxy TikTok, vui lòng nhập proxy.${plain}"
        /usr/bin/V2bX tiktok
    fi

    echo
    echo -e "${green}Hoàn tất migrate.${plain}"
    echo "Backup: $BACKUP_DIR"
    echo "Đổi proxy sau này: V2bX tiktok hoặc mở menu V2bX chọn mục 18"
    echo "Kiểm tra: V2bX tiktok-status"
}

main "$@"
