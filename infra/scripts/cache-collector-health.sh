#!/usr/bin/env bash
# Healthcheck for cache-collector service — stats cache or recent collector run.
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
CACHE_DIR="${STACK_ROOT}/data/panel/cache"
COLLECTOR_STATE_FILE="${CACHE_DIR}/collector-state.json"
STATS_FILE="${CACHE_DIR}/stats.json"
MAX_AGE_SEC="${DPANEL_COLLECTOR_HEALTH_MAX_AGE_SEC:-600}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_helpers.sh
source "${SCRIPT_DIR}/_helpers.sh"
ensure_python3 >/dev/null 2>&1 || exit 1

now_epoch="$(date +%s)"

if [[ -f "$STATS_FILE" ]]; then
  mtime="$("${PYBIN}" - "$STATS_FILE" <<'PY'
import os, sys
print(int(os.path.getmtime(sys.argv[1])))
PY
)"
  age=$((now_epoch - mtime))
  if (( age <= MAX_AGE_SEC )); then
    exit 0
  fi
fi

if [[ -f "$COLLECTOR_STATE_FILE" ]]; then
  "${PYBIN}" - "$MAX_AGE_SEC" "$COLLECTOR_STATE_FILE" <<'PY'
import json, sys
from datetime import datetime, timezone

max_age = int(sys.argv[1])
path = sys.argv[2]
try:
    with open(path, encoding="utf-8") as f:
        state = json.load(f)
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
runs = state.get("collectorLastRun") or {}
now = datetime.now(timezone.utc)
for ts in runs.values():
    if not ts:
        continue
    try:
        t = datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
        age = (now - t).total_seconds()
        if age <= max_age:
            raise SystemExit(0)
    except ValueError:
        continue
raise SystemExit(1)
PY
fi

exit 1
