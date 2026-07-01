#!/usr/bin/env bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

REPO='gencloud89/v2bx-tiktokproxy'
RAW_BASE='https://raw.githubusercontent.com/gencloud89/v2bx-tiktokproxy/main'
V2BX_DIR='/usr/local/V2bX'
ETC_DIR='/etc/V2bX'
ENV_FILE="$ETC_DIR/tiktok-proxy.env"
GITHUB_ENV_FILE="$ETC_DIR/tiktokproxy-github.env"

[[ $EUID -ne 0 ]] && echo -e "${red}Lỗi:${plain} Vui lòng chạy bằng user root.\n" && exit 1

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
    echo -e "${red}Không nhận diện được hệ điều hành.${plain}\n" && exit 1
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

confirm() {
    local prompt="$1" default="${2:-}"
    local temp
    if [[ -n "$default" ]]; then
        echo && read -rp "$prompt [mặc định $default]: " temp
        [[ -z "$temp" ]] && temp="$default"
    else
        read -rp "$prompt [y/n]: " temp
    fi
    [[ "$temp" == 'y' || "$temp" == 'Y' ]]
}

before_show_menu() {
    echo && echo -n -e "${yellow}Nhấn Enter để quay lại menu chính: ${plain}" && read -r _ || true
    show_menu
}

check_status() {
    if [[ ! -f "$V2BX_DIR/V2bX" ]]; then
        return 2
    fi
    if [[ "$release" == 'alpine' ]]; then
        local temp
        temp=$(service V2bX status 2>/dev/null | awk '{print $3}')
        [[ "$temp" == 'started' ]] && return 0 || return 1
    else
        local temp
        temp=$(systemctl status V2bX 2>/dev/null | grep Active | awk '{print $3}' | cut -d '(' -f2 | cut -d ')' -f1)
        [[ "$temp" == 'running' ]] && return 0 || return 1
    fi
}

check_enabled() {
    if [[ "$release" == 'alpine' ]]; then
        rc-update show 2>/dev/null | grep -q V2bX
    else
        [[ "$(systemctl is-enabled V2bX 2>/dev/null || true)" == 'enabled' ]]
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo && echo -e "${red}Vui lòng cài V2bX trước.${plain}"
        [[ $# == 0 ]] && before_show_menu
        return 1
    fi
    return 0
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo && echo -e "${red}V2bX đã được cài, không nên cài lặp.${plain}"
        [[ $# == 0 ]] && before_show_menu
        return 1
    fi
    return 0
}

restart() {
    if [[ "$release" == 'alpine' ]]; then service V2bX restart; else systemctl restart V2bX; fi
    sleep 2
    check_status
    if [[ $? == 0 ]]; then echo -e "${green}V2bX khởi động lại thành công.${plain}"; else echo -e "${red}V2bX có thể khởi động lỗi, hãy xem log.${plain}"; fi
    [[ $# == 0 ]] && before_show_menu
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${green}V2bX đang chạy, không cần khởi động lại.${plain}"
    else
        if [[ "$release" == 'alpine' ]]; then service V2bX start; else systemctl start V2bX; fi
        sleep 2
        check_status && echo -e "${green}V2bX khởi động thành công.${plain}" || echo -e "${red}V2bX có thể khởi động lỗi.${plain}"
    fi
    [[ $# == 0 ]] && before_show_menu
}

stop() {
    if [[ "$release" == 'alpine' ]]; then service V2bX stop; else systemctl stop V2bX; fi
    sleep 2
    check_status
    if [[ $? == 1 ]]; then echo -e "${green}V2bX đã dừng.${plain}"; else echo -e "${red}Dừng V2bX thất bại hoặc cần thêm thời gian.${plain}"; fi
    [[ $# == 0 ]] && before_show_menu
}

status() {
    if [[ "$release" == 'alpine' ]]; then service V2bX status; else systemctl status V2bX --no-pager -l; fi
    [[ $# == 0 ]] && before_show_menu
}

show_log() {
    if [[ "$release" == 'alpine' ]]; then echo -e "${red}Alpine chưa hỗ trợ xem log bằng journalctl.${plain}"; else journalctl -u V2bX.service -e --no-pager -f; fi
    [[ $# == 0 ]] && before_show_menu
}

enable() {
    if [[ "$release" == 'alpine' ]]; then rc-update add V2bX; else systemctl enable V2bX; fi
    echo -e "${green}Đã bật V2bX khởi động cùng hệ thống.${plain}"
    [[ $# == 0 ]] && before_show_menu
}

disable() {
    if [[ "$release" == 'alpine' ]]; then rc-update del V2bX; else systemctl disable V2bX; fi
    echo -e "${green}Đã tắt V2bX khởi động cùng hệ thống.${plain}"
    [[ $# == 0 ]] && before_show_menu
}

config() {
    echo "Sau khi sửa cấu hình, script sẽ thử restart V2bX."
    vi "$ETC_DIR/config.json"
    sleep 2
    restart 0
    [[ $# == 0 ]] && before_show_menu
}

install() {
    check_uninstall "$@" || return 0
    load_github_token
    local cmd="bash <(curl -Ls"
    if [[ -n "$GITHUB_TOKEN" ]]; then
        bash <(curl -Ls -H "Authorization: Bearer ${GITHUB_TOKEN}" "$RAW_BASE/install.sh")
    else
        bash <(curl -Ls "$RAW_BASE/install.sh")
    fi
    [[ $# == 0 ]] && before_show_menu
}

update() {
    load_github_token
    local version="${2:-}"
    if [[ $# == 0 || -z "$version" ]]; then
        echo && read -rp "Nhập phiên bản muốn cập nhật (bỏ trống = mới nhất): " version
    fi
    if [[ -n "$GITHUB_TOKEN" ]]; then
        bash <(curl -Ls -H "Authorization: Bearer ${GITHUB_TOKEN}" "$RAW_BASE/install.sh") "$version"
    else
        bash <(curl -Ls "$RAW_BASE/install.sh") "$version"
    fi
    apply_tiktok_proxy 0
    echo -e "${green}Cập nhật V2bX xong, logic TikTok đã được áp dụng lại.${plain}"
    [[ $# == 0 ]] && before_show_menu
}

uninstall() {
    confirm "Bạn chắc chắn muốn gỡ V2bX?" "n" || { [[ $# == 0 ]] && show_menu; return 0; }
    if [[ "$release" == 'alpine' ]]; then
        service V2bX stop || true; rc-update del V2bX || true; rm -f /etc/init.d/V2bX
    else
        systemctl stop V2bX || true; systemctl disable V2bX || true; rm -f /etc/systemd/system/V2bX.service; systemctl daemon-reload; systemctl reset-failed || true
    fi
    rm -rf "$ETC_DIR" "$V2BX_DIR"
    echo -e "${green}Đã gỡ V2bX. Muốn xoá script menu: rm -f /usr/bin/V2bX /usr/bin/v2bx${plain}"
    [[ $# == 0 ]] && before_show_menu
}

install_bbr() { bash <(curl -L -s https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh); }

show_V2bX_version() {
    echo -n "Phiên bản V2bX: "
    "$V2BX_DIR/V2bX" version || true
    [[ $# == 0 ]] && before_show_menu
}

generate_x25519_key() {
    echo -n "Đang tạo khoá X25519: "
    "$V2BX_DIR/V2bX" x25519
    [[ $# == 0 ]] && before_show_menu
}

generate_config_file() {
    fetch_url "${RAW_BASE}/install.sh" /tmp/v2bx-tiktok-install.sh >/dev/null 2>&1 || true
    curl -o /tmp/initconfig.sh -Ls https://raw.githubusercontent.com/wyx2685/V2bX-script/master/initconfig.sh
    # shellcheck disable=SC1091
    source /tmp/initconfig.sh
    rm -f /tmp/initconfig.sh
    generate_config_file
}

allow_ports() {
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -F
    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -P INPUT ACCEPT || true
        ip6tables -P FORWARD ACCEPT || true
        ip6tables -P OUTPUT ACCEPT || true
        ip6tables -F || true
    fi
    echo -e "${green}Đã mở tất cả cổng mạng bằng iptables hiện tại.${plain}"
    [[ $# == 0 ]] && before_show_menu
}

show_status() {
    check_status
    case $? in
        0) echo -e "V2bX trạng thái: ${green}Đang chạy${plain}" ;;
        1) echo -e "V2bX trạng thái: ${yellow}Chưa chạy${plain}" ;;
        2) echo -e "V2bX trạng thái: ${red}Chưa cài${plain}" ;;
    esac
    check_enabled && echo -e "Tự khởi động cùng hệ thống: ${green}Có${plain}" || echo -e "Tự khởi động cùng hệ thống: ${red}Không${plain}"
}

json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))'; }

parse_host_port() {
    local input="$1"
    if [[ "$input" == *:* ]]; then TIKTOK_PROXY_HOST="${input%:*}"; TIKTOK_PROXY_PORT="${input##*:}"; else TIKTOK_PROXY_HOST="$input"; read -rp "Cổng proxy: " TIKTOK_PROXY_PORT; fi
    [[ "$TIKTOK_PROXY_PORT" =~ ^[0-9]+$ ]] || { echo -e "${red}Cổng proxy phải là số.${plain}"; exit 1; }
}

save_proxy_env() {
    mkdir -p "$ETC_DIR"
    umask 077
    { printf 'TIKTOK_PROXY_HOST=%q\n' "$TIKTOK_PROXY_HOST"; printf 'TIKTOK_PROXY_PORT=%q\n' "$TIKTOK_PROXY_PORT"; printf 'TIKTOK_PROXY_USER=%q\n' "$TIKTOK_PROXY_USER"; printf 'TIKTOK_PROXY_PASS=%q\n' "$TIKTOK_PROXY_PASS"; } > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
}

load_proxy_env() {
    [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
    : "${TIKTOK_PROXY_HOST:=}"; : "${TIKTOK_PROXY_PORT:=}"; : "${TIKTOK_PROXY_USER:=}"; : "${TIKTOK_PROXY_PASS:=}"
}

ask_proxy() {
    load_proxy_env
    echo -e "${yellow}Cấu hình proxy xoay/cư dân cho TikTok${plain}"
    [[ -n "$TIKTOK_PROXY_HOST" ]] && echo "Proxy hiện tại: ${TIKTOK_PROXY_HOST}:${TIKTOK_PROXY_PORT}"
    read -rp "Nhập proxy host:port: " proxy_input
    parse_host_port "$proxy_input"
    read -rp "Username proxy (bỏ trống nếu không cần): " TIKTOK_PROXY_USER
    if [[ -n "$TIKTOK_PROXY_USER" ]]; then read -rsp "Password proxy: " TIKTOK_PROXY_PASS; echo; else TIKTOK_PROXY_PASS=''; fi
    save_proxy_env
}

install_templates() {
    mkdir -p "$ETC_DIR" "$V2BX_DIR"
    fetch_url "$RAW_BASE/templates/route.json" "$ETC_DIR/route.json"
    cp -a "$ETC_DIR/route.json" "$V2BX_DIR/route.json" 2>/dev/null || true
    fetch_url "$RAW_BASE/templates/update-rules-dat.sh" "$V2BX_DIR/update-rules-dat.sh"
    chmod +x "$V2BX_DIR/update-rules-dat.sh"
    fetch_url "$RAW_BASE/templates/config-paths.py" /tmp/v2bx-config-paths.py
    python3 /tmp/v2bx-config-paths.py
    rm -f /tmp/v2bx-config-paths.py
}

generate_custom_outbound() {
    load_proxy_env
    [[ -z "$TIKTOK_PROXY_HOST" || -z "$TIKTOK_PROXY_PORT" ]] && ask_proxy
    local host_json user_json pass_json users_json
    host_json=$(printf '%s' "$TIKTOK_PROXY_HOST" | json_escape)
    if [[ -n "$TIKTOK_PROXY_USER" ]]; then
        user_json=$(printf '%s' "$TIKTOK_PROXY_USER" | json_escape); pass_json=$(printf '%s' "$TIKTOK_PROXY_PASS" | json_escape); users_json="[{\"user\":${user_json},\"pass\":${pass_json}}]"
    else
        users_json='[]'
    fi
    cat > "$ETC_DIR/custom_outbound.json" <<EOF_JSON
[
  {"tag":"IPv4_out","protocol":"freedom","settings":{}},
  {"tag":"IPv6_out","protocol":"freedom","settings":{"domainStrategy":"UseIPv6"}},
  {"tag":"tiktok-residential","protocol":"http","settings":{"servers":[{"address":${host_json},"port":${TIKTOK_PROXY_PORT},"users":${users_json}}]}},
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
    load_github_token; save_github_token; load_proxy_env
    [[ -z "$TIKTOK_PROXY_HOST" || -z "$TIKTOK_PROXY_PORT" ]] && ask_proxy
    local backup_dir="/root/v2bx-tiktokproxy-backup-$(date +%F_%H%M%S)"
    mkdir -p "$backup_dir"
    cp -a "$ETC_DIR/config.json" "$backup_dir/config.json" 2>/dev/null || true
    cp -a "$ETC_DIR/route.json" "$backup_dir/route.json" 2>/dev/null || true
    cp -a "$ETC_DIR/custom_outbound.json" "$backup_dir/custom_outbound.json" 2>/dev/null || true
    install_templates
    generate_custom_outbound
    install_cron
    "$V2BX_DIR/update-rules-dat.sh" || true
    restart 0
    echo -e "${green}Đã áp dụng cấu hình proxy TikTok.${plain} Backup: $backup_dir"
    [[ $# == 0 ]] && before_show_menu
}

configure_tiktok_proxy() { ask_proxy; apply_tiktok_proxy "$@"; }

update_rules_dat() { [[ ! -x "$V2BX_DIR/update-rules-dat.sh" ]] && install_templates; "$V2BX_DIR/update-rules-dat.sh"; [[ $# == 0 ]] && before_show_menu; }

update_shell() {
    load_github_token
    fetch_url "$RAW_BASE/bin/V2bX.sh" /usr/bin/V2bX
    chmod +x /usr/bin/V2bX
    ln -sf /usr/bin/V2bX /usr/bin/v2bx
    echo -e "${green}Đã nâng cấp script quản lý V2bX TikTokProxy.${plain}"
    exit 0
}

show_tiktok_status() {
    load_proxy_env
    echo "Proxy TikTok: ${TIKTOK_PROXY_HOST:-chưa cấu hình}:${TIKTOK_PROXY_PORT:-}"
    if [[ -n "${TIKTOK_PROXY_PORT:-}" ]]; then
        echo "Kết nối proxy đang mở: $(ss -tnp 2>/dev/null | grep -c ":${TIKTOK_PROXY_PORT}" || true)"
    else
        echo "Kết nối proxy đang mở: 0"
    fi
    echo "Log TikTok gần đây:"
    journalctl -u V2bX --since '5 minutes ago' --no-pager -l 2>/dev/null | grep -Ei "tiktok|ibyte|byteimg|tiktok-residential|${TIKTOK_PROXY_HOST:-proxyxoay}|${TIKTOK_PROXY_PORT:-proxy}|Limited" | tail -30 || true
    [[ $# == 0 ]] && before_show_menu
    return 0
}

show_menu() {
    clear || true
    echo -e "${green}V2bX backend management script${plain}, ${red}not suitable for docker${plain}"
    echo -e "--- https://github.com/gencloud89/v2bx-tiktokproxy ---"
    echo -e "  ${green}0.${plain} Sửa cấu hình"
    echo "------------------------"
    echo -e "  ${green}1.${plain} Cài đặt V2bX"
    echo -e "  ${green}2.${plain} Cập nhật V2bX"
    echo -e "  ${green}3.${plain} Gỡ cài đặt V2bX"
    echo "------------------------"
    echo -e "  ${green}4.${plain} Khởi động V2bX"
    echo -e "  ${green}5.${plain} Dừng V2bX"
    echo -e "  ${green}6.${plain} Khởi động lại V2bX"
    echo -e "  ${green}7.${plain} Xem trạng thái V2bX"
    echo -e "  ${green}8.${plain} Xem log V2bX"
    echo "------------------------"
    echo -e "  ${green}9.${plain} Bật V2bX tự khởi động"
    echo -e " ${green}10.${plain} Tắt V2bX tự khởi động"
    echo "------------------------"
    echo -e " ${green}11.${plain} Cài đặt BBR một lệnh (kernel mới nhất)"
    echo -e " ${green}12.${plain} Xem phiên bản V2bX"
    echo -e " ${green}13.${plain} Tạo khoá X25519"
    echo -e " ${green}14.${plain} Nâng cấp script quản lý V2bX"
    echo -e " ${green}15.${plain} Tạo file cấu hình V2bX"
    echo -e " ${green}16.${plain} Mở tất cả cổng mạng của VPS"
    echo -e " ${green}17.${plain} Thoát script"
    echo -e " ${green}18.${plain} Cấu hình proxy TikTok"
    echo "------------------------"
    show_status
    echo && read -rp "Vui lòng nhập lựa chọn [0-18]: " num
    case "$num" in
        0) config ;;
        1) install ;;
        2) update ;;
        3) uninstall ;;
        4) start ;;
        5) stop ;;
        6) restart ;;
        7) status ;;
        8) show_log ;;
        9) enable ;;
        10) disable ;;
        11) install_bbr ;;
        12) show_V2bX_version ;;
        13) generate_x25519_key ;;
        14) update_shell ;;
        15) generate_config_file ;;
        16) allow_ports ;;
        17) exit 0 ;;
        18) configure_tiktok_proxy ;;
        *) echo -e "${red}Vui lòng nhập số hợp lệ [0-18].${plain}"; before_show_menu ;;
    esac
}

case "${1:-menu}" in
    start) start 0 ;;
    stop) stop 0 ;;
    restart) restart 0 ;;
    status) status 0 ;;
    log|logs) show_log 0 ;;
    install) install 0 ;;
    update) update 0 "${2:-}" ;;
    uninstall) uninstall 0 ;;
    tiktok|tiktok-config|proxy) configure_tiktok_proxy 0 ;;
    tiktok-apply|apply) apply_tiktok_proxy 0 ;;
    tiktok-status) show_tiktok_status 0 ;;
    update-rules|rules) update_rules_dat 0 ;;
    update-script|self-update) update_shell ;;
    *) show_menu ;;
esac
