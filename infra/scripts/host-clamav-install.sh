#!/usr/bin/env bash
# Install ClamAV on VPS host.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host-chroot.sh
source "${SCRIPT_DIR}/host-chroot.sh"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || die "python3 required"

INSTALL_CMD="
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y clamav clamav-daemon clamav-freshclam
systemctl enable clamav-daemon clamav-freshclam 2>/dev/null || true
systemctl restart clamav-freshclam 2>/dev/null || true
freshclam 2>/dev/null || true
systemctl restart clamav-daemon 2>/dev/null || systemctl start clamav-daemon 2>/dev/null || true
echo install_ok
"

_run_install() {
  if [[ -f /.dockerenv ]] && command -v docker >/dev/null 2>&1; then
    docker info >/dev/null 2>&1 || die "Cannot reach Docker daemon"
    local out=""
    out="$(host_exec_capture "${INSTALL_CMD}")" || die "${out:-ClamAV install failed}"
  else
    [[ "${EUID:-0}" -eq 0 ]] || die "Run as root on host"
    bash -lc "${INSTALL_CMD}" || die "ClamAV install failed"
  fi
}

_run_install
bash "${SCRIPT_DIR}/host-security-status.sh"
