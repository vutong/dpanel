#!/usr/bin/env bash
# Run installer detached from SSH (survives disconnect). Usage:
#   curl -fsSLO https://raw.githubusercontent.com/vutong/dpanel/main/install-background.sh
#   curl -fsSLO https://raw.githubusercontent.com/vutong/dpanel/main/install.sh
#   sudo bash install-background.sh
set -eu

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONSOLE_LOG="${DPANEL_CONSOLE_LOG:-/var/log/dpanel-install-console.log}"
INSTALL_SCRIPT="${DIR}/install.sh"

[[ -f "${INSTALL_SCRIPT}" ]] || INSTALL_SCRIPT="./install.sh"
[[ -f "${INSTALL_SCRIPT}" ]] || { echo "install.sh not found in ${DIR}"; exit 1; }

echo "Starting dpanel install in background."
echo "  Console log: ${CONSOLE_LOG}"
echo "  Install log: /var/log/dpanel-install.log"
echo "  Watch: tail -f ${CONSOLE_LOG}"

nohup bash "${INSTALL_SCRIPT}" >> "${CONSOLE_LOG}" 2>&1 &
echo "PID: $!"
echo "Do not close this terminal until you see 'installed successfully' in the log."
