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

[[ $EUID -ne 0 ]] && echo -e "${red}Error:${plain} please run as root." && exit 1

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
    curl -fsSL "$RAW_BASE/bin/V2bX.sh" -o /usr/bin/V2bX
    chmod +x /usr/bin/V2bX
    ln -sf /usr/bin/V2bX /usr/bin/v2bx
    curl -fsSL "$RAW_BASE/install.sh" -o "$V2BX_DIR/install-tiktokproxy.sh" || true
}

main() {
    echo -e "${green}Start installing V2bX TikTokProxy${plain}"
    install_base
    install_v2bx_binary "${1:-}"
    install_service
    install_manager
    echo -e "${yellow}Now configure TikTok residential proxy.${plain}"
    /usr/bin/V2bX tiktok
    echo -e "${green}Install complete.${plain}"
    echo "Commands:"
    echo "  V2bX                Show menu"
    echo "  V2bX tiktok         Configure TikTok proxy"
    echo "  V2bX tiktok-status  Check TikTok routing"
    echo "  V2bX update         Update V2bX binary and preserve TikTok logic"
    echo "  V2bX update-script  Update this manager script"
}

main "$@"
