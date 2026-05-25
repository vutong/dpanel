#!/usr/bin/env bash
#
# Run the installer in GNU screen — foreground UX, survives SSH disconnect.
#
#   curl -fsSLO https://raw.githubusercontent.com/vutong/dpanel/main/install.sh
#   curl -fsSLO https://raw.githubusercontent.com/vutong/dpanel/main/install-screen.sh
#   sudo bash install-screen.sh
#
# Detach: Ctrl+A then D
# Reattach: sudo screen -r dpanel-install
#
set -eu

SESSION_NAME="${DPANEL_SCREEN_SESSION:-dpanel-install}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="${DIR}/install.sh"
[[ -f "${INSTALL_SCRIPT}" ]] || INSTALL_SCRIPT="./install.sh"
[[ -f "${INSTALL_SCRIPT}" ]] || { echo "install.sh not found next to install-screen.sh"; exit 1; }

[[ "${EUID:-0}" -eq 0 ]] || exec sudo -E bash "$0" "$@"

if [[ -n "${STY:-}" || -n "${TMUX:-}" ]]; then
  exec bash "${INSTALL_SCRIPT}" "$@"
fi

if ! command -v screen >/dev/null 2>&1; then
  echo "[dpanel] Installing screen..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y screen
fi

if screen -ls 2>/dev/null | grep -qE "[[:space:]]+[0-9]+\.${SESSION_NAME}[[:space:]]"; then
  echo "Screen session '${SESSION_NAME}' already running."
  echo "  Attach: sudo screen -r ${SESSION_NAME}"
  echo "  Kill:   sudo screen -S ${SESSION_NAME} -X quit"
  exec screen -r "${SESSION_NAME}"
fi

echo "=============================================="
echo "  dpanel install (GNU screen)"
echo "=============================================="
echo "You will see live progress here (like aaPanel / CyberPanel)."
echo ""
echo "  Detach (install keeps running): Ctrl+A then D"
echo "  Reattach later:                 sudo screen -r ${SESSION_NAME}"
echo "  Second terminal tail:         tail -f /var/log/dpanel-install-console.log"
echo ""
sleep 1

# Detached session + attach: stable TTY for prompts (direct "screen bash script" often exits instantly)
screen -dmS "${SESSION_NAME}" env TERM="${TERM:-xterm-256color}" bash -l -c "exec bash '${INSTALL_SCRIPT}'"
sleep 1

if ! screen -ls 2>/dev/null | grep -qE "[[:space:]]+[0-9]+\.${SESSION_NAME}[[:space:]]"; then
  echo "Screen session ended immediately — install.sh may have failed."
  echo "  Log:    tail -30 /var/log/dpanel-install.log"
  echo "  Direct: sudo bash '${INSTALL_SCRIPT}'"
  exit 1
fi

if screen -ls 2>/dev/null | grep -qE "[[:space:]]+[0-9]+\.${SESSION_NAME}[[:space:]]+.*Dead"; then
  echo "Install already finished or crashed. Last log lines:"
  tail -30 /var/log/dpanel-install.log 2>/dev/null || true
  exit 1
fi

exec screen -r "${SESSION_NAME}"
