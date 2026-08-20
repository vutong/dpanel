#!/usr/bin/env bash
# Install Fail2ban on VPS host and sync dpanel jail configs.
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host-chroot.sh
source "${SCRIPT_DIR}/host-chroot.sh"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || die "python3 required"

INSTALL_CMD="
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y fail2ban
STACK=${STACK_ROOT}
if [[ -d \"\${STACK}/infra/security/fail2ban/filter.d\" ]]; then
  cp \"\${STACK}/infra/security/fail2ban/filter.d/\"*.conf /etc/fail2ban/filter.d/ 2>/dev/null || true
fi
if [[ -d \"\${STACK}/infra/security/fail2ban/jail.d\" ]]; then
  cp \"\${STACK}/infra/security/fail2ban/jail.d/\"*.conf /etc/fail2ban/jail.d/ 2>/dev/null || true
fi
systemctl enable fail2ban 2>/dev/null || true
systemctl restart fail2ban 2>/dev/null || systemctl start fail2ban 2>/dev/null || true
echo install_ok
"

_run_install() {
  if [[ -f /.dockerenv ]] && command -v docker >/dev/null 2>&1; then
    docker info >/dev/null 2>&1 || die "Cannot reach Docker daemon"
    local out=""
    out="$(host_exec_capture "${INSTALL_CMD}")" || die "${out:-Fail2ban install failed}"
  else
    [[ "${EUID:-0}" -eq 0 ]] || die "Run as root on host"
    bash -lc "${INSTALL_CMD}" || die "Fail2ban install failed"
  fi
}

_run_install

# Seed panel settings file if missing
SETTINGS="${STACK_ROOT}/data/panel/fail2ban-settings.json"
if [[ ! -f "${SETTINGS}" ]]; then
  mkdir -p "${STACK_ROOT}/data/panel"
  cat > "${SETTINGS}" << 'EOF'
{
  "ignoreip": ["127.0.0.1/8", "::1"],
  "jails": {
    "sshd": { "enabled": true, "maxretry": 5, "findtime": 600, "bantime": 3600, "bantimeIncrement": true },
    "nginx-dpanel-login": { "enabled": true, "maxretry": 5, "findtime": 600, "bantime": 3600, "bantimeIncrement": true },
    "nginx-php-exploit": { "enabled": true, "maxretry": 10, "findtime": 600, "bantime": 7200, "bantimeIncrement": false }
  }
}
EOF
fi

bash "${SCRIPT_DIR}/host-fail2ban-config-apply.sh" 2>/dev/null || true
bash "${SCRIPT_DIR}/host-security-status.sh"
