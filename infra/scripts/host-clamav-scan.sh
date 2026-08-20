#!/usr/bin/env bash
# Scan apps/ or apps/<domain>/ with ClamAV. Outputs JSON on last line.
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
TARGET="${1:-apps}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host-chroot.sh
source "${SCRIPT_DIR}/host-chroot.sh"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

# Normalize target — only under apps/
TARGET="${TARGET#apps/}"
TARGET="${TARGET#/}"
if [[ -n "${TARGET}" && ! "${TARGET}" =~ ^[a-zA-Z0-9.-]+$ ]]; then
  die "Invalid domain/path"
fi

SCAN_PATH="/opt/stack/apps"
if [[ -n "${TARGET}" ]]; then
  SCAN_PATH="/opt/stack/apps/${TARGET}"
fi

CMD="
if ! command -v clamscan >/dev/null 2>&1; then
  echo 'clamav not installed' >&2; exit 1
fi
if [[ ! -d '${SCAN_PATH}' ]]; then
  echo 'scan path not found' >&2; exit 1
fi
# Prefer clamdscan if daemon up; fallback clamscan
if systemctl is-active clamav-daemon >/dev/null 2>&1 && command -v clamdscan >/dev/null 2>&1; then
  clamdscan -i --no-summary '${SCAN_PATH}' 2>&1 || true
else
  clamscan -r -i --no-summary '${SCAN_PATH}' 2>&1 || true
fi
"

if [[ -f /.dockerenv ]] && command -v docker >/dev/null 2>&1; then
  OUT="$(host_exec_capture "${CMD}")" || true
else
  OUT="$(bash -lc "${CMD}")" || true
fi

command -v python3 >/dev/null 2>&1 || die "python3 required"

STACK_ROOT="${STACK_ROOT}" TARGET="${TARGET}" SCAN_OUT="${OUT}" python3 - <<'PY'
import json, os, re

stack = os.environ.get("STACK_ROOT", "/opt/stack")
target = os.environ.get("TARGET", "")
raw = os.environ.get("SCAN_OUT", "")

infected = []
for line in raw.splitlines():
    line = line.strip()
    if not line.endswith("FOUND"):
        continue
    # /opt/stack/apps/domain.com/file.php: Eicar-Test-Signature FOUND
    path = line.rsplit(":", 1)[0].strip()
    if path.startswith("/opt/stack/apps/"):
        rel = path[len("/opt/stack/apps/"):]
        parts = rel.split("/", 1)
        domain = parts[0] if parts else None
        rel_path = parts[1] if len(parts) > 1 else ""
        infected.append({"path": path, "domain": domain, "relPath": rel_path, "line": line})

print(json.dumps({
    "ok": True,
    "target": target or "all",
    "scanPath": f"/opt/stack/apps/{target}" if target else "/opt/stack/apps",
    "infectedCount": len(infected),
    "infected": infected,
    "logTail": raw[-8000:] if len(raw) > 8000 else raw,
}))
PY
