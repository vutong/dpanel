#!/usr/bin/env bash
# Purge sites whose pendingDeleteAt is older than 24 hours.
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"

SITES_FILE="${STACK_ROOT}/data/panel/sites.json"
[[ -f "${SITES_FILE}" ]] || exit 0

ensure_python3 >/dev/null 2>&1 || exit 0

# Single-flight: skip if another purge-expired is running.
LOCK_DIR="${STACK_ROOT}/data/panel/.site-purge-expired.lock"
mkdir -p "${STACK_ROOT}/data/panel"
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  exit 0
fi
cleanup_lock() { rmdir "${LOCK_DIR}" 2>/dev/null || true; }
trap cleanup_lock EXIT

export SITES_FILE
export SITE_PENDING_DELETE_HOURS="${SITE_PENDING_DELETE_HOURS:-24}"
mapfile -t EXPIRED < <("${PYBIN}" <<'PY'
import json, os
from datetime import datetime, timezone, timedelta

path = os.environ["SITES_FILE"]
hours = int(os.environ.get("SITE_PENDING_DELETE_HOURS") or "24")
cutoff = datetime.now(timezone.utc) - timedelta(hours=hours)
with open(path) as f:
    sites = json.load(f)
for s in sites:
    raw = (s.get("pendingDeleteAt") or "").strip()
    if not raw:
        continue
    d = (s.get("domain") or "").strip()
    if not d:
        continue
    try:
        ts = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        # Invalid / unparseable already handled; expired when <= cutoff
        if ts > cutoff:
            continue
    except ValueError:
        # Corrupt timestamp — treat as expired so the site is not stuck forever
        pass
    print(d)
PY
)

if [[ ${#EXPIRED[@]} -eq 0 ]]; then
  exit 0
fi

for domain in "${EXPIRED[@]}"; do
  [[ -n "${domain}" ]] || continue
  echo "[dpanel] Purging expired pending site: ${domain}" >&2
  bash "${STACK_ROOT}/infra/scripts/site-delete.sh" "${domain}" --purge \
    || echo "[dpanel] WARNING: purge failed for ${domain}" >&2
done

exit 0
