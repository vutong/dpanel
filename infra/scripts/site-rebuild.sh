#!/usr/bin/env bash
# Usage: site-rebuild.sh <domain>  (Node / Nuxt sites only)
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"

DOMAIN="${1:-}"
die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }
log() { echo "[dpanel] $*" >&2; }

[[ -n "${DOMAIN}" ]] || die "Missing domain"
[[ "${DOMAIN}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || die "Invalid domain"

SITES_FILE="${STACK_ROOT}/data/panel/sites.json"
APP_DIR="${STACK_ROOT}/apps/${DOMAIN}"
SLUG="$(site_slug "${DOMAIN}")"
SVC="nuxt-${SLUG}"

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

log "Rebuilding ${DOMAIN} (${SVC})..."
cd "${STACK_ROOT}"

if _stack_compose_available; then
  stack_compose build "${SVC}" 2>/dev/null || stack_compose build "${SVC}" >&2 || die "docker compose build failed"
  stack_compose run --rm --no-deps "${SVC}" sh -c \
    'npm ci 2>/dev/null || npm install; npm run build' >&2 \
    || die "npm build failed inside container"
  stack_compose up -d "${SVC}" 2>/dev/null || true
  stack_compose restart "${SVC}" 2>/dev/null || true
else
  project="$(_stack_project_name)"
  nuxt_cid="$(docker ps -q -f "name=^${project}-nuxt-${SLUG}$" -f "status=running" 2>/dev/null | head -1)"
  if [[ -n "${nuxt_cid}" ]]; then
    docker exec "${nuxt_cid}" sh -c 'npm ci 2>/dev/null || npm install; npm run build' >&2 \
      || die "npm build failed"
    docker restart "${nuxt_cid}" 2>/dev/null || true
  else
    die "Nuxt container not running — run dpanel update or create site again"
  fi
fi

echo "{\"ok\":true,\"domain\":\"${DOMAIN}\",\"service\":\"${SVC}\",\"action\":\"rebuild\"}"
