#!/usr/bin/env bash
# Tail fail2ban.log for panel UI.
# Usage: host-fail2ban-logs.sh [lines] [grep_pattern]
set -euo pipefail

LINES="${1:-200}"
GREP="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host-chroot.sh
source "${SCRIPT_DIR}/host-chroot.sh"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

[[ "${LINES}" =~ ^[0-9]+$ ]] || die "Invalid lines"
if [[ "${LINES}" -gt 2000 ]]; then LINES=2000; fi
if [[ "${LINES}" -lt 1 ]]; then LINES=1; fi

LOG_CMD="
set -euo pipefail
LINES=${LINES}
GREP=${GREP@Q}
for p in /var/log/fail2ban.log /var/log/fail2ban/fail2ban.log; do
  if [[ -f \"\$p\" ]]; then
    if [[ -n \"\$GREP\" ]]; then
      tail -n \"\$LINES\" \"\$p\" 2>/dev/null | grep -F -- \"\$GREP\" || true
    else
      tail -n \"\$LINES\" \"\$p\" 2>/dev/null || true
    fi
    echo \"__PATH__:\$p\"
    exit 0
  fi
done
echo '__PATH__:none'
"

if [[ -f /.dockerenv ]] && command -v docker >/dev/null 2>&1; then
  RAW="$(host_exec_capture "${LOG_CMD}")"
else
  RAW="$(bash -lc "${LOG_CMD}" 2>&1)"
fi

PATH_LINE="$(echo "${RAW}" | grep '^__PATH__:' | tail -1 | sed 's/^__PATH__://')"
CONTENT="$(echo "${RAW}" | grep -v '^__PATH__:' || true)"

python3 - <<PY
import json, os
lines = [ln for ln in """${CONTENT}""".splitlines() if ln.strip()]
path = """${PATH_LINE}"""
if path == "none":
    print(json.dumps({"ok": True, "lines": [], "truncated": False, "path": None, "warning": "fail2ban.log not found"}))
else:
    print(json.dumps({"ok": True, "lines": lines, "truncated": len(lines) >= int("${LINES}"), "path": path}))
PY
