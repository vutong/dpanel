#!/usr/bin/env bash
# Reload fail2ban service on host.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host-chroot.sh
source "${SCRIPT_DIR}/host-chroot.sh"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

CMD="
if ! command -v fail2ban-client >/dev/null 2>&1; then
  echo 'fail2ban not installed' >&2; exit 1
fi
fail2ban-client reload
"

if [[ -f /.dockerenv ]] && command -v docker >/dev/null 2>&1; then
  host_exec "${CMD}" >/dev/null 2>&1 || die "Reload failed"
else
  bash -lc "${CMD}" >/dev/null 2>&1 || die "Reload failed"
fi

echo '{"ok":true,"reloaded":true}'
