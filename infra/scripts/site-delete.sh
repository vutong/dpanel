#!/usr/bin/env bash
# Usage: site-delete.sh <domain> [--purge]
# Removes site from registry and all stack artifacts (nginx, compose.d, container).
# --purge also deletes apps/<domain> and data/uploads/<domain>
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"

DOMAIN="${1:-}"
PURGE=0
shift 2>/dev/null || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) PURGE=1 ;;
    -h|--help)
      echo "Usage: site-delete.sh <domain> [--purge]"
      exit 0
      ;;
  esac
  shift
done

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

ensure_python3 || die "python3 required"

# Detect runtime before removing from registry
RUNTIME=""
if [[ -f "${SITES_FILE}" ]]; then
  RUNTIME="$("${PYBIN}" -c "
import json, os, sys
domain = os.environ['DOMAIN']
with open(os.environ['SITES_FILE']) as f:
    for s in json.load(f):
        if s.get('domain') == domain:
            print(s.get('runtime') or '')
            sys.exit(0)
" 2>/dev/null || true)"
fi
export SITES_FILE DOMAIN="${DOMAIN}"
"${PYBIN}" <<'PY' || die "Site not found in sites.json"
import json, os, sys
path = os.environ["SITES_FILE"]
domain = os.environ["DOMAIN"]
if not os.path.isfile(path):
    sys.exit(1)
with open(path) as f:
    sites = json.load(f)
new = [s for s in sites if s.get("domain") != domain]
if len(new) == len(sites):
    sys.exit(1)
with open(path, "w") as f:
    json.dump(new, f, indent=2)
PY

# Stop/remove Nuxt service while compose fragment still exists
if [[ "${RUNTIME}" == "node" ]] || [[ -f "${STACK_ROOT}/compose.d/nuxt-${SLUG}.yml" ]]; then
  stack_compose stop "${SVC}" 2>/dev/null || true
  stack_compose rm -f "${SVC}" 2>/dev/null || true
fi

rm -f "${STACK_ROOT}/compose.d/nuxt-${SLUG}.yml"
rm -f "${STACK_ROOT}/infra/nginx/conf.d/${DOMAIN}.conf"
rm -f "${STACK_ROOT}/infra/nginx/conf.d/disabled/${DOMAIN}.conf"

if [[ "${PURGE}" -eq 1 ]]; then
  rm -rf "${STACK_ROOT}/apps/${DOMAIN}"
  rm -rf "${STACK_ROOT}/data/uploads/${DOMAIN}"
fi

prune_orphan_site_artifacts 2>/dev/null || true

bash "${STACK_ROOT}/infra/scripts/nginx-reload.sh" || die "nginx-reload failed after site remove"

# Recreate compose without deleted fragment and drop orphan containers
cd "${STACK_ROOT}"
stack_compose up -d --remove-orphans 2>/dev/null || true

echo "{\"ok\":true,\"domain\":\"${DOMAIN}\",\"purged\":${PURGE}}"
