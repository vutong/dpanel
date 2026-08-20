#!/usr/bin/env bash
# Usage: site-delete.sh <domain> [--soft|--purge]
#   --soft  (default) Mark pendingDeleteAt, offline nginx, stop Node — keep apps/DB 24h
#   --purge Full removal: registry, DBs, nginx, compose, apps/, routing, logs
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"
# shellcheck source=_db_registry.sh
source "${STACK_ROOT}/infra/scripts/_db_registry.sh"

DOMAIN="${1:-}"
MODE="soft"

log() { echo "[dpanel] $*" >&2; }
die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

shift 2>/dev/null || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --soft) MODE="soft" ;;
    --purge) MODE="purge" ;;
    -h|--help)
      echo "Usage: site-delete.sh <domain> [--soft|--purge]" >&2
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

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
PENDING=""
if [[ -f "${SITES_FILE}" ]]; then
  read -r RUNTIME PENDING < <("${PYBIN}" -c "
import json, os
domain = os.environ['DOMAIN']
with open(os.environ['SITES_FILE']) as f:
    for s in json.load(f):
        if s.get('domain') == domain:
            print((s.get('runtime') or '').strip())
            print((s.get('pendingDeleteAt') or '').strip())
            break
" 2>/dev/null || true)
fi

[[ -n "${RUNTIME}" || -f "${SITES_FILE}" ]] || die "sites.json not found"

# --- Soft delete: keep site in registry, offline only ---
if [[ "${MODE}" == "soft" ]]; then
  [[ -f "${SITES_FILE}" ]] || die "sites.json not found"
  export SITES_FILE DOMAIN
  export SITE_PENDING_DELETE_HOURS="${SITE_PENDING_DELETE_HOURS:-24}"
  EXPIRES="$("${PYBIN}" <<'PY'
import json, os
from datetime import datetime, timezone, timedelta

path = os.environ["SITES_FILE"]
domain = os.environ["DOMAIN"]
hours = int(os.environ.get("SITE_PENDING_DELETE_HOURS") or "24")
now = datetime.now(timezone.utc)

with open(path) as f:
    sites = json.load(f)
found = False
pending_raw = ""
for s in sites:
    if s.get("domain") == domain:
        found = True
        existing = (s.get("pendingDeleteAt") or "").strip()
        if existing:
            # Idempotent: keep original timestamp (do not reset 24h window)
            pending_raw = existing
        else:
            pending_raw = now.strftime("%Y-%m-%dT%H:%M:%SZ")
            s["pendingDeleteAt"] = pending_raw
        # Soft-delete supersedes suspend
        s.pop("suspendedAt", None)
        break
if not found:
    raise SystemExit(1)
with open(path, "w") as f:
    json.dump(sites, f, indent=2)

try:
    ts = datetime.fromisoformat(pending_raw.replace("Z", "+00:00"))
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
except ValueError:
    ts = now
expires = (ts + timedelta(hours=hours)).strftime("%Y-%m-%dT%H:%M:%SZ")
print(expires)
PY
)" || die "Site not found in sites.json"

  mkdir -p "${STACK_ROOT}/infra/nginx/conf.d/disabled"
  active_conf="${STACK_ROOT}/infra/nginx/conf.d/${DOMAIN}.conf"
  if [[ -f "${active_conf}" ]]; then
    mv -f "${active_conf}" "${STACK_ROOT}/infra/nginx/conf.d/disabled/${DOMAIN}.conf"
    REMOVED+=("nginx:quarantined")
    log "Quarantined nginx vhost for ${DOMAIN}"
  fi

  if [[ "${RUNTIME}" == "node" ]] || [[ -f "${STACK_ROOT}/compose.d/node-${SLUG}.yml" ]]; then
    docker_stop_container_by_name "$(_node_container_name "${SLUG}")"
    REMOVED+=("container:stopped")
    log "Stopped Node container for ${DOMAIN}"
  fi

  nginx_reload_stack 2>/dev/null || true

  printf '{"ok":true,"domain":"%s","soft":true,"expiresAt":"%s"}\n' \
    "${DOMAIN}" "${EXPIRES}"

  log "Done — ${DOMAIN} pending delete until ${EXPIRES} (Restore within 24h)"
  exit 0
fi

# --- Purge: full removal ---
log "Purging website: ${DOMAIN} (runtime=${RUNTIME:-unknown})"

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

site_delete_finish_background "${DOMAIN}" "${SLUG}" "${HAD_NODE}"

log "Done — ${DOMAIN} purged (background: logs/node/site-delete-${SLUG}.log)" >&2
