#!/usr/bin/env bash
# Usage: site-app-logs.sh <domain> [lines]
# Prints Docker logs for the site's Nuxt container (stdout for panel API).
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"

DOMAIN="${1:-}"
LINES="${2:-300}"

die() { echo "[dpanel] ERROR: $*" >&2; exit 1; }

[[ -n "${DOMAIN}" ]] || die "Missing domain"
[[ "${DOMAIN}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || die "Invalid domain"
[[ "${LINES}" =~ ^[0-9]+$ ]] || die "lines must be a number"

SLUG="$(site_slug "${DOMAIN}")"
cname="$(_nuxt_container_name "${SLUG}")"

if ! docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "${cname}"; then
  echo "[dpanel] Container ${cname} not found — create the site or run Rebuild first."
  exit 0
fi

docker logs --tail "${LINES}" "${cname}" 2>&1 || true
