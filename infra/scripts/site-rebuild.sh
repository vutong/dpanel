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

ensure_python3 || die "python3 required — run: sudo dpanel update"

SLUG="$(site_slug "${DOMAIN}")"
SVC="nuxt-${SLUG}"
LOG="${STACK_ROOT}/logs/node/site-rebuild-${SLUG}.log"

mkdir -p "${STACK_ROOT}/logs/node"
: >>"${LOG}"
exec >>"${LOG}" 2>&1
echo "[dpanel] $(date '+%Y-%m-%d %H:%M:%S') site-rebuild ${DOMAIN}"

site_op_status_write "${DOMAIN}" "rebuild" "running" "Building…" || true

SITES_FILE="${STACK_ROOT}/data/panel/sites.json"
APP_DIR="${STACK_ROOT}/apps/${DOMAIN}"

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

site_op_status_write "${DOMAIN}" "rebuild" "running" "npm install & build…"
if ! nuxt_container_build "${DOMAIN}"; then
  if [[ -f "${APP_DIR}/.output/server/index.mjs" ]]; then
    die "Build finished but app did not start — check App logs (Eye), Edit .env (MONGODB_URI), and mongoose in package.json"
  fi
  die "npm build failed — see log above or logs/node/site-rebuild-${SLUG}.log"
fi

log "Applying nginx routing (wildcard + custom domains)…"
site_apply_nginx_routing "${DOMAIN}"
site_op_status_write "${DOMAIN}" "rebuild" "ok" "Rebuild complete — site should be online"
echo "{\"ok\":true,\"domain\":\"${DOMAIN}\",\"service\":\"${SVC}\",\"action\":\"rebuild\"}"
