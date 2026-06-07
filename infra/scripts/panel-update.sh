#!/usr/bin/env bash
# Triggered from the panel UI — runs panel-update-host.sh as root on the VPS host.
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"

LOG="${STACK_ROOT}/logs/panel/dpanel-update.log"

die() {
  system_update_status_write "error" "$*" 2>/dev/null || true
  echo "{\"ok\":false,\"error\":\"$*\"}" >&2
  exit 1
}

mkdir -p "${STACK_ROOT}/logs/panel"
: >"${LOG}"

exec >>"${LOG}" 2>&1
echo "[dpanel] $(date '+%Y-%m-%d %H:%M:%S') panel-update (from UI)"

system_update_status_write "running" "Starting dpanel update…" || true

command -v docker >/dev/null 2>&1 || die "docker CLI not available"
docker info >/dev/null 2>&1 || die "Cannot reach Docker daemon"

if ! docker run --rm --privileged -v /:/host alpine:3.20 sh -c '
  exec chroot /host env STACK_ROOT=/opt/stack bash /opt/stack/infra/scripts/panel-update-host.sh
'; then
  die "dpanel update failed — see log"
fi

echo "[dpanel] panel-update trigger finished"
