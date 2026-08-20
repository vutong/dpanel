#!/usr/bin/env bash
# Tail ClamAV logs for panel UI.
# Usage: host-clamav-logs.sh [lines] [grep_pattern] [source]
# source: clamav | freshclam | clamd | scan (panel scan logs under logs/panel/)
set -euo pipefail

LINES="${1:-200}"
GREP="${2:-}"
SOURCE="${3:-clamav}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host-chroot.sh
source "${SCRIPT_DIR}/host-chroot.sh"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

[[ "${LINES}" =~ ^[0-9]+$ ]] || die "Invalid lines"
if [[ "${LINES}" -gt 2000 ]]; then LINES=2000; fi
if [[ "${LINES}" -lt 1 ]]; then LINES=1; fi

STACK_ROOT="${STACK_ROOT:-/opt/stack}"

LOG_CMD="
set -euo pipefail
LINES=${LINES}
GREP=${GREP@Q}
SOURCE=${SOURCE@Q}
STACK=${STACK_ROOT@Q}

tail_file() {
  local p=\"\$1\"
  if [[ -n \"\$GREP\" ]]; then
    tail -n \"\$LINES\" \"\$p\" 2>/dev/null | grep -F -- \"\$GREP\" || true
  else
    tail -n \"\$LINES\" \"\$p\" 2>/dev/null || true
  fi
  echo \"__PATH__:\$p\"
}

case \"\$SOURCE\" in
  freshclam)
    for p in /var/log/clamav/freshclam.log /var/log/freshclam.log; do
      if [[ -f \"\$p\" ]]; then tail_file \"\$p\"; exit 0; fi
    done
    ;;
  clamd)
    for p in /var/log/clamav/clamd.log /var/log/clamav/clamav.log; do
      if [[ -f \"\$p\" ]]; then tail_file \"\$p\"; exit 0; fi
    done
    ;;
  scan)
    dir=\"\${STACK}/logs/panel\"
    if [[ -d \"\$dir\" ]]; then
      latest=\$(ls -t \"\$dir\"/clamav-scan-*.log 2>/dev/null | head -1 || true)
      if [[ -n \"\$latest\" && -f \"\$latest\" ]]; then tail_file \"\$latest\"; exit 0; fi
    fi
    ;;
  *)
    for p in /var/log/clamav/clamav.log /var/log/clamav/clamd.log; do
      if [[ -f \"\$p\" ]]; then tail_file \"\$p\"; exit 0; fi
    done
    ;;
esac
echo '__PATH__:none'
"

if [[ -f /.dockerenv ]] && command -v docker >/dev/null 2>&1; then
  RAW="$(host_exec_capture "${LOG_CMD}")"
else
  RAW="$(bash -lc "${LOG_CMD}" 2>&1)"
fi

PATH_LINE="$(echo "${RAW}" | grep '^__PATH__:' | tail -1 | sed 's/^__PATH__://')"
CONTENT="$(echo "${RAW}" | grep -v '^__PATH__:' || true)"

export LOG_CONTENT="${CONTENT}" LOG_PATH="${PATH_LINE}" LOG_LINES="${LINES}" LOG_SOURCE="${SOURCE}"
python3 <<'PY'
import json, os

lines = [ln for ln in os.environ.get("LOG_CONTENT", "").splitlines() if ln.strip()]
path = os.environ.get("LOG_PATH", "none")
source = os.environ.get("LOG_SOURCE", "clamav")
max_lines = int(os.environ.get("LOG_LINES", "200"))

if path == "none":
    print(json.dumps({
        "ok": True,
        "lines": [],
        "truncated": False,
        "path": None,
        "source": source,
        "warning": f"No log file found for source '{source}'",
    }))
else:
    print(json.dumps({
        "ok": True,
        "lines": lines,
        "truncated": len(lines) >= max_lines,
        "path": path,
        "source": source,
    }))
PY
