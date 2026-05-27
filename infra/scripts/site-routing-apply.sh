#!/usr/bin/env bash
# Apply domain routing for a Node site → nginx vhost + reload.
# Usage: site-routing-apply.sh <site-domain>
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"

DOMAIN="${1:-}"
die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

[[ -n "${DOMAIN}" ]] || die "Missing domain"
[[ "${DOMAIN}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || die "Invalid domain"

SITES_FILE="${STACK_ROOT}/data/panel/sites.json"
ensure_python3 || die "python3 required"
export SITES_FILE DOMAIN
RUNTIME="$("${PYBIN}" -c "
import json, os, sys
path = os.environ['SITES_FILE']
domain = os.environ['DOMAIN']
if not os.path.isfile(path):
    sys.exit(1)
with open(path) as f:
    for s in json.load(f):
        if s.get('domain') == domain:
            print((s.get('runtime') or '').strip())
            sys.exit(0)
sys.exit(1)
" 2>/dev/null)" || die "Site not found in sites.json"
[[ "${RUNTIME}" == "node" ]] || die "Routing apply is only available for Node sites"

site_apply_nginx_routing "${DOMAIN}" || die "nginx routing apply failed"

echo "{\"ok\":true,\"domain\":\"${DOMAIN}\"}"
