#!/usr/bin/env bash
# Run app sync:dpanel-routing inside the site Node container (MongoDB → dpanel extraDomains).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_helpers.sh
source "${SCRIPT_DIR}/_helpers.sh"

DOMAIN="${1:-}"
[[ -n "${DOMAIN}" ]] || die "Usage: site-routing-sync.sh <domain>"

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
export STACK_ROOT
cd "${STACK_ROOT}"

SLUG="$(site_slug "${DOMAIN}")"
cname="$(_nuxt_container_name "${SLUG}")"

if ! docker ps --format '{{.Names}}' | grep -qx "${cname}"; then
  die "Container ${cname} is not running"
fi

if ! docker exec "${cname}" sh -c 'node -e "const p=require(\"./package.json\"); process.exit(p.scripts && p.scripts[\"sync:dpanel-routing\"] ? 0 : 1)"' 2>/dev/null; then
  die "This app has no npm run sync:dpanel-routing script"
fi

echo "[dpanel] Running sync:dpanel-routing in ${cname}…" >&2
docker exec "${cname}" sh -c '
  set -e
  if [ -f .env ]; then set -a; . ./.env; set +a; fi
  npm run sync:dpanel-routing
'

echo "{\"ok\":true,\"domain\":\"${DOMAIN}\"}"
