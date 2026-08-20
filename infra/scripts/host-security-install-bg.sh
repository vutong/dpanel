#!/usr/bin/env bash
# Background wrapper for Fail2ban / ClamAV install (panel triggers detached).
# Usage: host-security-install-bg.sh fail2ban|clamav
set -euo pipefail

OP="${1:-}"
STACK_ROOT="${STACK_ROOT:-/opt/stack}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS_FILE="${STACK_ROOT}/data/panel/security-install-${OP}.json"

[[ "${OP}" == fail2ban || "${OP}" == clamav ]] || {
  echo "usage: host-security-install-bg.sh fail2ban|clamav" >&2
  exit 1
}

write_status() {
  local status="$1"
  local message="${2:-}"
  STATUS="${status}" MESSAGE="${message}" OP="${OP}" STATUS_FILE="${STATUS_FILE}" python3 - <<'PY'
import json, os
from datetime import datetime, timezone

path = os.environ["STATUS_FILE"]
prev = {}
try:
    with open(path, encoding="utf-8") as f:
        prev = json.load(f)
except (OSError, json.JSONDecodeError):
    pass

data = {
    "op": os.environ["OP"],
    "status": os.environ["STATUS"],
    "message": os.environ.get("MESSAGE", ""),
    "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "eventRecorded": prev.get("eventRecorded", False),
}
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

fail() {
  local msg="${1:-Install failed}"
  write_status error "${msg}"
  exit 1
}

case "${OP}" in
  fail2ban) INSTALL_SCRIPT="${SCRIPT_DIR}/host-fail2ban-install.sh" ;;
  clamav) INSTALL_SCRIPT="${SCRIPT_DIR}/host-clamav-install.sh" ;;
esac

command -v python3 >/dev/null 2>&1 || fail "python3 required"

if ! out="$(bash "${INSTALL_SCRIPT}" 2>&1)"; then
  err=""
  json_line="$(printf '%s\n' "${out}" | grep -E '^\{"ok":false' | tail -1 || true)"
  if [[ -n "${json_line}" ]]; then
    err="$(STATUS_JSON="${json_line}" python3 - <<'PY'
import json, os
try:
    print(json.loads(os.environ["STATUS_JSON"]).get("error") or "")
except Exception:
    print("")
PY
)"
  fi
  if [[ -z "${err}" ]]; then
    err="$(printf '%s\n' "${out}" | tail -5 | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-500)"
  fi
  fail "${err:-Install failed}"
fi

write_status ok "Installed"
