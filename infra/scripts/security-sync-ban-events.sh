#!/usr/bin/env bash
# Record newly seen fail2ban banned IPs into security-events.json (collector only).
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
IPS_JSON="${1:-[]}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_helpers.sh
source "${SCRIPT_DIR}/_helpers.sh"
ensure_python3 >/dev/null 2>&1 || exit 0

"${PYBIN}" - "$STACK_ROOT" "$IPS_JSON" <<'PY'
import json, sys, uuid
from datetime import datetime, timezone
from pathlib import Path

stack_root = Path(sys.argv[1])
try:
    ips = json.loads(sys.argv[2])
except json.JSONDecodeError:
    ips = []
if not isinstance(ips, list):
    ips = []

def valid_ip(ip):
    ip = str(ip or "").strip()
    if not ip or len(ip) > 45:
        return None
    if ip.count(".") == 3:
        parts = ip.split(".")
        if all(p.isdigit() and 0 <= int(p) <= 255 for p in parts):
            return ip
    if ":" in ip:
        return ip
    return None

ips = [v for v in (valid_ip(x) for x in ips) if v]

panel_dir = stack_root / "data" / "panel"
panel_dir.mkdir(parents=True, exist_ok=True)
known_path = panel_dir / "fail2ban-known-ips.json"
events_path = panel_dir / "security-events.json"

try:
    known = set(json.loads(known_path.read_text(encoding="utf-8")))
    if not isinstance(known, set):
        known = set(known if isinstance(known, list) else [])
except (OSError, json.JSONDecodeError, TypeError):
    known = set()

try:
    events = json.loads(events_path.read_text(encoding="utf-8"))
    if not isinstance(events, list):
        events = []
except (OSError, json.JSONDecodeError):
    events = []

now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
added = False
for ip in ips:
    if ip in known:
        continue
    known.add(ip)
    events.insert(0, {
        "id": str(uuid.uuid4()),
        "at": now,
        "kind": "fail2ban_ban",
        "source": "fail2ban",
        "domain": None,
        "ip": ip,
        "path": None,
        "action": "banned_ip",
        "detail": "Fail2ban ban",
    })
    added = True

if added:
    events = events[:500]
    events_path.write_text(json.dumps(events, indent=2) + "\n", encoding="utf-8")
    known_path.write_text(json.dumps(sorted(known), indent=2) + "\n", encoding="utf-8")
PY
