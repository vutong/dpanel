#!/usr/bin/env bash
# Remove dpanel stack (containers + /opt/stack). Data is deleted.
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"

[[ "${EUID:-0}" -eq 0 ]] || { echo "Run as root." >&2; exit 1; }

if [[ "${DPANEL_UNINSTALL_CONFIRM:-}" != "YES" ]]; then
  echo "This removes ${STACK_ROOT} and all Docker containers for dpanel."
  echo "Type YES to confirm:"
  read -r ans
  [[ "${ans}" == "YES" ]] || { echo "Aborted."; exit 1; }
fi

if [[ -f "${STACK_ROOT}/compose.yml" ]]; then
  cd "${STACK_ROOT}"
  docker compose down --remove-orphans 2>/dev/null || true
fi

rm -f /usr/local/bin/dpanel 2>/dev/null || true
rm -rf "${STACK_ROOT}"

echo "[dpanel] Uninstalled."
