#!/usr/bin/env bash
# Usage: site-suspend.sh <domain>
# Mark suspendedAt, quarantine nginx, stop Node — keep apps/DB (reversible, no purge).
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
# shellcheck source=/dev/null
[[ -f .env ]] && source .env
PANEL_DOMAIN="${PANEL_DOMAIN:-}"

[[ "${DOMAIN}" != "${PANEL_DOMAIN}" ]] || die "Cannot suspend panel domain"
[[ "${DOMAIN}" != "panel.local" ]] || die "Cannot suspend panel domain"

SITES_FILE="${STACK_ROOT}/data/panel/sites.json"
[[ -f "${SITES_FILE}" ]] || die "sites.json not found"

ensure_python3 || die "python3 required"
export SITES_FILE DOMAIN

RUNTIME="$("${PYBIN}" <<'PY'
import json, os, sys
from datetime import datetime, timezone

path = os.environ["SITES_FILE"]
domain = os.environ["DOMAIN"]
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

with open(path) as f:
    sites = json.load(f)
for s in sites:
    if s.get("domain") == domain:
        if (s.get("pendingDeleteAt") or "").strip():
            print("PENDING")
            sys.exit(2)
        existing = (s.get("suspendedAt") or "").strip()
        if not existing:
            s["suspendedAt"] = now
            with open(path, "w") as out:
                json.dump(sites, out, indent=2)
        print((s.get("runtime") or "").strip())
        sys.exit(0)
sys.exit(1)
PY
)" || {
  code=$?
  [[ "${code}" -eq 2 ]] && die "Site is pending delete — cannot suspend"
  die "Site not found in sites.json"
}

[[ "${RUNTIME}" != "PENDING" ]] || die "Site is pending delete — cannot suspend"

SLUG="$(site_slug "${DOMAIN}")"
log "Suspending website: ${DOMAIN} (runtime=${RUNTIME})"

mkdir -p "${STACK_ROOT}/infra/nginx/conf.d/disabled"
active_conf="${STACK_ROOT}/infra/nginx/conf.d/${DOMAIN}.conf"
if [[ -f "${active_conf}" ]]; then
  mv -f "${active_conf}" "${STACK_ROOT}/infra/nginx/conf.d/disabled/${DOMAIN}.conf"
  log "Quarantined nginx vhost for ${DOMAIN}"
fi

if [[ "${RUNTIME}" == "node" ]] || [[ -f "${STACK_ROOT}/compose.d/node-${SLUG}.yml" ]]; then
  docker_stop_container_by_name "$(_node_container_name "${SLUG}")"
  log "Stopped Node container for ${DOMAIN}"
fi

nginx_reload_stack 2>/dev/null || true

printf '{"ok":true,"domain":"%s","suspended":true,"runtime":"%s"}\n' "${DOMAIN}" "${RUNTIME}"
log "Done — ${DOMAIN} suspended (inactive)"
