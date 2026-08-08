#!/usr/bin/env bash
# Purge sites whose pendingDeleteAt is older than 24 hours.
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"

SITES_FILE="${STACK_ROOT}/data/panel/sites.json"
[[ -f "${SITES_FILE}" ]] || exit 0

ensure_python3 >/dev/null 2>&1 || exit 0

export SITES_FILE
mapfile -t EXPIRED < <("${PYBIN}" <<'PY'
import json, os
from datetime import datetime, timezone, timedelta

path = os.environ["SITES_FILE"]
cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
with open(path) as f:
    sites = json.load(f)
for s in sites:
    raw = (s.get("pendingDeleteAt") or "").strip()
    if not raw:
        continue
    try:
        # Support Z suffix
        ts = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        continue
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    if ts <= cutoff:
        d = (s.get("domain") or "").strip()
        if d:
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
