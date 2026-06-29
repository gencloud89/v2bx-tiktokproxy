#!/usr/bin/env python3
import json
from pathlib import Path

path = Path('/etc/V2bX/config.json')
if not path.exists():
    raise SystemExit('/etc/V2bX/config.json not found')

data = json.loads(path.read_text())
cores = data.setdefault('Cores', [])
if not cores:
    cores.append({'Type': 'xray', 'Log': {'Level': 'info', 'AccessPath': '', 'ErrorPath': ''}})
for core in cores:
    if core.get('Type', '').lower() == 'xray' or 'RouteConfigPath' in core or 'OutboundConfigPath' in core:
        core['RouteConfigPath'] = '/etc/V2bX/route.json'
        core['OutboundConfigPath'] = '/etc/V2bX/custom_outbound.json'
        break
else:
    cores[0]['RouteConfigPath'] = '/etc/V2bX/route.json'
    cores[0]['OutboundConfigPath'] = '/etc/V2bX/custom_outbound.json'

path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
