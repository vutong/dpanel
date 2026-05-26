#!/usr/bin/env bash
# Usage: site-rebuild.sh <domain>  (Node / Nuxt sites only)
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"

DOMAIN="${1:-}"

die() {
  site_op_status_write "${DOMAIN}" "rebuild" "error" "$*" 2>/dev/null || true
  echo "{\"ok\":false,\"error\":\"$*\"}" >&2
  exit 1
}

log() { echo "[dpanel] $*" >&2; }

[[ -n "${DOMAIN}" ]] || die "Missing domain"
[[ "${DOMAIN}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || die "Invalid domain"

SLUG="$(site_slug "${DOMAIN}")"
SVC="nuxt-${SLUG}"
LOG="${STACK_ROOT}/logs/node/site-rebuild-${SLUG}.log"

mkdir -p "${STACK_ROOT}/logs/node"
exec >>"${LOG}" 2>&1
echo "[dpanel] $(date '+%Y-%m-%d %H:%M:%S') site-rebuild ${DOMAIN}"

site_op_status_write "${DOMAIN}" "rebuild" "running" "Building…"

SITES_FILE="${STACK_ROOT}/data/panel/sites.json"
APP_DIR="${STACK_ROOT}/apps/${DOMAIN}"

ensure_python3 || die "python3 required"
export SITES_FILE DOMAIN
RUNTIME="$("${PYBIN}" -c "
import json, os, sys
with open(os.environ['SITES_FILE']) as f:
    for s in json.load(f):
        if s.get('domain') == os.environ['DOMAIN']:
            print(s.get('runtime') or '')
            sys.exit(0)
sys.exit(1)
" 2>/dev/null)" || die "Site not found"

[[ "${RUNTIME}" == "node" ]] || die "Rebuild is only available for Node (Nuxt) sites"
[[ -f "${APP_DIR}/package.json" ]] || die "No package.json in apps/${DOMAIN}/ — deploy code first"

log "Rebuilding ${DOMAIN} (${SVC})…"
cd "${STACK_ROOT}"

site_ops_lock_acquire
trap site_ops_lock_release EXIT

project="$(_stack_project_name)"
cname="$(_nuxt_container_name "${SLUG}")"
nuxt_cid="$(docker ps -q -f "name=^${cname}$" -f "status=running" 2>/dev/null | head -1)"

if [[ -z "${nuxt_cid}" ]]; then
  site_op_status_write "${DOMAIN}" "rebuild" "running" "Starting container…"
  if _stack_compose_available; then
    stack_compose up -d "${SVC}" 2>/dev/null || true
    sleep 2
    nuxt_cid="$(docker ps -q -f "name=^${cname}$" -f "status=running" 2>/dev/null | head -1)"
  fi
fi

[[ -n "${nuxt_cid}" ]] || die "Nuxt container not running — create the site again or check logs/node/site-rebuild-${SLUG}.log"

site_op_status_write "${DOMAIN}" "rebuild" "running" "npm install & build…"
docker exec "${nuxt_cid}" sh -c 'npm ci 2>/dev/null || npm install; npm run build' \
  || die "npm build failed — see logs/node/site-rebuild-${SLUG}.log"

site_op_status_write "${DOMAIN}" "rebuild" "running" "Restarting app…"
docker restart "${nuxt_cid}" 2>/dev/null || true

site_op_status_write "${DOMAIN}" "rebuild" "ok" "Rebuild complete"
echo "{\"ok\":true,\"domain\":\"${DOMAIN}\",\"service\":\"${SVC}\",\"action\":\"rebuild\"}"
