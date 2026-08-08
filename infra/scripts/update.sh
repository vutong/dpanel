#!/usr/bin/env bash
# Pull latest dpanel from GitHub, sync stack (keep data/sites/.env), rebuild, restart.
#
#   dpanel update              Full update (includes nginx-reload + health --fix)
#   dpanel update --check      Compare local vs remote version only
#   dpanel update --no-build   Sync infra/compose only, skip Nuxt rebuild
#
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
INSTALL_LOG="${INSTALL_LOG:-/var/log/dpanel-update.log}"
DPANEL_REPO="${DPANEL_REPO:-https://github.com/vutong/dpanel.git}"
DPANEL_BRANCH="${DPANEL_BRANCH:-main}"
RAW_REPO_BASE="${DPANEL_RAW_BASE:-https://raw.githubusercontent.com/vutong/dpanel}"

CHECK_ONLY=0
SKIP_BUILD=0
SKIP_HEALTH_FIX=0
SKIP_NGINX_RELOAD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_ONLY=1; shift ;;
    --no-build) SKIP_BUILD=1; shift ;;
    --no-health-fix) SKIP_HEALTH_FIX=1; shift ;;
    --no-nginx-reload) SKIP_NGINX_RELOAD=1; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: dpanel update [--check] [--no-build] [--no-health-fix] [--no-nginx-reload]

  Full update: sync → rebuild → docker up → health --fix → nginx-reload (once)

  --check            Show installed vs latest version (no changes)
  --no-build         Sync files and containers only; skip Nuxt rebuild
  --no-health-fix    Skip automatic health --fix at end of update
  --no-nginx-reload  Skip nginx-reload (not recommended)
EOF
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

log() {
  local line="[dpanel] $(date '+%Y-%m-%d %H:%M:%S') $*"
  printf '%s\n' "$line" | tee -a "${INSTALL_LOG}" >&2
}

die() {
  log "ERROR: $*"
  exit 1
}

[[ "${EUID:-0}" -eq 0 ]] || die "Run as root: sudo dpanel update"

[[ -d "${STACK_ROOT}" && -f "${STACK_ROOT}/.env" ]] || die "Stack not found at ${STACK_ROOT}"

# shellcheck source=/dev/null
source "${STACK_ROOT}/.env"

PANEL_DOMAIN="${PANEL_DOMAIN:?PANEL_DOMAIN not set in .env}"
DPANEL_REPO="${DPANEL_REPO:-https://github.com/vutong/dpanel.git}"
DPANEL_BRANCH="${DPANEL_BRANCH:-main}"

read_local_version() {
  if [[ -f "${STACK_ROOT}/data/panel/version.json" ]]; then
    python3 -c "import json; print(json.load(open('${STACK_ROOT}/data/panel/version.json')).get('version',''))" 2>/dev/null || true
  fi
  grep -E '^DPANEL_VERSION=' "${STACK_ROOT}/.env" 2>/dev/null | cut -d= -f2- || true
}

read_remote_version() {
  local url="${RAW_REPO_BASE}/${DPANEL_BRANCH}/install.sh"
  curl -fsSL --max-time 30 "${url}" 2>/dev/null \
    | grep -E '^INSTALLER_VERSION=' \
    | head -1 \
    | sed 's/^INSTALLER_VERSION="\(.*\)"$/\1/' \
    || true
}

set_env_version() {
  local ver="$1"
  if grep -q '^DPANEL_VERSION=' "${STACK_ROOT}/.env"; then
    sed -i "s/^DPANEL_VERSION=.*/DPANEL_VERSION=${ver}/" "${STACK_ROOT}/.env"
  else
    echo "DPANEL_VERSION=${ver}" >> "${STACK_ROOT}/.env"
  fi
  mkdir -p "${STACK_ROOT}/data/panel"
  python3 - "${STACK_ROOT}/data/panel/version.json" "${ver}" <<'PY'
import json
import sys
from datetime import datetime, timezone

path, ver = sys.argv[1], sys.argv[2]
data = {"version": ver, "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
try:
    with open(path, encoding="utf-8") as f:
        old = json.load(f)
    data["previous_version"] = old.get("version")
except (FileNotFoundError, json.JSONDecodeError):
    pass
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f)
PY
}

LOCAL_VER="$(read_local_version | head -1 | tr -d '[:space:]')"
REMOTE_VER="$(read_remote_version | tr -d '[:space:]')"

if [[ -z "${LOCAL_VER}" ]]; then
  LOCAL_VER="$(grep -E '^INSTALLER_VERSION=' "${STACK_ROOT}/.env" 2>/dev/null | cut -d= -f2- || echo unknown)"
fi

if [[ "${CHECK_ONLY}" -eq 1 ]]; then
  echo "Installed: ${LOCAL_VER:-unknown}"
  echo "Latest:    ${REMOTE_VER:-unknown (network or branch ${DPANEL_BRANCH})}"
  if [[ -n "${REMOTE_VER}" && -n "${LOCAL_VER}" && "${LOCAL_VER}" == "${REMOTE_VER}" ]]; then
    echo "Status:    up to date"
    exit 0
  fi
  if [[ -n "${REMOTE_VER}" && -n "${LOCAL_VER}" ]]; then
    echo "Status:    update available — run: dpanel update"
    exit 2
  fi
  exit 0
fi

if [[ -n "${REMOTE_VER}" && -n "${LOCAL_VER}" && "${LOCAL_VER}" == "${REMOTE_VER}" ]]; then
  log "Already at version ${LOCAL_VER}"
  if [[ "${SKIP_BUILD}" -eq 1 ]]; then
    exit 0
  fi
  log "Continuing (rebuild/restart requested)"
fi

# Phase 1: download + rsync, then re-exec so build/nginx use the new scripts on disk.
if [[ "${DPANEL_UPDATE_REEXEC:-}" != 1 ]]; then
  log "Update start — local ${LOCAL_VER:-?} → remote ${REMOTE_VER:-?}"
  log "Repo: ${DPANEL_REPO} (${DPANEL_BRANCH})"
  log "Log: ${INSTALL_LOG}"

  CLONE_TMP="$(mktemp -d)"
  cleanup() { rm -rf "${CLONE_TMP}"; }
  trap cleanup EXIT

  export GIT_TERMINAL_PROMPT=0
  log "Downloading source..."
  git clone --depth 1 --branch "${DPANEL_BRANCH}" "${DPANEL_REPO}" "${CLONE_TMP}" >> "${INSTALL_LOG}" 2>&1 \
    || die "git clone failed — check ${INSTALL_LOG}"

  systemctl stop unattended-upgrades.service unattended-upgrades.timer 2>/dev/null || true

  log "Syncing stack (keeping .env, data/, apps/, logs/, compose.d/)..."
  rsync -a \
    --exclude '.git' \
    --exclude 'node_modules' \
    --exclude '.output' \
    --exclude '.nuxt' \
    --exclude '.env' \
    --exclude 'data/' \
    --exclude 'apps/' \
    --exclude 'logs/' \
    --exclude 'compose.d/' \
    --exclude 'CREDENTIALS.txt' \
    "${CLONE_TMP}/" "${STACK_ROOT}/"

  chmod +x "${STACK_ROOT}/infra/scripts/"*.sh
  ln -sf "${STACK_ROOT}/infra/scripts/dpanel-cli.sh" /usr/local/bin/dpanel

  mkdir -p "${STACK_ROOT}/data/panel" "${STACK_ROOT}/infra/nginx/conf.d" "${STACK_ROOT}/compose.d"
  [[ -f "${STACK_ROOT}/data/panel/sites.json" ]] || echo '[]' > "${STACK_ROOT}/data/panel/sites.json"

  if grep -q '^DPANEL_REPO=' "${STACK_ROOT}/.env"; then
    sed -i "s|^DPANEL_REPO=.*|DPANEL_REPO=${DPANEL_REPO}|" "${STACK_ROOT}/.env"
  else
    echo "DPANEL_REPO=${DPANEL_REPO}" >> "${STACK_ROOT}/.env"
  fi
  if grep -q '^DPANEL_BRANCH=' "${STACK_ROOT}/.env"; then
    sed -i "s/^DPANEL_BRANCH=.*/DPANEL_BRANCH=${DPANEL_BRANCH}/" "${STACK_ROOT}/.env"
  else
    echo "DPANEL_BRANCH=${DPANEL_BRANCH}" >> "${STACK_ROOT}/.env"
  fi

  trap - EXIT
  rm -rf "${CLONE_TMP}"
  export DPANEL_UPDATE_REEXEC=1
  exec bash "${STACK_ROOT}/infra/scripts/update.sh" "$@"
fi

NEW_VER="$(grep -E '^INSTALLER_VERSION=' "${STACK_ROOT}/install.sh" | head -1 | sed 's/^INSTALLER_VERSION="\(.*\)"$/\1/' || echo "${REMOTE_VER}")"

# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"
ensure_python3 >> "${INSTALL_LOG}" 2>&1 || log "Warning: python3 not available — some scripts may fail"

# MariaDB: only root — no default dpanel database/user (panel uses JSON files).
if [[ -f "${STACK_ROOT}/.env" ]]; then
  sed -i '/^MARIADB_DATABASE=/d; /^MARIADB_USER=/d; /^MARIADB_PASSWORD=/d' "${STACK_ROOT}/.env" 2>/dev/null || true
fi

log "Migrating compose nuxt-* → node-* (if any)..."
bash "${STACK_ROOT}/infra/scripts/migrate-nuxt-to-node.sh" >> "${INSTALL_LOG}" 2>&1 \
  || log "Warning: nuxt→node migrate had issues — see ${INSTALL_LOG}"

run_nginx_reload() {
  [[ "${SKIP_NGINX_RELOAD}" -eq 0 ]] || return 0
  log "dpanel nginx-reload"
  bash "${STACK_ROOT}/infra/scripts/nginx-reload.sh" || die "nginx-reload failed"
}

if [[ "${SKIP_BUILD}" -eq 0 ]]; then
  log "Rebuilding panel..."
  bash "${STACK_ROOT}/infra/scripts/update-panel.sh" >> "${INSTALL_LOG}" 2>&1 \
    || die "Panel rebuild failed — see ${INSTALL_LOG}"
else
  log "Skipping panel rebuild (--no-build)"
fi

log "Rebuilding Docker services (including compose.d sites)..."
cd "${STACK_ROOT}"
stack_compose build >> "${INSTALL_LOG}" 2>&1 || die "docker compose build failed"
stack_compose up -d --remove-orphans >> "${INSTALL_LOG}" 2>&1 || die "docker compose up failed"

export STACK_ROOT
log "Waiting for panel container..."
wait_for_dpanel_ready 90 >> "${INSTALL_LOG}" 2>&1 || log "Panel still warming up — health will retry"

[[ -n "${NEW_VER}" ]] && set_env_version "${NEW_VER}"

systemctl start unattended-upgrades.service unattended-upgrades.timer 2>/dev/null || true

if [[ "${SKIP_HEALTH_FIX}" -eq 0 && -f "${STACK_ROOT}/infra/scripts/health-check.sh" ]]; then
  log "dpanel health --fix (quick — nginx-reload runs once after)"
  export DPANEL_HEALTH_FROM_UPDATE=1
  _health_cmd=(bash "${STACK_ROOT}/infra/scripts/health-check.sh" --fix --from-update)
  if command -v stdbuf >/dev/null 2>&1; then
    _health_cmd=(stdbuf -oL -eL "${_health_cmd[@]}")
  fi
  if ! "${_health_cmd[@]}" 2>&1 | tee -a "${INSTALL_LOG}"; then
    if stack_compose ps --format '{{.Service}} {{.State}}' 2>/dev/null | grep -qE '^nginx running' \
      && stack_compose ps --format '{{.Service}} {{.State}}' 2>/dev/null | grep -qE '^dpanel running'; then
      log "WARNING: optional health checks failed — nginx and panel are running."
      log "Details: sudo dpanel health"
    else
      die "Health check failed — run: sudo dpanel health"
    fi
  fi
fi

run_nginx_reload

log "Update complete — version ${NEW_VER:-${REMOTE_VER:-?}}"
log "Panel: http://${PANEL_DOMAIN}"
