#!/usr/bin/env bash
# Remove dpanel stack: containers, /opt/stack, CLI symlink.
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
PROJECT_NAME="${PROJECT_NAME:-dpanel}"

[[ "${EUID:-0}" -eq 0 ]] || { echo "[dpanel] Run as root." >&2; exit 1; }

if [[ "${DPANEL_UNINSTALL_CONFIRM:-}" != "YES" ]]; then
  echo "[dpanel] This will remove:"
  echo "  - ${STACK_ROOT} (websites, databases, panel data)"
  echo "  - Docker containers/images for project ${PROJECT_NAME}"
  echo "  - /usr/local/bin/dpanel"
  echo ""
  echo "Type YES to confirm:"
  read -r ans </dev/tty 2>/dev/null || read -r ans
  [[ "${ans}" == "YES" ]] || { echo "[dpanel] Aborted."; exit 1; }
fi

log() { echo "[dpanel] $*"; }

if [[ -f "${STACK_ROOT}/compose.yml" ]]; then
  cd "${STACK_ROOT}"
  log "Stopping containers..."
  shopt -s nullglob
  COMPOSE_FILES=(compose.yml)
  for f in compose.d/*.yml; do
    [[ -f "$f" ]] && COMPOSE_FILES+=(-f "$f")
  done
  docker compose "${COMPOSE_FILES[@]}" down --remove-orphans -v 2>/dev/null || \
    docker compose down --remove-orphans -v 2>/dev/null || true
  shopt -u nullglob
fi

# Stop any leftover containers matching project name
while read -r id; do
  [[ -n "$id" ]] && docker rm -f "$id" 2>/dev/null || true
done < <(docker ps -aq --filter "name=${PROJECT_NAME}-" 2>/dev/null || true)

log "Removing ${STACK_ROOT}..."
rm -rf "${STACK_ROOT}"

rm -f /usr/local/bin/dpanel 2>/dev/null || true

if [[ "${DPANEL_PRUNE_IMAGES:-}" == "1" ]]; then
  log "Pruning unused Docker images..."
  docker image prune -af 2>/dev/null || true
fi

log "VPS cleaned. Reinstall:"
log "  curl -fsSLO https://raw.githubusercontent.com/vutong/dpanel/main/install.sh"
log "  sudo bash install.sh"
