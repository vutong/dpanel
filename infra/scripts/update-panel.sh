#!/usr/bin/env bash
# Rebuild and redeploy the Nuxt panel only (no full reinstall).
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
INSTALL_LOG="${INSTALL_LOG:-/var/log/dpanel-update.log}"

log() { echo "[dpanel] $*" | tee -a "${INSTALL_LOG}" >&2; }

[[ "${EUID:-0}" -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
cd "${STACK_ROOT}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"
# shellcheck source=/dev/null
[[ -f .env ]] && source .env

PANEL_DOMAIN="${PANEL_DOMAIN:?PANEL_DOMAIN not set in .env}"
PANEL_SRC="${STACK_ROOT}/panel"
APP_DIR="${STACK_ROOT}/apps/${PANEL_DOMAIN}"

chmod +x "${STACK_ROOT}/infra/scripts/build-panel.sh"
bash "${STACK_ROOT}/infra/scripts/build-panel.sh" "${PANEL_SRC}" || {
  log "Panel build failed — see output above or ${INSTALL_LOG}"
  exit 1
}

log "Deploying to ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}"
rsync -a "${PANEL_SRC}/.output/" "${APP_DIR}/.output/"
rsync -a "${PANEL_SRC}/package.json" "${PANEL_SRC}/node_modules" "${APP_DIR}/" 2>/dev/null || true

stack_compose restart dpanel
log "Panel updated. URL: http://${PANEL_DOMAIN}"
