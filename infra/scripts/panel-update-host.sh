#!/usr/bin/env bash
# Runs on the VPS host (root) — same work as: sudo dpanel update
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"

LOG="${STACK_ROOT}/logs/panel/dpanel-update.log"
export INSTALL_LOG="${LOG}"

mkdir -p "${STACK_ROOT}/logs/panel"

die() {
  system_update_status_write "error" "$*" 2>/dev/null || true
  echo "[dpanel] ERROR: $*" >&2
  exit 1
}

system_update_status_write "running" "Running dpanel update…" || true

if bash "${STACK_ROOT}/infra/scripts/update.sh"; then
  system_update_status_write "ok" "Update complete — panel may have restarted briefly"
  exit 0
fi

die "dpanel update failed — see log"
