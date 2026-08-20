#!/usr/bin/env bash
# Background ClamAV scan — writes result to data/panel/clamav-scans/{id}.json
# Usage: host-clamav-scan-bg.sh <scan_id> [domain]
set -euo pipefail

SCAN_ID="${1:-}"
DOMAIN="${2:-}"
STACK_ROOT="${STACK_ROOT:-/opt/stack}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -n "${SCAN_ID}" ]] || { echo "scan_id required" >&2; exit 1; }
[[ "${SCAN_ID}" =~ ^[a-zA-Z0-9-]+$ ]] || { echo "invalid scan_id" >&2; exit 1; }

if [[ -n "${DOMAIN}" && ! "${DOMAIN}" =~ ^[a-zA-Z0-9.-]+$ ]]; then
  echo "invalid domain" >&2
  exit 1
fi

SCAN_SCRIPT="${SCRIPT_DIR}/host-clamav-scan.sh"
ARGS=()
if [[ -n "${DOMAIN}" ]]; then
  ARGS=("${DOMAIN}")
fi

echo "[$(date -Iseconds)] Starting scan id=${SCAN_ID} target=${DOMAIN:-all}" >&2

RAW=""
if RAW="$("${SCAN_SCRIPT}" "${ARGS[@]}" 2>&1)"; then
  :
else
  RC=$?
  echo "[$(date -Iseconds)] Scan script exit ${RC}" >&2
fi

JSON_LINE="$(echo "${RAW}" | grep -E '^\{.*\}$' | tail -1 || true)"

export STACK_ROOT SCAN_ID DOMAIN SCAN_JSON="${JSON_LINE}" SCAN_RAW="${RAW}"
python3 <<'PY'
import json, os
from datetime import datetime, timezone

stack = os.environ.get("STACK_ROOT", "/opt/stack")
scan_id = os.environ.get("SCAN_ID", "")
domain = os.environ.get("DOMAIN", "").strip().lower()
raw_json = os.environ.get("SCAN_JSON", "").strip()
raw_out = os.environ.get("SCAN_RAW", "")

scans_dir = os.path.join(stack, "data", "panel", "clamav-scans")
detail_path = os.path.join(scans_dir, f"{scan_id}.json")
index_path = os.path.join(scans_dir, "index.json")
by_domain_dir = os.path.join(scans_dir, "by-domain")

os.makedirs(by_domain_dir, exist_ok=True)

now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

detail = {}
try:
    with open(detail_path, encoding="utf-8") as f:
        detail = json.load(f)
except Exception:
    detail = {
        "id": scan_id,
        "target": domain or "all",
        "domain": domain or None,
        "scanPath": f"/opt/stack/apps/{domain}" if domain else "/opt/stack/apps",
        "startedAt": now,
    }

result = {}
if raw_json:
    try:
        result = json.loads(raw_json)
    except Exception as e:
        result = {"ok": False, "error": f"Invalid scan JSON: {e}"}
else:
    result = {"ok": False, "error": "Scan produced no JSON output"}

ok = bool(result.get("ok"))
infected = result.get("infected") or []
infected_count = int(result.get("infectedCount", len(infected)))

detail.update({
    "status": "ok" if ok else "error",
    "finishedAt": now,
    "infectedCount": infected_count,
    "infected": infected,
    "logTail": result.get("logTail") or (raw_out[-8000:] if len(raw_out) > 8000 else raw_out),
    "eventsRecorded": False,
})
if not ok:
    detail["error"] = result.get("error") or "Scan failed"
if result.get("scanPath"):
    detail["scanPath"] = result["scanPath"]
if result.get("target"):
    detail["target"] = result["target"]

with open(detail_path, "w", encoding="utf-8") as f:
    json.dump(detail, f, indent=2)
    f.write("\n")

index = {"scans": []}
try:
    with open(index_path, encoding="utf-8") as f:
        index = json.load(f)
except Exception:
    pass
if not isinstance(index.get("scans"), list):
    index["scans"] = []

summary = {k: detail[k] for k in (
    "id", "target", "domain", "scanPath", "status", "startedAt",
    "finishedAt", "infectedCount", "error", "eventsRecorded",
) if k in detail}

found = False
for i, s in enumerate(index["scans"]):
    if s.get("id") == scan_id:
        index["scans"][i] = {**s, **summary}
        found = True
        break
if not found:
    index["scans"].insert(0, summary)
index["scans"] = index["scans"][:100]

with open(index_path, "w", encoding="utf-8") as f:
    json.dump(index, f, indent=2)
    f.write("\n")

if domain:
    meta_path = os.path.join(by_domain_dir, f"{domain}.json")
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump({
            "lastScanId": scan_id,
            "lastScanAt": detail.get("finishedAt") or detail.get("startedAt"),
            "lastStatus": detail.get("status"),
            "lastInfectedCount": infected_count,
        }, f, indent=2)
        f.write("\n")

print(json.dumps({"ok": True, "scanId": scan_id, "status": detail["status"]}))
PY

echo "[$(date -Iseconds)] Scan id=${SCAN_ID} finished" >&2
