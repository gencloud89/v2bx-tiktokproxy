#!/usr/bin/env python3
import json
import os
import shutil
import sys
import time
from pathlib import Path

ETC_DIR = Path("/etc/V2bX")
CONFIG_PATH = ETC_DIR / "config.json"

CORE_OPTIONS = [
    ("xray", "Xray core, phù hợp VMess/VLESS/Trojan/Shadowsocks và TikTok route/outbound"),
    ("sing", "Sing-box core, dùng khi node/panel của bạn yêu cầu sing"),
    ("hysteria2", "Hysteria2 core riêng"),
]

NODE_TYPES = [
    ("shadowsocks", "Shadowsocks"),
    ("vmess", "VMess"),
    ("vless", "VLESS"),
    ("trojan", "Trojan"),
    ("hysteria", "Hysteria"),
    ("hysteria2", "Hysteria2"),
    ("tuic", "TUIC"),
    ("anytls", "AnyTLS"),
]


def ask(prompt, default=None, required=False, secret=False):
    while True:
        suffix = f" [{default}]" if default not in (None, "") else ""
        if secret:
            import getpass
            value = getpass.getpass(f"{prompt}{suffix}: ")
        else:
            value = input(f"{prompt}{suffix}: ").strip()
        if value == "" and default is not None:
            value = str(default)
        if value or not required:
            return value
        print("Giá trị này không được để trống.")


def ask_yes_no(prompt, default=False):
    suffix = "Y/n" if default else "y/N"
    value = input(f"{prompt} [{suffix}]: ").strip().lower()
    if not value:
        return default
    return value in ("y", "yes", "1", "true", "co", "có")


def ask_choice(title, options, default_index=1):
    print()
    print(title)
    for idx, (value, desc) in enumerate(options, 1):
        print(f"  {idx}. {value} - {desc}")
    while True:
        raw = ask("Chọn số", str(default_index), required=True)
        try:
            index = int(raw)
            if 1 <= index <= len(options):
                return options[index - 1][0]
        except ValueError:
            pass
        print(f"Vui lòng nhập số từ 1 đến {len(options)}.")


def normalize_api_host(value):
    value = value.strip().rstrip("/")
    if value and not value.startswith(("http://", "https://")):
        value = "https://" + value
    return value


def read_existing():
    if CONFIG_PATH.exists():
        try:
            return json.loads(CONFIG_PATH.read_text())
        except Exception:
            return {}
    return {}


def core_entry(core_type):
    if core_type == "xray":
        return {
            "Type": "xray",
            "Log": {"Level": "info", "AccessPath": "", "ErrorPath": ""},
            "RouteConfigPath": "/etc/V2bX/route.json",
            "OutboundConfigPath": "/etc/V2bX/custom_outbound.json",
        }
    if core_type == "sing":
        return {"Type": "sing", "Log": {"Level": "info"}}
    return {"Type": core_type, "Log": {"Level": "info"}}


def default_config():
    return {
        "Log": {"Level": "info", "Output": ""},
        "DnsConfigPath": "/etc/V2bX/dns.json",
        "RouteConfigPath": "/etc/V2bX/route.json",
        "InboundConfigPath": "/etc/V2bX/custom_inbound.json",
        "OutboundConfigPath": "/etc/V2bX/custom_outbound.json",
        "ConnectionConfig": {
            "Handshake": 4,
            "ConnIdle": 30,
            "UplinkOnly": 2,
            "DownlinkOnly": 4,
            "BufferSize": 64,
        },
        "Nodes": [],
        "Cores": [],
    }


def build_node(api_host, api_key):
    core = ask_choice("Core muốn dùng", CORE_OPTIONS, 1)
    node_type = ask_choice("Node type", NODE_TYPES, 1)
    node_id = ask("Node ID", required=True)
    while not str(node_id).isdigit():
        print("Node ID phải là số.")
        node_id = ask("Node ID", required=True)

    node = {
        "Core": core,
        "ApiHost": api_host,
        "ApiKey": api_key,
        "NodeID": int(node_id),
        "NodeType": node_type,
        "Timeout": int(ask("Timeout API giây", "30", required=True)),
        "ListenIP": ask("Listen IP", "0.0.0.0", required=True),
        "SendIP": ask("Send IP", "0.0.0.0", required=True),
        "EnableProxyProtocol": ask_yes_no("Bật Proxy Protocol", False),
        "EnableTFO": ask_yes_no("Bật TCP Fast Open", False),
        "EnableUot": ask_yes_no("Bật UDP over TCP/UoT nếu core hỗ trợ", True),
        "CertConfig": {
            "CertMode": "none",
            "CertDomain": "",
            "CertFile": "",
            "KeyFile": "",
            "Provider": "cloudflare",
            "Email": "",
            "DNSEnv": {},
        },
    }
    return node


def main():
    print("Thiết lập nhanh /etc/V2bX/config.json")
    print("API Host và API Key nhập một lần, dùng chung cho mọi node trong VPS này.")
    ETC_DIR.mkdir(parents=True, exist_ok=True)

    existing = read_existing()
    existing_nodes = existing.get("Nodes") if isinstance(existing.get("Nodes"), list) else []
    default_api_host = ""
    default_api_key = ""
    if existing_nodes:
        default_api_host = str(existing_nodes[0].get("ApiHost", ""))
        default_api_key = str(existing_nodes[0].get("ApiKey", ""))

    api_host = normalize_api_host(ask("API Host panel", default_api_host, required=True))
    api_key = ask("API Key / Server token", default_api_key, required=True, secret=not bool(default_api_key))

    nodes = []
    while True:
        nodes.append(build_node(api_host, api_key))
        if not ask_yes_no("Bạn có muốn thiết lập thêm node khác trên VPS này không", False):
            break

    data = default_config()
    data["Nodes"] = nodes
    cores = []
    seen = set()
    for node in nodes:
        core = node["Core"]
        if core in seen:
            continue
        seen.add(core)
        cores.append(core_entry(core))
    data["Cores"] = cores

    if CONFIG_PATH.exists():
        backup = CONFIG_PATH.with_name(f"config.json.bak-quick-{time.strftime('%Y%m%d-%H%M%S')}")
        shutil.copy2(CONFIG_PATH, backup)
        print(f"Đã backup config cũ: {backup}")

    tmp = CONFIG_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    json.loads(tmp.read_text())
    tmp.replace(CONFIG_PATH)
    print(f"Đã ghi cấu hình: {CONFIG_PATH}")
    print(f"Số node: {len(nodes)}")
    print("Nếu đã bật TikTok proxy, Xray core sẽ dùng route/outbound TikTokProxy.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nĐã huỷ.")
        sys.exit(1)
