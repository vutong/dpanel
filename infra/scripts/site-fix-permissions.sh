#!/usr/bin/env bash
# Usage: site-fix-permissions.sh <domain>
# PHP sites only — repair owner/mode after FTP or manual upload.
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"

DOMAIN="${1:-}"
OP_FINALIZED=0

die() {
  OP_FINALIZED=1
  site_op_status_write "${DOMAIN}" "fix-permissions" "error" "$*" 2>/dev/null || true
  echo "{\"ok\":false,\"error\":\"$*\"}" >&2
  exit 1
}

on_exit() {
  if [[ "${OP_FINALIZED}" -eq 0 && -n "${DOMAIN}" ]]; then
    site_op_status_write "${DOMAIN}" "fix-permissions" "error" \
      "Fix permissions interrupted unexpectedly — retry" 2>/dev/null || true
  fi
}

trap on_exit EXIT

[[ -n "${DOMAIN}" ]] || die "Missing domain"
[[ "${DOMAIN}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || die "Invalid domain"

ensure_python3 || die "python3 required — run: sudo dpanel update"

SLUG="$(site_slug "${DOMAIN}")"
LOG="${STACK_ROOT}/logs/node/site-fix-permissions-${SLUG}.log"

mkdir -p "${STACK_ROOT}/logs/node"
: >>"${LOG}"
exec >>"${LOG}" 2>&1
echo "[dpanel] $(date '+%Y-%m-%d %H:%M:%S') site-fix-permissions ${DOMAIN}"

site_op_status_write "${DOMAIN}" "fix-permissions" "running" "Fixing permissions…"

SITES_FILE="${STACK_ROOT}/data/panel/sites.json"
export SITES_FILE DOMAIN
RUNTIME="$("${PYBIN}" -c "
import json, os, sys
with open(os.environ['SITES_FILE']) as f:
    for s in json.load(f):
        if s.get('domain') == os.environ['DOMAIN']:
            print(s.get('runtime') or '')
            sys.exit(0)
sys.exit(1)
" 2>/dev/null)" || die "Site not found in sites.json"

[[ "${RUNTIME}" == "php" ]] || die "Fix permissions is only available for PHP sites"

if ! site_fix_permissions "${DOMAIN}" "full"; then
  die "Fix permissions failed — see log"
fi

OP_FINALIZED=1
site_op_status_write "${DOMAIN}" "fix-permissions" "ok" "Permissions fixed"
trap - EXIT

echo "{\"ok\":true,\"domain\":\"${DOMAIN}\",\"runtime\":\"${RUNTIME}\",\"action\":\"fix-permissions\"}"
