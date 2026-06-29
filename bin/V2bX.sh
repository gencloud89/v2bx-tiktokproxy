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
ENV_FILE="$ETC_DIR/tiktok-proxy.env"
LOG_FILE='/var/log/v2bx-rules-dat.log'

need_root() {
    [[ $EUID -ne 0 ]] && echo -e "${red}Please run as root.${plain}" && exit 1
}

service_cmd() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl "$@" V2bX
    else
        service V2bX "$@"
    fi
}

restart_v2bx() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart V2bX
    else
        service V2bX restart
    fi
}

status_v2bx() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl status V2bX --no-pager -l || true
    else
        service V2bX status || true
    fi
}

json_escape() {
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))'
}

parse_host_port() {
    local input="$1"
    if [[ "$input" == *:* ]]; then
        TIKTOK_PROXY_HOST="${input%:*}"
        TIKTOK_PROXY_PORT="${input##*:}"
    else
        TIKTOK_PROXY_HOST="$input"
        read -rp "Proxy port: " TIKTOK_PROXY_PORT
    fi
    if ! [[ "$TIKTOK_PROXY_PORT" =~ ^[0-9]+$ ]]; then
        echo -e "${red}Proxy port must be a number.${plain}"
        exit 1
    fi
}

save_proxy_env() {
    mkdir -p "$ETC_DIR"
    umask 077
    {
        printf 'TIKTOK_PROXY_HOST=%q\n' "$TIKTOK_PROXY_HOST"
        printf 'TIKTOK_PROXY_PORT=%q\n' "$TIKTOK_PROXY_PORT"
        printf 'TIKTOK_PROXY_USER=%q\n' "$TIKTOK_PROXY_USER"
        printf 'TIKTOK_PROXY_PASS=%q\n' "$TIKTOK_PROXY_PASS"
    } > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
}

load_proxy_env() {
    if [[ -f "$ENV_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$ENV_FILE"
    fi
    : "${TIKTOK_PROXY_HOST:=}"
    : "${TIKTOK_PROXY_PORT:=}"
    : "${TIKTOK_PROXY_USER:=}"
    : "${TIKTOK_PROXY_PASS:=}"
}

ask_proxy() {
    load_proxy_env
    echo -e "${yellow}TikTok residential/rotating HTTP proxy config${plain}"
    [[ -n "$TIKTOK_PROXY_HOST" ]] && echo "Current proxy: ${TIKTOK_PROXY_HOST}:${TIKTOK_PROXY_PORT}"
    read -rp "Proxy host:port: " proxy_input
    parse_host_port "$proxy_input"
    read -rp "Proxy username (empty for no-auth): " TIKTOK_PROXY_USER
    if [[ -n "$TIKTOK_PROXY_USER" ]]; then
        read -rsp "Proxy password: " TIKTOK_PROXY_PASS
        echo
    else
        TIKTOK_PROXY_PASS=''
    fi
    save_proxy_env
}

install_templates() {
    mkdir -p "$ETC_DIR" "$V2BX_DIR"
    curl -fsSL "$RAW_BASE/templates/route.json" -o "$ETC_DIR/route.json"
    cp -a "$ETC_DIR/route.json" "$V2BX_DIR/route.json" 2>/dev/null || true
    curl -fsSL "$RAW_BASE/templates/update-rules-dat.sh" -o "$V2BX_DIR/update-rules-dat.sh"
    chmod +x "$V2BX_DIR/update-rules-dat.sh"
    curl -fsSL "$RAW_BASE/templates/config-paths.py" -o /tmp/v2bx-config-paths.py
    python3 /tmp/v2bx-config-paths.py
    rm -f /tmp/v2bx-config-paths.py
}

generate_custom_outbound() {
    load_proxy_env
    if [[ -z "$TIKTOK_PROXY_HOST" || -z "$TIKTOK_PROXY_PORT" ]]; then
        echo -e "${red}TikTok proxy is not configured.${plain}"
        ask_proxy
    fi
    local host_json user_json pass_json users_json
    host_json=$(printf '%s' "$TIKTOK_PROXY_HOST" | json_escape)
    if [[ -n "$TIKTOK_PROXY_USER" ]]; then
        user_json=$(printf '%s' "$TIKTOK_PROXY_USER" | json_escape)
        pass_json=$(printf '%s' "$TIKTOK_PROXY_PASS" | json_escape)
        users_json="[{\"user\":${user_json},\"pass\":${pass_json}}]"
    else
        users_json='[]'
    fi
    cat > "$ETC_DIR/custom_outbound.json" <<EOF_JSON
[
  {"tag":"IPv4_out","protocol":"freedom","settings":{}},
  {"tag":"IPv6_out","protocol":"freedom","settings":{"domainStrategy":"UseIPv6"}},
  {
    "tag":"tiktok-residential",
    "protocol":"http",
    "settings":{
      "servers":[{"address":${host_json},"port":${TIKTOK_PROXY_PORT},"users":${users_json}}]
    }
  },
  {"protocol":"blackhole","tag":"block"}
]
EOF_JSON
    python3 -m json.tool "$ETC_DIR/custom_outbound.json" >/dev/null
    cp -a "$ETC_DIR/custom_outbound.json" "$V2BX_DIR/custom_outbound.json" 2>/dev/null || true
}

install_cron() {
    cat > /etc/cron.d/v2bx-rules-dat <<'EOF_CRON'
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
17 4 * * * root /usr/local/V2bX/update-rules-dat.sh >> /var/log/v2bx-rules-dat.log 2>&1
EOF_CRON
}

apply_tiktok_proxy() {
    need_root
    load_proxy_env
    if [[ -z "$TIKTOK_PROXY_HOST" || -z "$TIKTOK_PROXY_PORT" ]]; then
        ask_proxy
    fi
    local backup_dir="/root/v2bx-tiktokproxy-backup-$(date +%F_%H%M%S)"
    mkdir -p "$backup_dir"
    cp -a "$ETC_DIR/config.json" "$backup_dir/config.json" 2>/dev/null || true
    cp -a "$ETC_DIR/route.json" "$backup_dir/route.json" 2>/dev/null || true
    cp -a "$ETC_DIR/custom_outbound.json" "$backup_dir/custom_outbound.json" 2>/dev/null || true
    install_templates
    generate_custom_outbound
    install_cron
    "$V2BX_DIR/update-rules-dat.sh" || true
    restart_v2bx
    echo -e "${green}TikTok proxy config applied.${plain} Backup: $backup_dir"
}

configure_tiktok_proxy() {
    need_root
    ask_proxy
    apply_tiktok_proxy
}

update_rules_dat() {
    need_root
    if [[ ! -x "$V2BX_DIR/update-rules-dat.sh" ]]; then
        install_templates
    fi
    "$V2BX_DIR/update-rules-dat.sh"
}

update_v2bx_binary() {
    need_root
    local arch last_version zip_url
    arch=$(uname -m)
    case "$arch" in
        x86_64|x64|amd64) arch='64' ;;
        aarch64|arm64) arch='arm64-v8a' ;;
        s390x) arch='s390x' ;;
        *) arch='64' ;;
    esac
    last_version=$(curl -fsSL 'https://api.github.com/repos/wyx2685/V2bX/releases/latest' | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [[ -z "$last_version" ]] && echo -e "${red}Cannot detect latest V2bX version.${plain}" && exit 1
    zip_url="https://github.com/wyx2685/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip"
    mkdir -p "$V2BX_DIR"
    curl -fL --retry 3 "$zip_url" -o /tmp/V2bX-linux.zip
    local backup_dir="/root/v2bx-binary-backup-$(date +%F_%H%M%S)"
    mkdir -p "$backup_dir"
    cp -a "$V2BX_DIR/V2bX" "$backup_dir/V2bX" 2>/dev/null || true
    unzip -o /tmp/V2bX-linux.zip -d "$V2BX_DIR" >/dev/null
    chmod +x "$V2BX_DIR/V2bX"
    rm -f /tmp/V2bX-linux.zip
    apply_tiktok_proxy
    echo -e "${green}V2bX binary updated to ${last_version}; TikTok logic preserved.${plain}"
}

update_tiktokproxy_script() {
    need_root
    curl -fsSL "$RAW_BASE/bin/V2bX.sh" -o /usr/bin/V2bX
    chmod +x /usr/bin/V2bX
    ln -sf /usr/bin/V2bX /usr/bin/v2bx
    curl -fsSL "$RAW_BASE/install.sh" -o /usr/local/V2bX/install-tiktokproxy.sh || true
    install_templates
    generate_custom_outbound
    install_cron
    restart_v2bx
    echo -e "${green}v2bx-tiktokproxy script updated; existing proxy config preserved.${plain}"
}

show_tiktok_status() {
    load_proxy_env
    echo "Proxy: ${TIKTOK_PROXY_HOST:-not set}:${TIKTOK_PROXY_PORT:-}"
    echo "Route matchers: $(python3 - <<'PY' 2>/dev/null || echo unknown
import json
r=json.load(open('/etc/V2bX/route.json'))['rules']
for x in r:
    if x.get('outboundTag') == 'tiktok-residential':
        print(len(x.get('domain', [])))
        break
PY
)"
    echo "Active proxy connections: $(ss -tnp 2>/dev/null | grep -c ':8779' || true)"
    echo "Recent TikTok detours:"
    journalctl -u V2bX --since '5 minutes ago' --no-pager -l 2>/dev/null | grep 'taking detour \[tiktok-residential\]' | tail -10 || true
}

show_menu() {
    clear || true
    echo -e "${green}V2bX TikTokProxy Manager${plain}"
    echo "------------------------------------------"
    echo "1. Start V2bX"
    echo "2. Stop V2bX"
    echo "3. Restart V2bX"
    echo "4. Status"
    echo "5. Logs"
    echo "6. Configure TikTok proxy"
    echo "7. Re-apply TikTok route/outbound"
    echo "8. Update geosite/geoip dat"
    echo "9. Update V2bX binary, keep TikTok logic"
    echo "10. Update v2bx-tiktokproxy menu/script"
    echo "11. TikTok routing status"
    echo "0. Exit"
    echo "------------------------------------------"
    read -rp "Choose: " num
    case "$num" in
        1) service_cmd start ;;
        2) service_cmd stop ;;
        3) restart_v2bx ;;
        4) status_v2bx ;;
        5) journalctl -u V2bX -f -l ;;
        6) configure_tiktok_proxy ;;
        7) apply_tiktok_proxy ;;
        8) update_rules_dat ;;
        9) update_v2bx_binary ;;
        10) update_tiktokproxy_script ;;
        11) show_tiktok_status ;;
        0) exit 0 ;;
        *) echo "Invalid option" ;;
    esac
}

main() {
    case "${1:-menu}" in
        start) service_cmd start ;;
        stop) service_cmd stop ;;
        restart) restart_v2bx ;;
        status) status_v2bx ;;
        log|logs) journalctl -u V2bX -f -l ;;
        tiktok|tiktok-config|proxy) configure_tiktok_proxy ;;
        tiktok-apply|apply) apply_tiktok_proxy ;;
        tiktok-status) show_tiktok_status ;;
        update-rules|rules) update_rules_dat ;;
        update) update_v2bx_binary ;;
        update-script|self-update) update_tiktokproxy_script ;;
        menu|*) show_menu ;;
    esac
}

main "$@"
