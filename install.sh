#!/usr/bin/env bash
#
# dpanel — VPS installer
#
# Recommended:
#   curl -fsSLO https://raw.githubusercontent.com/vutong/dpanel/main/install.sh
#   sudo bash install.sh
#
# Non-interactive:
#   export DPANEL_NONINTERACTIVE=1
#   export PANEL_DOMAIN=panel.example.com
#   export ADMIN_EMAIL=admin@example.com
#   export ADMIN_PASSWORD='your-secure-password'
#   sudo -E bash install.sh
#
set -euo pipefail

INSTALLER_VERSION="1.0.0"
STACK_ROOT="/opt/stack"
PROJECT_NAME="${PROJECT_NAME:-dpanel}"
DPANEL_REPO="${DPANEL_REPO:-https://github.com/vutong/dpanel.git}"
DPANEL_BRANCH="${DPANEL_BRANCH:-main}"
PANEL_DOMAIN="${PANEL_DOMAIN:-}"
INSTALL_LOG="${INSTALL_LOG:-/var/log/dpanel-install.log}"
TOTAL_STEPS=11
STEP=0

INSTALL_LOG_DIR="$(dirname "${INSTALL_LOG}")"
mkdir -p "${INSTALL_LOG_DIR}" 2>/dev/null || INSTALL_LOG="/tmp/dpanel-install.log"
touch "${INSTALL_LOG}" 2>/dev/null || INSTALL_LOG="/tmp/dpanel-install.log"

log() {
  echo "[dpanel] $(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "${INSTALL_LOG}" >&2
}

die() {
  echo "[dpanel] ERROR: $*" | tee -a "${INSTALL_LOG}" >&2
  echo "[dpanel] See log: ${INSTALL_LOG}" | tee -a "${INSTALL_LOG}" >&2
  exit 1
}

on_err() {
  local line=$1
  log "Install failed at line ${line}. Check ${INSTALL_LOG}"
}
trap 'on_err $LINENO' ERR

step() {
  STEP=$((STEP + 1))
  log "[$STEP/$TOTAL_STEPS] $*"
}

wait_for_apt_lock() {
  local max_wait="${APT_LOCK_WAIT_SEC:-600}"
  local waited=0
  local locks=(/var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock)

  apt_lock_held() {
    local f
    for f in "${locks[@]}"; do
      [[ -e "$f" ]] || continue
      fuser "$f" >/dev/null 2>&1 && return 0
    done
    return 1
  }

  while apt_lock_held; do
    if [[ $waited -eq 0 ]]; then
      log "Waiting for apt/dpkg lock (unattended-upgrades or another apt process)..."
      pgrep -a apt 2>/dev/null | tee -a "${INSTALL_LOG}" >&2 || true
    fi
    if [[ $waited -ge $max_wait ]]; then
      die "apt lock held after ${max_wait}s. Run: sudo dpkg --configure -a && retry"
    fi
    sleep 5
    waited=$((waited + 5))
    log "  waiting for apt lock... (${waited}s / ${max_wait}s)"
  done
  [[ $waited -gt 0 ]] && log "apt lock released"
}

apt_get() {
  wait_for_apt_lock
  apt-get "$@"
}

preflight_checks() {
  step "Preflight checks"

  if [[ ! -f /etc/os-release ]]; then
    die "Cannot detect OS. Ubuntu 24.04 LTS is required."
  fi
  # shellcheck source=/dev/null
  source /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    die "Unsupported OS: ${ID:-unknown}. Use Ubuntu 24.04 LTS."
  fi
  local ver="${VERSION_ID:-}"
  if [[ "${ver}" != "24.04" ]]; then
    log "Warning: tested on Ubuntu 24.04; you are on ${ver}"
  fi

  local mem_kb
  mem_kb="$(grep MemTotal /proc/meminfo | awk '{print $2}')"
  if [[ "${mem_kb}" -lt 1800000 ]]; then
    log "Warning: less than 2 GB RAM — panel build may be slow or fail"
  else
    log "Memory: $((mem_kb / 1024)) MB OK"
  fi

  local disk_avail
  disk_avail="$(df -BM "${STACK_ROOT%/*}" 2>/dev/null | awk 'NR==2 {print $4}' | tr -d M || echo 0)"
  if [[ "${disk_avail}" -lt 10240 ]] 2>/dev/null; then
    log "Warning: less than 10 GB free disk under ${STACK_ROOT%/*}"
  else
    log "Disk free: ${disk_avail} MB OK"
  fi

  for port in 80 8080; do
    if ss -tln 2>/dev/null | grep -q ":${port} "; then
      if ! docker ps --format '{{.Ports}}' 2>/dev/null | grep -q ":${port}->"; then
        log "Warning: port ${port} is in use (install may conflict)"
      fi
    fi
  done

  command -v curl >/dev/null 2>&1 || die "curl is required"
  command -v git >/dev/null 2>&1 || log "git will be installed"
  log "Preflight passed"
}

banner() {
  log "=============================================="
  log "  dpanel installer v${INSTALLER_VERSION}"
  log "  Log: ${INSTALL_LOG}"
  log "  Typical time: 15–30 min (fresh VPS)"
  log "=============================================="
}

tty_print() { printf '%s\n' "$*" >/dev/tty 2>/dev/null || printf '%s\n' "$*"; }

tty_read() {
  printf '%s' "$1" >/dev/tty 2>/dev/null || printf '%s' "$1"
  read -r "$2" </dev/tty
}

tty_read_secret() {
  printf '%s' "$1" >/dev/tty 2>/dev/null || printf '%s' "$1"
  read -r -s "$2" </dev/tty
  echo >/dev/tty 2>/dev/null || echo
}

normalize_domain() {
  local d="$1"
  d="$(echo "$d" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  d="${d#https://}"
  d="${d#http://}"
  d="${d%%/*}"
  echo "$d"
}

collect_configuration() {
  step "Configuration"

  if [[ -n "${DPANEL_NONINTERACTIVE:-}" ]]; then
    [[ -n "${PANEL_DOMAIN}" && -n "${ADMIN_EMAIL}" && -n "${ADMIN_PASSWORD:-}" ]] \
      || die "Non-interactive mode requires PANEL_DOMAIN, ADMIN_EMAIL, ADMIN_PASSWORD"
    PANEL_DOMAIN="$(normalize_domain "${PANEL_DOMAIN}")"
    log "Non-interactive install for ${PANEL_DOMAIN}"
    return
  fi

  tty_print ""
  tty_print "Panel setup (press Enter after each answer):"

  if [[ -z "${PANEL_DOMAIN}" ]]; then
    while true; do
      tty_read "Panel domain (e.g. panel.example.com): " PANEL_DOMAIN
      PANEL_DOMAIN="$(normalize_domain "${PANEL_DOMAIN}")"
      [[ -n "${PANEL_DOMAIN}" ]] || { tty_print "Domain cannot be empty."; continue; }
      [[ "${PANEL_DOMAIN}" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] || {
        tty_print "Invalid domain (e.g. panel.example.com)."
        continue
      }
      break
    done
  else
    PANEL_DOMAIN="$(normalize_domain "${PANEL_DOMAIN}")"
    log "Panel domain (env): ${PANEL_DOMAIN}"
  fi

  if [[ -z "${ADMIN_EMAIL}" ]]; then
    tty_read "Panel login email: " ADMIN_EMAIL
  fi
  [[ -n "${ADMIN_EMAIL}" ]] || die "Email cannot be empty."

  if [[ -z "${ADMIN_PASSWORD:-}" ]]; then
    while true; do
      local p1 p2
      tty_read_secret "Password (min 8 chars): " p1
      tty_read_secret "Confirm password: " p2
      [[ "${p1}" == "${p2}" ]] || { tty_print "Passwords do not match."; continue; }
      [[ ${#p1} -ge 8 ]] || { tty_print "Password must be at least 8 characters."; continue; }
      ADMIN_PASSWORD="${p1}"
      break
    done
  fi
  [[ ${#ADMIN_PASSWORD} -ge 8 ]] || die "Password must be at least 8 characters"

  log "Panel domain: ${PANEL_DOMAIN}"
  log "Login email:  ${ADMIN_EMAIL}"
}

confirm_existing_stack() {
  if [[ ! -f "${STACK_ROOT}/.env" ]]; then
    return
  fi
  if [[ "${DPANEL_FORCE:-}" == "1" || -n "${DPANEL_NONINTERACTIVE:-}" ]]; then
    log "Existing stack at ${STACK_ROOT} — continuing (forced)"
    return
  fi
  tty_print ""
  tty_print "Existing installation found at ${STACK_ROOT}."
  tty_print "Panel auth and sites.json will be reset. MariaDB data is kept unless you remove ${STACK_ROOT}."
  local confirm=""
  tty_read "Type YES to continue: " confirm
  [[ "${confirm}" == "YES" ]] || die "Install cancelled"
}

write_credentials() {
  local cred="${STACK_ROOT}/CREDENTIALS.txt"
  local db_note="(unchanged — see .env)"
  if [[ "${NEW_ENV_CREATED:-}" == "1" ]]; then
    db_note="(new — saved in .env, not shown here for security)"
  fi
  cat > "${cred}" <<EOF
dpanel installation summary
Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Installer: v${INSTALLER_VERSION}

Panel URL:    http://${PANEL_DOMAIN}
              http://${SERVER_IP}:8080  (before DNS)

Login email:  ${ADMIN_EMAIL}
Login pass:   (the password you chose at install)

MariaDB:      ${db_note}
phpMyAdmin:   http://${PANEL_DOMAIN}/pma/  (via panel when logged in)

Stack path:   ${STACK_ROOT}
Install log:  ${INSTALL_LOG}

Commands:
  dpanel status
  dpanel health
  dpanel update-panel
  dpanel credentials

EOF
  chmod 600 "${cred}"
  log "Credentials summary: ${cred}"
}

wait_for_healthy_stack() {
  step "Waiting for services to become healthy"
  local i
  for i in $(seq 1 40); do
    if docker compose ps --format json 2>/dev/null | grep -q '"Health":"healthy"' 2>/dev/null \
      || docker compose exec -T dpanel wget -q -O- http://127.0.0.1:3000/api/health 2>/dev/null | grep -q '"ok"'; then
      log "Panel is healthy"
      return 0
    fi
    sleep 3
  done
  log "Warning: health check timed out — run: dpanel logs dpanel"
  return 0
}

# --- Main ---
banner

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
cleanup_clone() { [[ -n "${CLONE_TMP}" && -d "${CLONE_TMP}" ]] && rm -rf "${CLONE_TMP}"; }
trap cleanup_clone EXIT

if [[ "${USE_LOCAL_SRC}" == true ]]; then
  step "Using local source at ${SRC_DIR}"
else
  step "Downloading source from GitHub"
  CLONE_TMP="$(mktemp -d)"
  export GIT_TERMINAL_PROMPT=0
  git clone --progress --depth 1 --branch "${DPANEL_BRANCH}" "${DPANEL_REPO}" "${CLONE_TMP}"
  SRC_DIR="${CLONE_TMP}"
fi

step "Preparing system packages"
export DEBIAN_FRONTEND=noninteractive
apt_get update
if [[ "${DPANEL_FULL_UPGRADE:-0}" == "1" ]]; then
  log "Running full dist-upgrade (DPANEL_FULL_UPGRADE=1)..."
  apt_get upgrade -y
else
  log "Skipping dist-upgrade (faster install). Set DPANEL_FULL_UPGRADE=1 to enable."
fi

apt_get install -y \
  ca-certificates curl gnupg lsb-release git unzip rsync ufw \
  apache2-utils python3

if ! command -v docker &>/dev/null; then
  step "Installing Docker Engine"
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
else
  log "Docker already installed"
fi

docker compose version &>/dev/null || die "docker compose plugin is not available"

if command -v ufw &>/dev/null; then
  log "Configuring UFW (SSH, 80, 443, 8080)..."
  ufw allow OpenSSH || true
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  ufw allow 8080/tcp || true
  ufw --force enable || true
fi

step "Deploying stack to ${STACK_ROOT}"
mkdir -p "${STACK_ROOT}"
rsync -a --delete \
  --exclude '.git' \
  --exclude 'node_modules' \
  --exclude '.output' \
  --exclude '.nuxt' \
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

MARIADB_ROOT_PASSWORD=${DB_ROOT_PASS}
MARIADB_DATABASE=dpanel
MARIADB_USER=dpanel
MARIADB_PASSWORD=${DB_ROOT_PASS}

REDIS_PASSWORD=${REDIS_PASS}
PANEL_SESSION_SECRET=${SESSION_SECRET}

NODE_ENV=production
NUXT_HOST=0.0.0.0
NUXT_PORT=3000
PHP_MEMORY_LIMIT=256M
EOF
  chmod 600 "${STACK_ROOT}/.env"
  log "Created ${STACK_ROOT}/.env"
else
  grep -q '^PANEL_DOMAIN=' "${STACK_ROOT}/.env" \
    && sed -i "s/^PANEL_DOMAIN=.*/PANEL_DOMAIN=${PANEL_DOMAIN}/" "${STACK_ROOT}/.env" \
    || echo "PANEL_DOMAIN=${PANEL_DOMAIN}" >> "${STACK_ROOT}/.env"
fi

step "Building control panel (Nuxt)"
PANEL_SRC="${STACK_ROOT}/panel"
APP_DIR="${STACK_ROOT}/apps/${PANEL_DOMAIN}"
docker run --rm -v "${PANEL_SRC}:/app" -w /app node:22-alpine sh -c \
  "npm ci && npm run build" \
  || docker run --rm -v "${PANEL_SRC}:/app" -w /app node:22-alpine sh -c \
  "npm install && npm run build"

log "Deploying panel to apps/${PANEL_DOMAIN}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}"
rsync -a "${PANEL_SRC}/.output/" "${APP_DIR}/.output/"
rsync -a "${PANEL_SRC}/package.json" "${PANEL_SRC}/node_modules" "${APP_DIR}/" 2>/dev/null || true

chmod +x "${STACK_ROOT}/infra/scripts/"*.sh
ln -sf "${STACK_ROOT}/infra/scripts/dpanel-cli.sh" /usr/local/bin/dpanel

export STACK_ROOT
bash "${STACK_ROOT}/infra/scripts/nginx-reload.sh" panel-only 2>/dev/null || true

step "Starting Docker stack"
cd "${STACK_ROOT}"
docker compose build
docker compose up -d --remove-orphans

wait_for_healthy_stack
docker compose ps

SERVER_IP="$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
write_credentials

log ""
log "=============================================="
log "  dpanel installed successfully"
log "=============================================="
log "Panel:     http://${PANEL_DOMAIN}"
log "Fallback:  http://${SERVER_IP}:8080"
log "Email:     ${ADMIN_EMAIL}"
log "Summary:   ${STACK_ROOT}/CREDENTIALS.txt"
log "CLI:       dpanel status | dpanel health"
log "Log:       ${INSTALL_LOG}"
log "DNS:       Point ${PANEL_DOMAIN} → ${SERVER_IP} (Cloudflare proxy for SSL)"
log "=============================================="
