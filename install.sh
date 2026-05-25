#!/usr/bin/env bash
#
# dpanel — Bootstrap VPS + Control Panel
#
# Recommended (shows progress, prompts work reliably):
#   curl -fsSLO https://raw.githubusercontent.com/vutong/dpanel/main/install.sh
#   sudo bash install.sh
#
# One-liner (also supported):
#   curl -fsSL https://raw.githubusercontent.com/vutong/dpanel/main/install.sh | sudo bash
#
set -euo pipefail

STACK_ROOT="/opt/stack"
PROJECT_NAME="${PROJECT_NAME:-dpanel}"
DPANEL_REPO="${DPANEL_REPO:-https://github.com/vutong/dpanel.git}"
DPANEL_BRANCH="${DPANEL_BRANCH:-main}"
PANEL_DOMAIN="${PANEL_DOMAIN:-}"
INSTALL_LOG="${INSTALL_LOG:-/var/log/dpanel-install.log}"
TOTAL_STEPS=9
STEP=0

INSTALL_LOG_DIR="$(dirname "${INSTALL_LOG}")"
mkdir -p "${INSTALL_LOG_DIR}" 2>/dev/null || INSTALL_LOG="/tmp/dpanel-install.log"
touch "${INSTALL_LOG}" 2>/dev/null || INSTALL_LOG="/tmp/dpanel-install.log"

# Always show progress on stderr + log file (visible even when stdout is piped)
log() {
  echo "[dpanel] $(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "${INSTALL_LOG}" >&2
}

die() {
  echo "[dpanel] ERROR: $*" | tee -a "${INSTALL_LOG}" >&2
  exit 1
}

step() {
  STEP=$((STEP + 1))
  log "[$STEP/$TOTAL_STEPS] $*"
}

banner() {
  log "=============================================="
  log "  dpanel installer"
  log "  Log file: ${INSTALL_LOG}"
  log "  This may take 15–30 minutes on a fresh VPS."
  log "=============================================="
}

# Print something immediately (before root check / apt)
banner

[[ "${EUID:-0}" -eq 0 ]] || die "Run as root: sudo bash install.sh"

# curl | bash: attach stdin and prompts to the real terminal
if [[ -r /dev/tty ]]; then
  exec 0</dev/tty
fi

tty_print() {
  printf '%s\n' "$*" >/dev/tty 2>/dev/null || printf '%s\n' "$*"
}

tty_read() {
  local prompt=$1
  local var=$2
  printf '%s' "${prompt}" >/dev/tty 2>/dev/null || printf '%s' "${prompt}"
  read -r "${var}" </dev/tty
}

tty_read_secret() {
  local prompt=$1
  local var=$2
  printf '%s' "${prompt}" >/dev/tty 2>/dev/null || printf '%s' "${prompt}"
  read -r -s "${var}" </dev/tty
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

step "Configuration — enter panel details"
tty_print ""
tty_print "Panel setup (press Enter after each answer):"

ADMIN_EMAIL=""
ADMIN_PASSWORD=""
ADMIN_PASSWORD2=""

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
  log "Panel domain (from environment): ${PANEL_DOMAIN}"
fi

tty_read "Panel login email: " ADMIN_EMAIL
[[ -n "${ADMIN_EMAIL}" ]] || die "Email cannot be empty."

while true; do
  tty_read_secret "Password: " ADMIN_PASSWORD
  tty_read_secret "Confirm password: " ADMIN_PASSWORD2
  [[ "${ADMIN_PASSWORD}" == "${ADMIN_PASSWORD2}" ]] || { tty_print "Passwords do not match. Try again."; continue; }
  [[ ${#ADMIN_PASSWORD} -ge 8 ]] || { tty_print "Password must be at least 8 characters."; continue; }
  break
done

log "Using panel domain: ${PANEL_DOMAIN}"
log "Using login email:  ${ADMIN_EMAIL}"
tty_print ""

# Detect source: piped curl | bash has BASH_SOURCE=bash — always clone from GitHub
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
cleanup_clone() {
  [[ -n "${CLONE_TMP}" && -d "${CLONE_TMP}" ]] && rm -rf "${CLONE_TMP}"
}
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

if [[ -f /etc/os-release ]]; then
  # shellcheck source=/dev/null
  source /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || log "Warning: script targets Ubuntu, running on ${ID:-unknown}"
fi

step "Updating system packages (apt)"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

step "Installing system dependencies"
apt-get install -y \
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
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
else
  log "Docker already installed — skipping"
fi

docker compose version &>/dev/null || die "docker compose plugin is not available"

if command -v ufw &>/dev/null; then
  log "Configuring firewall (UFW)..."
  ufw allow OpenSSH || true
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  ufw allow 8080/tcp || true
  ufw --force enable || true
fi

step "Deploying files to ${STACK_ROOT}"
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
  "${STACK_ROOT}/logs/nginx"
  "${STACK_ROOT}/logs/node"
  "${STACK_ROOT}/logs/php"
  "${STACK_ROOT}/logs/mariadb"
  "${STACK_ROOT}/logs/redis"
  "${STACK_ROOT}/infra/nginx/conf.d"
  "${STACK_ROOT}/compose.d"
)
for d in "${DIRS[@]}"; do mkdir -p "$d"; done
touch "${STACK_ROOT}/logs/nginx/access.log" "${STACK_ROOT}/logs/nginx/error.log"

ADMIN_HASH="$(htpasswd -nbBC 10 dpanel "${ADMIN_PASSWORD}" | cut -d: -f2)"
cat > "${STACK_ROOT}/data/panel/auth.json" <<EOF
{"email":"${ADMIN_EMAIL}","passwordHash":"${ADMIN_HASH}"}
EOF
chmod 600 "${STACK_ROOT}/data/panel/auth.json"

echo '[]' > "${STACK_ROOT}/data/panel/sites.json"
chmod 644 "${STACK_ROOT}/data/panel/sites.json"

if [[ ! -f "${STACK_ROOT}/.env" ]]; then
  DB_ROOT_PASS="$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)"
  REDIS_PASS="$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)"
  SESSION_SECRET="$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 48)"

  cat > "${STACK_ROOT}/.env" <<EOF
COMPOSE_PROJECT_NAME=${PROJECT_NAME}
PANEL_DOMAIN=${PANEL_DOMAIN}
STACK_ROOT=${STACK_ROOT}

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
  log "Updated PANEL_DOMAIN in existing .env"
fi

step "Building control panel (Nuxt) — npm output below"
PANEL_SRC="${STACK_ROOT}/panel"
APP_DIR="${STACK_ROOT}/apps/${PANEL_DOMAIN}"

if command -v docker &>/dev/null; then
  docker run --rm -v "${PANEL_SRC}:/app" -w /app node:22-alpine sh -c \
    "npm ci && npm run build" \
    || docker run --rm -v "${PANEL_SRC}:/app" -w /app node:22-alpine sh -c \
    "npm install && npm run build"
else
  die "Docker is required to build the panel"
fi

log "Copying panel build to apps/${PANEL_DOMAIN}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}"
rsync -a "${PANEL_SRC}/.output/" "${APP_DIR}/.output/"
rsync -a "${PANEL_SRC}/package.json" "${PANEL_SRC}/node_modules" "${APP_DIR}/" 2>/dev/null || true

chmod +x "${STACK_ROOT}/infra/scripts/"*.sh 2>/dev/null || true

export STACK_ROOT
bash "${STACK_ROOT}/infra/scripts/nginx-reload.sh" panel-only 2>/dev/null || true

step "Starting Docker stack (compose build & up)"
cd "${STACK_ROOT}"
docker compose build
docker compose up -d --remove-orphans
docker compose ps

SERVER_IP="$(curl -4 -s --max-time 3 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"

log ""
log "========== dpanel installed =========="
log "Panel URL:  http://${PANEL_DOMAIN}  (or http://${SERVER_IP}:8080 if DNS is not ready)"
log "Login:      ${ADMIN_EMAIL}"
log "Stack:      ${STACK_ROOT}"
log "Full log:   ${INSTALL_LOG}"
log "Next: point panel subdomain DNS (Cloudflare) to this VPS; SSL via Cloudflare."
log "======================================"
