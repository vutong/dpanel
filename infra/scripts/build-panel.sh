#!/usr/bin/env bash
# Build Nuxt panel inside Docker (used by install.sh and update-panel.sh).
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
PANEL_SRC="${1:-${STACK_ROOT}/panel}"
NODE_IMAGE="${NODE_IMAGE:-node:22-alpine}"
export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=2048}"

log() { echo "[dpanel] $*" >&2; }

[[ -f "${PANEL_SRC}/package.json" ]] || {
  log "Missing ${PANEL_SRC}/package.json"
  exit 1
}

if command -v free >/dev/null 2>&1; then
  avail="$(free -m | awk '/^Mem:/ {print $7}')"
  if [[ "${avail:-0}" -lt 800 ]]; then
    log "Warning: low free RAM (${avail}MB). Build may OOM — add 2G swap if it fails."
  fi
fi

log "Pulling ${NODE_IMAGE}..."
docker pull "${NODE_IMAGE}" >&2 || true

log "Running npm install && npm run build..."
if ! docker run --rm \
  -e NODE_OPTIONS \
  -v "${PANEL_SRC}:/app" \
  -w /app \
  "${NODE_IMAGE}" \
  sh -c "npm install --no-audit --no-fund && npm run build"; then
  log "Docker build failed — last npm output may be above"
  exit 1
fi

if [[ ! -f "${PANEL_SRC}/.output/server/index.mjs" ]]; then
  log "Build finished but .output/server/index.mjs is missing"
  exit 1
fi

log "Panel build OK"
