#!/usr/bin/env bash
# Regenerate compose.d fragment with resource limits and recreate the site container.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_helpers.sh
source "${SCRIPT_DIR}/_helpers.sh"

DOMAIN="${1:-}"
[[ -n "${DOMAIN}" ]] || die "Usage: site-resources-apply.sh <domain>"

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
export STACK_ROOT
cd "${STACK_ROOT}"

SLUG="$(site_slug "${DOMAIN}")"
SVC="nuxt-${SLUG}"

write_nuxt_compose_fragment "${DOMAIN}"

stack_compose up -d "${SVC}" 2>/dev/null || stack_compose up -d "${SVC}"

echo "{\"ok\":true,\"domain\":\"${DOMAIN}\",\"service\":\"${SVC}\"}"
