#!/usr/bin/env bash
# Usage: site-delete.sh <domain>
# Full removal: sites.json, nginx, compose.d, container, apps/<domain>/ (no leftovers)
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"

DOMAIN="${1:-}"
shift 2>/dev/null || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) ;; # legacy flag, always purges app files
    -h|--help)
      echo "Usage: site-delete.sh <domain>" >&2
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

log() { echo "[dpanel] $*" >&2; }

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

[[ -n "${DOMAIN}" ]] || die "Missing domain"
[[ "${DOMAIN}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || die "Invalid domain"

cd "${STACK_ROOT}"
# shellcheck source=/dev/null
[[ -f .env ]] && source .env
PANEL_DOMAIN="${PANEL_DOMAIN:-}"

[[ "${DOMAIN}" != "${PANEL_DOMAIN}" ]] || die "Cannot remove panel domain"
[[ "${DOMAIN}" != "panel.local" ]] || die "Cannot remove panel domain"

SITES_FILE="${STACK_ROOT}/data/panel/sites.json"
SLUG="$(site_slug "${DOMAIN}")"
SVC="nuxt-${SLUG}"
declare -a REMOVED=()

ensure_python3 || die "python3 required"
export SITES_FILE DOMAIN="${DOMAIN}"

RUNTIME=""
if [[ -f "${SITES_FILE}" ]]; then
  RUNTIME="$("${PYBIN}" -c "
import json, os
domain = os.environ['DOMAIN']
with open(os.environ['SITES_FILE']) as f:
    for s in json.load(f):
        if s.get('domain') == domain:
            print(s.get('runtime') or '')
            break
" 2>/dev/null || true)"
fi

log "Removing website: ${DOMAIN} (runtime=${RUNTIME:-unknown}, full purge)"

if [[ -f "${SITES_FILE}" ]]; then
  if ! "${PYBIN}" <<'PY'; then
import json, os, sys
path = os.environ["SITES_FILE"]
domain = os.environ["DOMAIN"]
with open(path) as f:
    sites = json.load(f)
new = [s for s in sites if s.get("domain") != domain]
if len(new) == len(sites):
    sys.exit(1)
with open(path, "w") as f:
    json.dump(new, f, indent=2)
PY
    die "Site not found in sites.json"
  fi
  REMOVED+=("sites.json")
  log "Removed from sites.json"
else
  die "sites.json not found"
fi

if [[ "${RUNTIME}" == "node" ]] || [[ -f "${STACK_ROOT}/compose.d/nuxt-${SLUG}.yml" ]]; then
  log "Stopping Docker service ${SVC}..."
  stack_compose stop "${SVC}" 2>/dev/null || true
  stack_compose rm -f "${SVC}" 2>/dev/null || true
  docker_stop_container_by_name "$(_nuxt_container_name "${SLUG}")"
  REMOVED+=("container:${SVC}")
fi

if [[ -f "${STACK_ROOT}/compose.d/nuxt-${SLUG}.yml" ]]; then
  rm -f "${STACK_ROOT}/compose.d/nuxt-${SLUG}.yml"
  REMOVED+=("compose.d:nuxt-${SLUG}.yml")
  log "Removed compose.d/nuxt-${SLUG}.yml"
fi

for conf in \
  "${STACK_ROOT}/infra/nginx/conf.d/${DOMAIN}.conf" \
  "${STACK_ROOT}/infra/nginx/conf.d/disabled/${DOMAIN}.conf"; do
  if [[ -f "${conf}" ]]; then
    rm -f "${conf}"
    REMOVED+=("nginx:$(basename "${conf}")")
    log "Removed ${conf}"
  fi
done

if [[ -d "${STACK_ROOT}/apps/${DOMAIN}" ]]; then
  rm -rf "${STACK_ROOT}/apps/${DOMAIN}"
  REMOVED+=("apps:${DOMAIN}")
  log "Deleted apps/${DOMAIN}/"
fi

log "Pruning orphan artifacts..."
prune_orphan_site_artifacts 2>/dev/null || true

REMOVED_JSON="$(printf '%s\n' "${REMOVED[@]}" | "${PYBIN}" -c "
import json, sys
items = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(items))
")"

log "Done — ${DOMAIN} removed (nginx reload runs in background)"
printf '{"ok":true,"domain":"%s","purged":true,"removed":%s}\n' \
  "${DOMAIN}" "${REMOVED_JSON}"

site_finalize_async "site-delete-${SLUG}"
