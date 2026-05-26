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
HAD_NUXT=0

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
  HAD_NUXT=1
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

# JSON before slow work (rm -rf apps, compose stop, prune+compose up) — avoids panel timeout/502.
REMOVED_JSON="$(printf '%s\n' "${REMOVED[@]}" | "${PYBIN}" -c "
import json, sys
items = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(items))
")"

printf '{"ok":true,"domain":"%s","purged":true,"removed":%s}\n' \
  "${DOMAIN}" "${REMOVED_JSON}"

APP_DIR="${STACK_ROOT}/apps/${DOMAIN}"
mkdir -p "${STACK_ROOT}/logs/node"
nohup bash -c "
  sleep 0.3
  export STACK_ROOT='${STACK_ROOT}'
  cd \"\${STACK_ROOT}\"
  # shellcheck source=_helpers.sh
  source \"\${STACK_ROOT}/infra/scripts/_helpers.sh\"
  app_dir='${APP_DIR}'
  if [[ -d \"\${app_dir}\" ]]; then
    rm -rf \"\${app_dir}\"
    echo \"[dpanel] Deleted \${app_dir}/\" >&2
  fi
  if [[ ${HAD_NUXT} -eq 1 ]]; then
    site_finalize_async 'site-delete-${SLUG}' '${SVC}' delete
  else
    stack_compose up -d nginx 2>/dev/null || true
    nginx_reload_stack 2>/dev/null || true
    prune_orphan_site_artifacts --no-up 2>/dev/null || true
  fi
" >> "${STACK_ROOT}/logs/node/site-delete-${SLUG}.log" 2>&1 &
disown 2>/dev/null || true

log "Done — ${DOMAIN} unregistered (files/containers finish in background — see logs/node/site-delete-${SLUG}.log)" >&2
