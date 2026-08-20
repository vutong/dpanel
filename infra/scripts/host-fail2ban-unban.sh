#!/usr/bin/env bash
# Unban an IP from all fail2ban jails (or a specific jail).
set -euo pipefail

IP="${1:-}"
JAIL="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host-chroot.sh
source "${SCRIPT_DIR}/host-chroot.sh"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

[[ -n "${IP}" ]] || die "IP required"
[[ "${IP}" =~ ^[0-9a-fA-F:.]+$ ]] || die "Invalid IP"

if [[ -n "${JAIL}" ]]; then
  CMD="fail2ban-client set ${JAIL} unbanip ${IP}"
else
  CMD="
set -e
if ! command -v fail2ban-client >/dev/null 2>&1; then
  echo 'fail2ban not installed' >&2; exit 1
fi
for jail in \$(fail2ban-client status 2>/dev/null | sed -n 's/^Jail list:[[:space:]]*//p' | tr ',' ' '); do
  jail=\$(echo \"\$jail\" | xargs)
  [[ -n \"\$jail\" ]] && fail2ban-client set \"\$jail\" unbanip '${IP}' 2>/dev/null || true
done
"
fi

if [[ -f /.dockerenv ]] && command -v docker >/dev/null 2>&1; then
  host_exec "${CMD}" >/dev/null 2>&1 || die "Unban failed"
else
  bash -lc "${CMD}" >/dev/null 2>&1 || die "Unban failed"
fi

echo "{\"ok\":true,\"ip\":\"${IP}\",\"jail\":\"${JAIL}\"}"
