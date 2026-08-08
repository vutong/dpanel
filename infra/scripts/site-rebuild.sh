#!/usr/bin/env bash
# Usage: site-rebuild.sh <domain>  (Node SSR sites only)
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"

DOMAIN="${1:-}"
NODE_MODULES_MODE="${NODE_MODULES_MODE:-auto}"
OP_FINALIZED=0

die() {
  OP_FINALIZED=1
  site_op_status_write "${DOMAIN}" "rebuild" "error" "$*" 2>/dev/null || true
  echo "{\"ok\":false,\"error\":\"$*\"}" >&2
  exit 1
}

on_exit() {
  site_ops_lock_release
  if [[ "${OP_FINALIZED}" -eq 0 && -n "${DOMAIN}" ]]; then
    site_op_status_write "${DOMAIN}" "rebuild" "error" \
      "Rebuild interrupted unexpectedly — retry Rebuild" 2>/dev/null || true
  fi
}

log() { echo "[dpanel] $*" >&2; }

[[ -n "${DOMAIN}" ]] || die "Missing domain"
[[ "${DOMAIN}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || die "Invalid domain"
[[ "${NODE_MODULES_MODE}" =~ ^(auto|keep|clean)$ ]] || die "Invalid NODE_MODULES_MODE: ${NODE_MODULES_MODE}"

ensure_python3 || die "python3 required — run: sudo dpanel update"

SLUG="$(site_slug "${DOMAIN}")"
SVC="node-${SLUG}"
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

[[ "${RUNTIME}" == "node" ]] || die "Rebuild is only available for Node SSR sites"
[[ -f "${APP_DIR}/package.json" ]] || die "No package.json in apps/${DOMAIN}/ — deploy code first"

log "Rebuilding ${DOMAIN} (${SVC})…"
cd "${STACK_ROOT}"

site_ops_lock_acquire
trap on_exit EXIT

site_op_status_write "${DOMAIN}" "rebuild" "running" "npm install & build…"
if ! node_container_build "${DOMAIN}" "${NODE_MODULES_MODE}"; then
  if [[ -f "${APP_DIR}/.output/server/index.mjs" ]]; then
    die "Build finished but app did not start — check App logs (Eye), Edit .env (MONGODB_URI), and mongoose in package.json"
  fi
  die "npm build failed — see log above or logs/node/site-rebuild-${SLUG}.log"
fi

site_op_status_write "${DOMAIN}" "rebuild" "running" "Applying nginx routing…"
log "Applying nginx routing (wildcard + custom domains)…"
if ! site_apply_nginx_routing "${DOMAIN}"; then
  die "nginx routing apply failed — see log; run: sudo bash ${STACK_ROOT}/infra/scripts/site-routing-apply.sh ${DOMAIN}"
fi

# Mark complete + release lock before domain sync — sync must not block the console or pin the lock.
OP_FINALIZED=1
site_op_status_write "${DOMAIN}" "rebuild" "ok" "Rebuild complete — site should be online"
echo "{\"ok\":true,\"domain\":\"${DOMAIN}\",\"service\":\"${SVC}\",\"action\":\"rebuild\"}"
site_ops_lock_release
trap - EXIT

site_sync_dpanel_routing_best_effort "${DOMAIN}" 90 || true
