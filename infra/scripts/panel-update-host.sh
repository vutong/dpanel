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
  echo "[dpanel] ERROR: $*" | tee -a "${LOG}" >&2
  exit 1
}

{
  echo "[dpanel] $(date '+%Y-%m-%d %H:%M:%S') host: running update.sh (same as sudo dpanel update)"
  echo "[dpanel] Phases: sync → rebuild panel → docker up → health → nginx-reload"
} | tee -a "${LOG}" >&2

system_update_status_write "running" "Downloading & applying update…" || true

# update.sh appends to INSTALL_LOG (this file) and prints to stderr for the terminal.
if bash "${STACK_ROOT}/infra/scripts/update.sh"; then
  system_update_status_write "ok" "Update complete — panel may have restarted briefly"
  echo "[dpanel] $(date '+%Y-%m-%d %H:%M:%S') Update complete" | tee -a "${LOG}" >&2
  exit 0
fi

die "dpanel update failed — see log"
