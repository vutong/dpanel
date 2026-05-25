#!/usr/bin/env bash
# Wrap install.sh in GNU screen (SSH-safe). Usage: sudo bash install-screen.sh
set -eu

SESSION_NAME="${DPANEL_SCREEN_SESSION:-dpanel-install}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="${DIR}/install.sh"
[[ -f "${INSTALL_SCRIPT}" ]] || INSTALL_SCRIPT="./install.sh"
[[ -f "${INSTALL_SCRIPT}" ]] || { echo "[dpanel] install.sh not found in ${DIR}"; exit 1; }

[[ "${EUID:-0}" -eq 0 ]] || exec sudo -E bash "$0" "$@"

if [[ -n "${STY:-}" ]]; then
  exec bash "${INSTALL_SCRIPT}" "$@"
fi

if ! command -v screen >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y screen
fi

if screen -ls 2>/dev/null | grep -qE "[[:space:]]+[0-9]+\.${SESSION_NAME}[[:space:]]"; then
  exec screen -r "${SESSION_NAME}"
fi

printf '[dpanel] Session: %s | Detach: Ctrl+A D | Reattach: screen -r %s\n' \
  "${SESSION_NAME}" "${SESSION_NAME}"

# -m: allocate TTY; keep shell open on failure
exec screen -S "${SESSION_NAME}" -m bash -c "
  set +e
  export DPANEL_IN_SCREEN=1
  bash '${INSTALL_SCRIPT}'
  ec=\$?
  echo
  if [[ \$ec -eq 0 ]]; then
    echo '[dpanel] Install completed.'
  else
    echo \"[dpanel] Install failed (exit \$ec). See /var/log/dpanel-install.log\"
    tail -20 /var/log/dpanel-install.log 2>/dev/null || true
  fi
  exec \"\${SHELL:-/bin/bash}\" -l
"
