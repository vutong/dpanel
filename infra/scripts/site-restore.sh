#!/usr/bin/env bash
# Usage: site-restore.sh <domain>
# Clear pendingDeleteAt, restore nginx, start Node container if needed.
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"

DOMAIN="${1:-}"

log() { echo "[dpanel] $*" >&2; }
die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

[[ -n "${DOMAIN}" ]] || die "Missing domain"
[[ "${DOMAIN}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || die "Invalid domain"

cd "${STACK_ROOT}"
SITES_FILE="${STACK_ROOT}/data/panel/sites.json"
[[ -f "${SITES_FILE}" ]] || die "sites.json not found"

ensure_python3 || die "python3 required"
export SITES_FILE DOMAIN

RUNTIME="$("${PYBIN}" <<'PY'
import json, os, sys
path = os.environ["SITES_FILE"]
domain = os.environ["DOMAIN"]
with open(path) as f:
    sites = json.load(f)
for s in sites:
    if s.get("domain") == domain:
        if not (s.get("pendingDeleteAt") or "").strip():
            print("NOT_PENDING")
            sys.exit(2)
        s.pop("pendingDeleteAt", None)
        print((s.get("runtime") or "").strip())
        with open(path, "w") as out:
            json.dump(sites, out, indent=2)
        sys.exit(0)
sys.exit(1)
PY
)" || {
  code=$?
  [[ "${code}" -eq 2 ]] && die "Site is not pending delete"
  die "Site not found in sites.json"
}

[[ "${RUNTIME}" != "NOT_PENDING" ]] || die "Site is not pending delete"

SLUG="$(site_slug "${DOMAIN}")"
log "Restoring website: ${DOMAIN} (runtime=${RUNTIME})"

# Drop quarantined copy so write_* can recreate active conf cleanly.
rm -f "${STACK_ROOT}/infra/nginx/conf.d/disabled/${DOMAIN}.conf" 2>/dev/null || true

if [[ "${RUNTIME}" == "node" ]]; then
  write_node_compose_fragment "${DOMAIN}"
  write_nginx_node_site "${DOMAIN}"
  cd "${STACK_ROOT}"
  stack_compose up -d "node-${SLUG}" 2>/dev/null || true
elif [[ "${RUNTIME}" == "php" ]]; then
  write_nginx_php_site "${DOMAIN}"
else
  die "Unknown runtime: ${RUNTIME}"
fi

nginx_test_stack 1 || die "nginx -t failed after restore"
nginx_reload_stack 2>/dev/null || true

printf '{"ok":true,"domain":"%s","restored":true,"runtime":"%s"}\n' "${DOMAIN}" "${RUNTIME}"
log "Done — ${DOMAIN} restored"
