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
MATCH="$("${PYBIN}" -c "
import json, os, sys
import re
path = os.environ['SITES_FILE']
host = (os.environ.get('DOMAIN') or '').strip().lower()
slug = re.sub(r'[^a-zA-Z0-9-]', '', host.replace('.', '-'))
routing_path = os.path.join(os.environ.get('STACK_ROOT', '/opt/stack'), 'data', 'panel', 'site-routing')
if not os.path.isfile(path):
    sys.exit(1)

with open(path) as f:
    sites = json.load(f)

for s in sites:
    d = (s.get('domain') or '').strip().lower()
    r = (s.get('runtime') or '').strip().lower()
    if d == host:
        print(f'{d}|{r}')
        sys.exit(0)

# Fallback: input may be a storefront/custom domain; map back to the owning Node site.
candidates = []
for s in sites:
    d = (s.get('domain') or '').strip().lower()
    r = (s.get('runtime') or '').strip().lower()
    if r != 'node' or not d:
        continue
    s_slug = re.sub(r'[^a-zA-Z0-9-]', '', d.replace('.', '-'))
    cfg = os.path.join(routing_path, f'{s_slug}.json')
    wildcard = ''
    extras = set()
    if os.path.isfile(cfg):
        try:
            with open(cfg) as rf:
                rd = json.load(rf)
            wildcard = str(rd.get('wildcardBase') or '').strip().lower()
            extras = {str(x).strip().lower() for x in (rd.get('extraDomains') or []) if str(x).strip()}
        except Exception:
            pass
    if wildcard and (host == wildcard or host == f'www.{wildcard}' or host.endswith(f'.{wildcard}')):
        candidates.append(d)
        continue
    if host in extras:
        candidates.append(d)

candidates = sorted(set(candidates))
if len(candidates) == 1:
    print(f'{candidates[0]}|node')
    sys.exit(0)
if len(candidates) > 1:
    print('AMBIGUOUS|' + ','.join(candidates))
    sys.exit(2)
sys.exit(1)
" 2>/dev/null)" || die "Site not found in sites.json (or no routing match for this host)"

MATCH_DOMAIN="${MATCH%%|*}"
RUNTIME="${MATCH#*|}"
if [[ "${MATCH_DOMAIN}" == "AMBIGUOUS" ]]; then
  die "Host maps to multiple sites: ${RUNTIME} — pass the primary site domain"
fi
DOMAIN="${MATCH_DOMAIN}"
export DOMAIN
[[ "${RUNTIME}" == "node" ]] || die "Routing apply is only available for Node sites"

# Soft-deleted sites must not regain an active nginx vhost.
PENDING="$("${PYBIN}" -c "
import json, os
domain = os.environ.get('DOMAIN', '')
with open(os.environ['SITES_FILE']) as f:
    for s in json.load(f):
        if (s.get('domain') or '').strip().lower() == domain.strip().lower():
            print((s.get('pendingDeleteAt') or '').strip())
            break
" 2>/dev/null || true)"
[[ -z "${PENDING}" ]] || die "Site is pending delete — restore before applying routing"

site_apply_nginx_routing "${DOMAIN}" || die "nginx routing apply failed"

echo "{\"ok\":true,\"domain\":\"${DOMAIN}\"}"
