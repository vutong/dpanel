#!/usr/bin/env bash
# Usage: site-app-restart.sh <domain>  (Node sites — restart Nuxt container)
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"

DOMAIN="${1:-}"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

[[ -n "${DOMAIN}" ]] || die "Missing domain"
[[ "${DOMAIN}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || die "Invalid domain"

SLUG="$(site_slug "${DOMAIN}")"
SVC="nuxt-${SLUG}"
cname="$(_nuxt_container_name "${SLUG}")"

SITES_FILE="${STACK_ROOT}/data/panel/sites.json"
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

[[ "${RUNTIME}" == "node" ]] || die "Restart is only for Node sites"

cd "${STACK_ROOT}"
stack_compose up -d "${SVC}" 2>/dev/null || true
if docker ps -q -f "name=^${cname}$" -f "status=running" 2>/dev/null | grep -q .; then
  docker restart "${cname}" 2>/dev/null || die "Could not restart ${cname}"
  echo "{\"ok\":true,\"domain\":\"${DOMAIN}\",\"container\":\"${cname}\",\"action\":\"restart\"}"
else
  die "Container ${cname} is not running"
fi
