#!/usr/bin/env bash
# Install Fail2ban + ClamAV on VPS host and sync dpanel jail configs.
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host-chroot.sh
source "${SCRIPT_DIR}/host-chroot.sh"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

[[ -n "${PYBIN:-}" ]] || command -v python3 >/dev/null 2>&1 || die "python3 required"

INSTALL_CMD="
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y fail2ban clamav clamav-daemon clamav-freshclam
STACK=${STACK_ROOT}
if [[ -d \"\${STACK}/infra/security/fail2ban/filter.d\" ]]; then
  cp \"\${STACK}/infra/security/fail2ban/filter.d/\"*.conf /etc/fail2ban/filter.d/ 2>/dev/null || true
fi
if [[ -d \"\${STACK}/infra/security/fail2ban/jail.d\" ]]; then
  cp \"\${STACK}/infra/security/fail2ban/jail.d/\"*.conf /etc/fail2ban/jail.d/ 2>/dev/null || true
fi
systemctl enable fail2ban clamav-daemon clamav-freshclam 2>/dev/null || true
systemctl restart fail2ban 2>/dev/null || systemctl start fail2ban 2>/dev/null || true
systemctl restart clamav-freshclam 2>/dev/null || true
# Initial signature update (best-effort, may take a while)
freshclam 2>/dev/null || true
systemctl restart clamav-daemon 2>/dev/null || systemctl start clamav-daemon 2>/dev/null || true
echo install_ok
"

if [[ -f /.dockerenv ]] && command -v docker >/dev/null 2>&1; then
  if ! docker info >/dev/null 2>&1; then
    die "Cannot reach Docker daemon"
  fi
  OUT="$(host_exec_capture "${INSTALL_CMD}")" || die "Host install failed: ${OUT:0:500}"
else
  if [[ "${EUID:-0}" -ne 0 ]]; then
    die "Run as root on host"
  fi
  OUT="$(bash -lc "${INSTALL_CMD}")" || die "Install failed"
fi

# Return refreshed status
bash "${SCRIPT_DIR}/host-security-status.sh"
