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

write_nginx_node_site "${DOMAIN}"
nginx_reload_stack 2>/dev/null || true

echo "{\"ok\":true,\"domain\":\"${DOMAIN}\"}"
