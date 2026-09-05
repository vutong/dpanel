#!/usr/bin/env bash
# Clear stuck meta.opRunning when no site-op / panel-update process is running.
set -euo pipefail

META_FILE="${1:-}"
GRACE_MS="${2:-120000}"
MAX_MS="${3:-1800000}"

[[ -n "$META_FILE" && -f "$META_FILE" ]] || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_helpers.sh
source "${SCRIPT_DIR}/_helpers.sh"
ensure_python3 >/dev/null 2>&1 || exit 0

if pgrep -af 'site-(update|rebuild|fix-permissions)\.sh ' >/dev/null 2>&1; then
  exit 0
fi
if pgrep -af 'panel-update\.sh' >/dev/null 2>&1; then
  exit 0
fi
if pgrep -af 'panel-update-host' >/dev/null 2>&1; then
  exit 0
fi
if pgrep -af 'infra/scripts/update\.sh' >/dev/null 2>&1; then
  exit 0
fi

"${PYBIN}" - "$META_FILE" "$GRACE_MS" "$MAX_MS" <<'PY'
import json, sys, os
from datetime import datetime, timezone

path, grace_ms, max_ms = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
try:
    with open(path, encoding="utf-8") as f:
        meta = json.load(f)
except (OSError, json.JSONDecodeError):
    raise SystemExit(0)
if not meta.get("opRunning"):
    raise SystemExit(0)
since = meta.get("opRunningSince")
if since:
    try:
        t = datetime.fromisoformat(str(since).replace("Z", "+00:00"))
        age_ms = (datetime.now(timezone.utc) - t).total_seconds() * 1000
    except ValueError:
        age_ms = max_ms + 1
else:
    age_ms = max_ms + 1
if age_ms < grace_ms and age_ms < max_ms:
    raise SystemExit(0)
meta["opRunning"] = False
meta["opRunningSince"] = None
meta["pausedUntil"] = None
tmp = f"{path}.{os.getpid()}.tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(meta, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
PY
