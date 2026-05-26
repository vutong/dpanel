#!/usr/bin/env bash
#
# dpanel VPS installer
#
#   curl -fsSLO https://raw.githubusercontent.com/vutong/dpanel/main/install.sh
#   sudo bash install.sh
#
# SSH (recommended):
#   curl -fsSLO .../install-screen.sh && sudo bash install-screen.sh
#
# Non-interactive:
#   export DPANEL_NONINTERACTIVE=1 PANEL_DOMAIN=... ADMIN_EMAIL=...
#   sudo -E bash install.sh
# Default login password: 12345678 — change after install: dpanel setpass <password>
#
set -eu

INSTALLER_VERSION="1.0.37"
DEFAULT_ADMIN_PASSWORD="${DEFAULT_ADMIN_PASSWORD:-12345678}"
STACK_ROOT="/opt/stack"
PROJECT_NAME="${PROJECT_NAME:-dpanel}"
DPANEL_REPO="${DPANEL_REPO:-https://github.com/vutong/dpanel.git}"
DPANEL_BRANCH="${DPANEL_BRANCH:-main}"
PANEL_DOMAIN="${PANEL_DOMAIN:-}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-${DEFAULT_ADMIN_PASSWORD}}"
INSTALL_LOG="${INSTALL_LOG:-/var/log/dpanel-install.log}"
TOTAL_STEPS=11
STEP=0
PROGRESS_PID=""

INSTALL_LOG_DIR="$(dirname "${INSTALL_LOG}")"
mkdir -p "${INSTALL_LOG_DIR}" 2>/dev/null || INSTALL_LOG="/tmp/dpanel-install.log"
: >> "${INSTALL_LOG}" 2>/dev/null || INSTALL_LOG="/tmp/dpanel-install.log"

verbose_terminal() {
  [[ "${DPANEL_VERBOSE:-0}" == "1" ]]
}

log() {
  local line="[dpanel] $(date '+%Y-%m-%d %H:%M:%S') $*"
  printf '%s\n' "$line" >> "${INSTALL_LOG}"
  printf '%s\n' "$line" >&2 || true
}

log_detail() {
  printf '%s\n' "$*" >> "${INSTALL_LOG}"
}

die() {
  log "ERROR: $*"
  log "Log file: ${INSTALL_LOG}"
  if [[ -f "${INSTALL_LOG}" ]]; then
    echo "[dpanel] --- last 50 lines of ${INSTALL_LOG} ---" >&2
    tail -50 "${INSTALL_LOG}" >&2 || true
    echo "[dpanel] --- end ---" >&2
  fi
  exit 1
}

on_err() {
  log "Install failed near line ${1:-?}"
}

on_exit() {
  stop_progress 2>/dev/null || true
  [[ -n "${CLONE_TMP:-}" && -d "${CLONE_TMP}" ]] && rm -rf "${CLONE_TMP}"
}

trap 'on_err $LINENO' ERR

step() {
  STEP=$((STEP + 1))
  log "[${STEP}/${TOTAL_STEPS}] $*"
}

start_progress() {
  local label="$1"
  stop_progress 2>/dev/null || true
  (
    local s=0
    while sleep 30; do
      s=$((s + 30))
      printf '[dpanel] %s (%ds)\n' "${label}" "${s}" >&2 || true
    done
  ) &
  PROGRESS_PID=$!
}

stop_progress() {
  if [[ -n "${PROGRESS_PID:-}" ]]; then
    kill "${PROGRESS_PID}" 2>/dev/null || true
    wait "${PROGRESS_PID}" 2>/dev/null || true
    PROGRESS_PID=""
  fi
}

run_cmd() {
  local label="$1"
  shift
  log_detail "--- ${label} ---"
  log_detail "+ $*"
  start_progress "${label}"
  local rc=0
  if verbose_terminal; then
    "$@" 2>&1 | tee -a "${INSTALL_LOG}" || rc="${PIPESTATUS[0]:-1}"
  else
    "$@" >> "${INSTALL_LOG}" 2>&1 || rc=$?
  fi
  stop_progress
  if [[ "$rc" -ne 0 ]]; then
    [[ -f "${STACK_ROOT}/.env" ]] \
      && log "Resume: sudo bash ${STACK_ROOT}/infra/scripts/install-continue.sh"
    die "${label} failed (exit ${rc})"
  fi
}

run_cmd_try() {
  local label="$1"
  shift
  log_detail "--- ${label} (optional) ---"
  log_detail "+ $*"
  start_progress "${label}"
  local rc=0
  "$@" >> "${INSTALL_LOG}" 2>&1 || rc=$?
  stop_progress
  return "$rc"
}

apt_lock_held() {
  pgrep -x apt-get >/dev/null 2>&1 && return 0
  pgrep -x apt >/dev/null 2>&1 && return 0
  pgrep -x dpkg >/dev/null 2>&1 && return 0
  if command -v fuser >/dev/null 2>&1; then
    local f
    for f in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock; do
      [[ -e "$f" ]] || continue
      fuser "$f" >/dev/null 2>&1 && return 0
    done
  fi
  return 1
}

wait_for_apt_lock() {
  local max_wait="${APT_LOCK_WAIT_SEC:-600}"
  local waited=0
  while true; do
    if ! apt_lock_held; then
      break
    fi
    if [[ $waited -eq 0 ]]; then
      log "Waiting for apt lock..."
    elif (( waited % 30 == 0 )); then
      log "Still waiting for apt lock (${waited}s / ${max_wait}s)"
    fi
    if [[ $waited -ge $max_wait ]]; then
      die "apt lock held after ${max_wait}s — run: dpkg --configure -a"
    fi
    sleep 5
    waited=$((waited + 5))
  done
}

apt_get() {
  wait_for_apt_lock
  log_detail "+ apt-get $*"
  local rc=0
  start_progress "apt-get $*"
  if verbose_terminal; then
    apt-get "$@" 2>&1 | tee -a "${INSTALL_LOG}" || rc="${PIPESTATUS[0]:-1}"
  else
    apt-get "$@" >> "${INSTALL_LOG}" 2>&1 || rc=$?
  fi
  stop_progress
  [[ "$rc" -eq 0 ]] || die "apt-get failed: apt-get $*"
}

preflight_checks() {
  step "Preflight"

  if [[ ! -f /etc/os-release ]]; then
    die "Cannot detect OS (Ubuntu 24.04 required)"
  fi
  # shellcheck source=/dev/null
  source /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    die "Unsupported OS: ${ID:-unknown}"
  fi
  if [[ "${VERSION_ID:-}" != "24.04" ]]; then
    log "Warning: tested on Ubuntu 24.04 (detected ${VERSION_ID:-unknown})"
  fi

  local mem_kb
  mem_kb="$(grep MemTotal /proc/meminfo | awk '{print $2}')"
  if [[ "${mem_kb}" -lt 1800000 ]]; then
    log "Warning: less than 2 GB RAM — Nuxt build may need swap (see README)"
  fi
  if [[ "${mem_kb}" -lt 1200000 && ! -f /swapfile ]]; then
    log "Tip: add swap before build: fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile"
  fi

  command -v curl >/dev/null 2>&1 || die "curl is required"
}

tty_print() { printf '%s\n' "$*" >/dev/tty 2>/dev/null || printf '%s\n' "$*"; }

tty_read() {
  local prompt="$1" varname="$2"
  printf '%s' "${prompt}" >/dev/tty 2>/dev/null || printf '%s' "${prompt}"
  if ! read -r "${varname}" </dev/tty 2>/dev/null; then
    if ! read -r "${varname}"; then
      die "No TTY for input — use DPANEL_NONINTERACTIVE=1 or run without screen wrapper issues"
    fi
  fi
}

normalize_domain() {
  local d="$1"
  d="$(echo "$d" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  d="${d#https://}"; d="${d#http://}"; d="${d%%/*}"
  echo "$d"
}

collect_configuration() {
  step "Configuration"

  if [[ -n "${DPANEL_NONINTERACTIVE:-}" ]]; then
    [[ -n "${PANEL_DOMAIN}" && -n "${ADMIN_EMAIL}" ]] \
      || die "Set PANEL_DOMAIN and ADMIN_EMAIL"
    PANEL_DOMAIN="$(normalize_domain "${PANEL_DOMAIN}")"
    ADMIN_PASSWORD="${ADMIN_PASSWORD:-${DEFAULT_ADMIN_PASSWORD}}"
    return
  fi

  if [[ -z "${PANEL_DOMAIN}" ]]; then
    while true; do
      tty_read "Panel domain: " PANEL_DOMAIN
      PANEL_DOMAIN="$(normalize_domain "${PANEL_DOMAIN}")"
      [[ -n "${PANEL_DOMAIN}" ]] || { tty_print "Required."; continue; }
      [[ "${PANEL_DOMAIN}" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] || {
        tty_print "Invalid domain format."; continue
      }
      break
    done
  else
    PANEL_DOMAIN="$(normalize_domain "${PANEL_DOMAIN}")"
  fi

  if [[ -z "${ADMIN_EMAIL:-}" ]]; then
    tty_read "Admin email: " ADMIN_EMAIL
  fi
  [[ -n "${ADMIN_EMAIL}" ]] || die "Email required"

  ADMIN_PASSWORD="${ADMIN_PASSWORD:-${DEFAULT_ADMIN_PASSWORD}}"
  [[ ${#ADMIN_PASSWORD} -ge 6 ]] || die "Password too short (min 6)"

  log "Domain: ${PANEL_DOMAIN} | Email: ${ADMIN_EMAIL}"
  log "Default password: ${DEFAULT_ADMIN_PASSWORD} (change: dpanel setpass <password>)"
}

confirm_existing_stack() {
  if [[ ! -f "${STACK_ROOT}/.env" ]]; then
    return
  fi
  if [[ "${DPANEL_FORCE:-}" == "1" || -n "${DPANEL_NONINTERACTIVE:-}" ]]; then
    log "Existing ${STACK_ROOT} — overwrite panel config (DPANEL_FORCE)"
    return
  fi
  tty_print ""
  tty_print "Existing install at ${STACK_ROOT}. Panel auth will reset; MariaDB data kept."
  local confirm=""
  tty_read "Type YES to continue: " confirm
  [[ "${confirm}" == "YES" ]] || die "Cancelled"
}

write_credentials() {
  local cred="${STACK_ROOT}/CREDENTIALS.txt"
  cat > "${cred}" <<EOF
dpanel installation summary
Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Installer: v${INSTALLER_VERSION}

Panel URL:    http://${PANEL_DOMAIN}
              http://${SERVER_IP}:8080

Login email:  ${ADMIN_EMAIL}
Login pass:   ${ADMIN_PASSWORD}

Change password: dpanel setpass <new-password>

Stack:        ${STACK_ROOT}
Install log:  ${INSTALL_LOG}

CLI: dpanel update | dpanel setpass | dpanel status
EOF
  chmod 600 "${cred}"
}

wait_for_healthy_stack() {
  step "Health check"
  cd "${STACK_ROOT}"
  # shellcheck source=_helpers.sh
  source "${STACK_ROOT}/infra/scripts/_helpers.sh"
  if wait_for_dpanel_ready 120; then
    log "Panel healthy"
    return 0
  fi
  log "Warning: health check timeout — run: dpanel logs dpanel"
}

# --- Main ---
log "dpanel installer v${INSTALLER_VERSION}"
log "Log: ${INSTALL_LOG} (set DPANEL_VERBOSE=1 for full command output on screen)"

[[ "${EUID:-0}" -eq 0 ]] || die "Run as root: sudo bash install.sh"
[[ -r /dev/tty ]] && exec 0</dev/tty

preflight_checks
confirm_existing_stack
collect_configuration

SCRIPT_PATH="${BASH_SOURCE[0]:-}"
USE_LOCAL_SRC=false
if [[ -n "${SCRIPT_PATH}" && "${SCRIPT_PATH}" != "bash" && -f "${SCRIPT_PATH}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
  if [[ -f "${SCRIPT_DIR}/panel/package.json" ]]; then
    USE_LOCAL_SRC=true
    SRC_DIR="${SCRIPT_DIR}"
  fi
fi

CLONE_TMP=""
trap on_exit EXIT

if [[ "${USE_LOCAL_SRC}" == true ]]; then
  step "Local source"
else
  step "Download source"
  CLONE_TMP="$(mktemp -d)"
  export GIT_TERMINAL_PROMPT=0
  run_cmd "git clone" git clone --depth 1 --branch "${DPANEL_BRANCH}" "${DPANEL_REPO}" "${CLONE_TMP}"
  SRC_DIR="${CLONE_TMP}"
fi

step "System packages"
export DEBIAN_FRONTEND=noninteractive
systemctl stop unattended-upgrades.service unattended-upgrades.timer 2>/dev/null || true
apt_get update
if [[ "${DPANEL_FULL_UPGRADE:-0}" == "1" ]]; then
  apt_get upgrade -y
fi
apt_get install -y ca-certificates curl gnupg lsb-release git unzip rsync ufw apache2-utils python3

if ! command -v docker &>/dev/null; then
  step "Docker Engine"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt_get update
  apt_get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
fi

docker compose version &>/dev/null || die "docker compose plugin missing"

if command -v ufw &>/dev/null; then
  ufw allow OpenSSH >/dev/null 2>&1 || true
  ufw allow 80/tcp >/dev/null 2>&1 || true
  ufw allow 443/tcp >/dev/null 2>&1 || true
  ufw allow 8080/tcp >/dev/null 2>&1 || true
  ufw --force enable >/dev/null 2>&1 || true
fi

step "Deploy stack"
mkdir -p "${STACK_ROOT}"
rsync -a --delete \
  --exclude '.git' --exclude 'node_modules' --exclude '.output' --exclude '.nuxt' \
  "${SRC_DIR}/" "${STACK_ROOT}/"

DIRS=(
  "${STACK_ROOT}/apps/${PANEL_DOMAIN}"
  "${STACK_ROOT}/data/panel"
  "${STACK_ROOT}/data/mariadb/volume"
  "${STACK_ROOT}/data/redis/persistence"
  "${STACK_ROOT}/data/redis/dump"
  "${STACK_ROOT}/logs/nginx" "${STACK_ROOT}/logs/node" "${STACK_ROOT}/logs/php"
  "${STACK_ROOT}/logs/mariadb" "${STACK_ROOT}/logs/redis"
  "${STACK_ROOT}/infra/nginx/conf.d" "${STACK_ROOT}/compose.d"
)
for d in "${DIRS[@]}"; do mkdir -p "$d"; done
touch "${STACK_ROOT}/logs/nginx/access.log" "${STACK_ROOT}/logs/nginx/error.log"

ADMIN_HASH="$(htpasswd -nbBC 10 dpanel "${ADMIN_PASSWORD}" | cut -d: -f2)"
cat > "${STACK_ROOT}/data/panel/auth.json" <<EOF
{"email":"${ADMIN_EMAIL}","passwordHash":"${ADMIN_HASH}"}
EOF
chmod 600 "${STACK_ROOT}/data/panel/auth.json"
echo '[]' > "${STACK_ROOT}/data/panel/sites.json"
STACK_ROOT="${STACK_ROOT}" INSTALLER_VERSION="${INSTALLER_VERSION}" python3 <<'PY' 2>/dev/null || true
import json, os
from datetime import datetime, timezone
root = os.environ["STACK_ROOT"]
ver = os.environ["INSTALLER_VERSION"]
path = os.path.join(root, "data", "panel", "version.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump({"version": ver, "installed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}, f)
PY

NEW_ENV_CREATED=0
if [[ ! -f "${STACK_ROOT}/.env" ]]; then
  NEW_ENV_CREATED=1
  DB_ROOT_PASS="$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)"
  REDIS_PASS="$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)"
  SESSION_SECRET="$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 48)"
  cat > "${STACK_ROOT}/.env" <<EOF
COMPOSE_PROJECT_NAME=${PROJECT_NAME}
PANEL_DOMAIN=${PANEL_DOMAIN}
STACK_ROOT=${STACK_ROOT}
INSTALLER_VERSION=${INSTALLER_VERSION}
DPANEL_VERSION=${INSTALLER_VERSION}
DPANEL_REPO=${DPANEL_REPO}
DPANEL_BRANCH=${DPANEL_BRANCH}

MARIADB_ROOT_PASSWORD=${DB_ROOT_PASS}

REDIS_PASSWORD=${REDIS_PASS}
PANEL_SESSION_SECRET=${SESSION_SECRET}

NODE_ENV=production
NUXT_HOST=0.0.0.0
NUXT_PORT=3000
PHP_MEMORY_LIMIT=256M
PMA_ABSOLUTE_URI=http://${PANEL_DOMAIN}/mariadb/
EOF
  chmod 600 "${STACK_ROOT}/.env"
else
  grep -q '^PANEL_DOMAIN=' "${STACK_ROOT}/.env" \
    && sed -i "s/^PANEL_DOMAIN=.*/PANEL_DOMAIN=${PANEL_DOMAIN}/" "${STACK_ROOT}/.env" \
    || echo "PANEL_DOMAIN=${PANEL_DOMAIN}" >> "${STACK_ROOT}/.env"
fi

step "Build panel"
PANEL_SRC="${STACK_ROOT}/panel"
APP_DIR="${STACK_ROOT}/apps/${PANEL_DOMAIN}"
chmod +x "${STACK_ROOT}/infra/scripts/build-panel.sh"
run_cmd "Build panel (Docker)" bash "${STACK_ROOT}/infra/scripts/build-panel.sh" "${PANEL_SRC}"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}"
rsync -a "${PANEL_SRC}/.output/" "${APP_DIR}/.output/"
rsync -a "${PANEL_SRC}/package.json" "${PANEL_SRC}/node_modules" "${APP_DIR}/" 2>/dev/null || true

chmod +x "${STACK_ROOT}/infra/scripts/"*.sh
ln -sf "${STACK_ROOT}/infra/scripts/dpanel-cli.sh" /usr/local/bin/dpanel

export STACK_ROOT

step "Start containers"
cd "${STACK_ROOT}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"
run_cmd "docker compose build" stack_compose build
run_cmd "docker compose up" stack_compose up -d --remove-orphans

step "Configure nginx"
bash "${STACK_ROOT}/infra/scripts/nginx-reload.sh" || die "nginx configuration failed"

wait_for_healthy_stack

if [[ -f "${STACK_ROOT}/infra/scripts/health-check.sh" ]]; then
  bash "${STACK_ROOT}/infra/scripts/health-check.sh" --fix || log "Warning: post-install health check reported issues — run: dpanel health --fix"
fi

systemctl start unattended-upgrades.service unattended-upgrades.timer 2>/dev/null || true

SERVER_IP="$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
write_credentials

log "Done — http://${PANEL_DOMAIN} (or http://${SERVER_IP}:8080)"
log "Login: ${ADMIN_EMAIL} / ${DEFAULT_ADMIN_PASSWORD} — dpanel setpass <new-password>"
log "Updates: dpanel update-check | sudo dpanel update"
log "Credentials: ${STACK_ROOT}/CREDENTIALS.txt"
