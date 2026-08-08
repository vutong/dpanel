#!/usr/bin/env bash
# Triggered from the panel UI — runs panel-update-host.sh as root on the VPS host.
# Caller (beginSystemUpdate) already force-killed prior jobs and cleared the lock/log.
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"

LOG="${STACK_ROOT}/logs/panel/dpanel-update.log"
LOCKDIR="${STACK_ROOT}/data/panel/.update-lock"

die() {
  system_update_status_write "error" "$*" 2>/dev/null || true
  echo "[dpanel] ERROR: $*" | tee -a "${LOG}" >&2
  echo "{\"ok\":false,\"error\":\"$*\"}" >&2
  exit 1
}

mkdir -p "${STACK_ROOT}/logs/panel" "${STACK_ROOT}/data/panel"

# Take lock (beginSystemUpdate may have already created it as a "starting" marker).
if ! mkdir "${LOCKDIR}" 2>/dev/null; then
  # Already held by beginSystemUpdate in this same run — keep it.
  if [[ ! -d "${LOCKDIR}" ]]; then
    die "Could not acquire update lock — try again"
  fi
fi
trap 'rmdir "${LOCKDIR}" 2>/dev/null || true' EXIT

{
  echo "[dpanel] $(date '+%Y-%m-%d %H:%M:%S') panel-update (from UI) — fresh start"
  echo "[dpanel] Same as: sudo dpanel update"
  echo "[dpanel] Streaming log: ${LOG}"
} | tee -a "${LOG}" >&2

system_update_status_write "running" "Starting dpanel update…" || true

command -v docker >/dev/null 2>&1 || die "docker CLI not available"
docker info >/dev/null 2>&1 || die "Cannot reach Docker daemon"

echo "[dpanel] Launching host update via privileged alpine chroot…" | tee -a "${LOG}" >&2

# --network host: chroot uses host /etc/resolv.conf (often 127.0.0.53). In bridge mode
# that nameserver is unreachable inside the container, so git/curl cannot resolve GitHub.
# Do NOT redirect docker into LOG — update.sh already appends to INSTALL_LOG.
if ! docker run --rm --privileged --network host -v /:/host alpine:3.20 sh -c \
  'exec chroot /host env STACK_ROOT=/opt/stack bash /opt/stack/infra/scripts/panel-update-host.sh'; then
  die "dpanel update failed — see log above"
fi

echo "[dpanel] panel-update finished OK" | tee -a "${LOG}" >&2
