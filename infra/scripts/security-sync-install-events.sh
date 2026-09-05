#!/usr/bin/env bash
# Record completed security package installs into security-events.json (collector only).
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_helpers.sh
source "${SCRIPT_DIR}/_helpers.sh"
ensure_python3 >/dev/null 2>&1 || exit 0

"${PYBIN}" - "$STACK_ROOT" <<'PY'
import json, sys, uuid
from datetime import datetime, timezone
from pathlib import Path

stack_root = Path(sys.argv[1])
panel_dir = stack_root / "data" / "panel"
events_path = panel_dir / "security-events.json"

ops = {
    "fail2ban": "Fail2ban installed from panel",
    "clamav": "ClamAV installed from panel",
}

try:
    events = json.loads(events_path.read_text(encoding="utf-8"))
    if not isinstance(events, list):
        events = []
except (OSError, json.JSONDecodeError):
    events = []

now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
changed = False

for op, detail in ops.items():
    path = panel_dir / f"security-install-{op}.json"
    try:
        status = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        continue
    if status.get("status") != "ok" or status.get("eventRecorded"):
        continue
    events.insert(0, {
        "id": str(uuid.uuid4()),
        "at": now,
        "kind": "security_install",
        "source": "panel",
        "domain": None,
        "ip": None,
        "path": None,
        "action": "installed",
        "detail": detail,
    })
    status["eventRecorded"] = True
    path.write_text(json.dumps(status, indent=2) + "\n", encoding="utf-8")
    changed = True

if changed:
    events = events[:500]
    events_path.write_text(json.dumps(events, indent=2) + "\n", encoding="utf-8")
PY
