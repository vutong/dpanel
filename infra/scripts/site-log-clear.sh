#!/usr/bin/env bash
# Usage: site-log-clear.sh <domain> <rebuild|update|create|container>
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"

DOMAIN="${1:-}"
OP="${2:-}"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

[[ -n "${DOMAIN}" && -n "${OP}" ]] || die "Missing domain or log type"
[[ "${DOMAIN}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || die "Invalid domain"
[[ "${OP}" == "rebuild" || "${OP}" == "update" || "${OP}" == "create" || "${OP}" == "container" ]] \
  || die "op must be rebuild, update, create, or container"

SLUG="$(site_slug "${DOMAIN}")"

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

[[ "${RUNTIME}" == "node" ]] || die "Log clear is only for Node sites"

mkdir -p "${STACK_ROOT}/logs/node"

if [[ "${OP}" == "container" ]]; then
  cname="$(_nuxt_container_name "${SLUG}")"
  if ! docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "${cname}"; then
    die "Container ${cname} not found"
  fi
  logpath="$(docker inspect --format='{{.LogPath}}' "${cname}" 2>/dev/null || true)"
  if [[ -n "${logpath}" && -f "${logpath}" ]]; then
    : >"${logpath}"
    echo "{\"ok\":true,\"domain\":\"${DOMAIN}\",\"op\":\"container\",\"cleared\":\"docker\"}"
  else
    die "Could not find Docker log file for ${cname}"
  fi
  exit 0
fi

LOG="${STACK_ROOT}/logs/node/site-${OP}-${SLUG}.log"
if [[ "${OP}" == "create" ]]; then
  LOG="${STACK_ROOT}/logs/node/site-create-${SLUG}.log"
fi

touch "${LOG}"
: >"${LOG}"
echo "{\"ok\":true,\"domain\":\"${DOMAIN}\",\"op\":\"${OP}\",\"path\":\"${LOG}\"}"
