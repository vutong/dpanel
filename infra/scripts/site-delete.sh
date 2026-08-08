#!/usr/bin/env bash
# Usage: site-delete.sh <domain>
# Full removal: sites.json, linked MariaDB DBs, nginx, compose.d, container,
# apps/<domain>/, site-routing, site-resources, site-ops, site logs (no leftovers)
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"
# shellcheck source=_db_registry.sh
source "${STACK_ROOT}/infra/scripts/_db_registry.sh"

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
declare -a REMOVED=()
declare -a DELETED_DBS=()
HAD_NODE=0

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

# Drop MariaDB databases linked to this site (registry + DROP DATABASE/USER).
while IFS= read -r db_name; do
  [[ -n "${db_name}" ]] || continue
  log "Deleting linked database: ${db_name}"
  if bash "${STACK_ROOT}/infra/scripts/db-delete.sh" "${db_name}" >/dev/null; then
    DELETED_DBS+=("${db_name}")
    REMOVED+=("database:${db_name}")
    log "Deleted database ${db_name}"
  else
    log "Warning: failed to delete database ${db_name}"
  fi
done < <(db_registry_names_for_site "${DOMAIN}" || true)

if [[ "${RUNTIME}" == "node" ]] || [[ -f "${STACK_ROOT}/compose.d/node-${SLUG}.yml" ]]; then
  HAD_NODE=1
fi

if [[ -f "${STACK_ROOT}/compose.d/node-${SLUG}.yml" ]]; then
  rm -f "${STACK_ROOT}/compose.d/node-${SLUG}.yml"
  REMOVED+=("compose.d:node-${SLUG}.yml")
  log "Removed compose.d/node-${SLUG}.yml"
fi

routing_json="${STACK_ROOT}/data/panel/site-routing/${SLUG}.json"
if [[ -f "${routing_json}" ]]; then
  rm -f "${routing_json}"
  REMOVED+=("site-routing:${SLUG}.json")
  log "Removed ${routing_json}"
fi

resources_json="${STACK_ROOT}/data/panel/site-resources/${SLUG}.json"
if [[ -f "${resources_json}" ]]; then
  rm -f "${resources_json}"
  REMOVED+=("site-resources:${SLUG}.json")
  log "Removed ${resources_json}"
fi

ops_json="${STACK_ROOT}/data/panel/site-ops/${DOMAIN}.json"
if [[ -f "${ops_json}" ]]; then
  rm -f "${ops_json}"
  REMOVED+=("site-ops:${DOMAIN}.json")
  log "Removed ${ops_json}"
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

# Site operation logs (create / rebuild / update). Delete log cleaned after background finish.
for op in create rebuild update; do
  log_file="${STACK_ROOT}/logs/node/site-${op}-${SLUG}.log"
  if [[ -f "${log_file}" ]]; then
    rm -f "${log_file}"
    REMOVED+=("log:site-${op}-${SLUG}.log")
    log "Removed ${log_file}"
  fi
done

REMOVED_JSON="$(printf '%s\n' "${REMOVED[@]}" | "${PYBIN}" -c "
import json, sys
items = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(items))
")"
DELETED_DBS_JSON="$(printf '%s\n' "${DELETED_DBS[@]}" | "${PYBIN}" -c "
import json, sys
items = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(items))
")"

printf '{"ok":true,"domain":"%s","purged":true,"removed":%s,"deletedDatabases":%s}\n' \
  "${DOMAIN}" "${REMOVED_JSON}" "${DELETED_DBS_JSON}"

# Slow work in background: rm apps/, docker stop Node, nginx reload — never stack_compose up/stop (502 panel).
site_delete_finish_background "${DOMAIN}" "${SLUG}" "${HAD_NODE}"

log "Done — ${DOMAIN} unregistered (background: logs/node/site-delete-${SLUG}.log)" >&2
