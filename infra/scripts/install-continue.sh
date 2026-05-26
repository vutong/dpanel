#!/usr/bin/env bash
# Resume a failed or partial install (build panel → deploy → docker up → nginx).
# Usage: sudo bash /opt/stack/infra/scripts/install-continue.sh
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
INSTALL_LOG="${INSTALL_LOG:-/var/log/dpanel-install.log}"

log() {
  local line="[dpanel] $(date '+%Y-%m-%d %H:%M:%S') $*"
  printf '%s\n' "$line" | tee -a "${INSTALL_LOG}" >&2
}

die() {
  log "ERROR: $*"
  exit 1
}

[[ "${EUID:-0}" -eq 0 ]] || die "Run as root: sudo bash install-continue.sh"
[[ -f "${STACK_ROOT}/.env" ]] || die "Missing ${STACK_ROOT}/.env — run install.sh first"

cd "${STACK_ROOT}"
# shellcheck source=/dev/null
source .env
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"

PANEL_DOMAIN="${PANEL_DOMAIN:?PANEL_DOMAIN not set in .env}"
PANEL_SRC="${STACK_ROOT}/panel"
APP_DIR="${STACK_ROOT}/apps/${PANEL_DOMAIN}"

log "Continuing install at ${STACK_ROOT} (panel: ${PANEL_DOMAIN})"

chmod +x "${STACK_ROOT}/infra/scripts/"*.sh
ln -sf "${STACK_ROOT}/infra/scripts/dpanel-cli.sh" /usr/local/bin/dpanel 2>/dev/null || true

if [[ ! -f "${PANEL_SRC}/.output/server/index.mjs" ]]; then
  log "Building panel..."
  bash "${STACK_ROOT}/infra/scripts/build-panel.sh" "${PANEL_SRC}" || die "Panel build failed"
else
  log "Panel build output exists — skipping build (delete .output to rebuild)"
fi

log "Deploying panel to ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}"
rsync -a "${PANEL_SRC}/.output/" "${APP_DIR}/.output/"
rsync -a "${PANEL_SRC}/package.json" "${PANEL_SRC}/node_modules" "${APP_DIR}/" 2>/dev/null || true

log "Starting Docker stack..."
stack_compose build || die "docker compose build failed"
stack_compose up -d --remove-orphans || die "docker compose up failed"

log "Configuring nginx..."
bash "${STACK_ROOT}/infra/scripts/nginx-reload.sh" || die "nginx-reload failed"

log "Waiting for panel..."
if wait_for_dpanel_ready 120; then
  log "Panel is healthy"
else
  log "Warning: panel not ready yet — run: dpanel logs dpanel"
fi

if [[ -f "${STACK_ROOT}/infra/scripts/health-check.sh" ]]; then
  bash "${STACK_ROOT}/infra/scripts/health-check.sh" --fix || log "Warning: health-check reported issues"
fi

log "Resume complete — http://${PANEL_DOMAIN}"
log "CLI: dpanel status | dpanel health"
