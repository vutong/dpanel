#!/usr/bin/env bash
#
# dpanel — Bootstrap VPS + Control Panel (single entry point)
# Via SSH (script attaches stdin to /dev/tty when piped):
#   curl -fsSL https://raw.githubusercontent.com/vutong/dpanel/main/install.sh | sudo bash
# Or download first: curl -fsSLO .../install.sh && sudo bash install.sh
# Or: chmod +x install.sh && sudo ./install.sh
#
set -euo pipefail

STACK_ROOT="/opt/stack"
PROJECT_NAME="${PROJECT_NAME:-dpanel}"
DPANEL_REPO="${DPANEL_REPO:-https://github.com/vutong/dpanel.git}"
DPANEL_BRANCH="${DPANEL_BRANCH:-main}"
PANEL_DOMAIN="${PANEL_DOMAIN:-}"

log() { echo "[dpanel] $*"; }
die() { echo "[dpanel] ERROR: $*" >&2; exit 1; }

[[ "${EUID:-0}" -eq 0 ]] || die "Run as root: sudo bash install.sh"

# curl | bash: stdin is the pipe — reads must use the real terminal
if [[ ! -t 0 && -r /dev/tty ]]; then
  exec 0</dev/tty
fi

normalize_domain() {
  local d="$1"
  d="$(echo "$d" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  d="${d#https://}"
  d="${d#http://}"
  d="${d%%/*}"
  echo "$d"
}

log "dpanel setup — enter the details below."
echo

ADMIN_EMAIL=""
ADMIN_PASSWORD=""
ADMIN_PASSWORD2=""

if [[ -z "${PANEL_DOMAIN}" ]]; then
  while true; do
    read -r -p "Panel domain (e.g. panel.example.com): " PANEL_DOMAIN
    PANEL_DOMAIN="$(normalize_domain "${PANEL_DOMAIN}")"
    [[ -n "${PANEL_DOMAIN}" ]] || { echo "Domain cannot be empty."; continue; }
    [[ "${PANEL_DOMAIN}" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] || {
      echo "Invalid domain (e.g. panel.example.com)."
      continue
    }
    break
  done
else
  PANEL_DOMAIN="$(normalize_domain "${PANEL_DOMAIN}")"
  log "Panel domain (from environment): ${PANEL_DOMAIN}"
fi

read -r -p "Panel login email: " ADMIN_EMAIL
[[ -n "${ADMIN_EMAIL}" ]] || die "Email cannot be empty."

while true; do
  read -r -s -p "Password: " ADMIN_PASSWORD
  echo
  read -r -s -p "Confirm password: " ADMIN_PASSWORD2
  echo
  [[ "${ADMIN_PASSWORD}" == "${ADMIN_PASSWORD2}" ]] || { echo "Passwords do not match. Try again."; continue; }
  [[ ${#ADMIN_PASSWORD} -ge 8 ]] || { echo "Password must be at least 8 characters."; continue; }
  break
done

log "Panel domain: ${PANEL_DOMAIN}"
log "Email:        ${ADMIN_EMAIL}"
echo

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
CLONE_TMP=""

cleanup_clone() {
  [[ -n "${CLONE_TMP}" && -d "${CLONE_TMP}" ]] && rm -rf "${CLONE_TMP}"
}
trap cleanup_clone EXIT

if [[ -f "${SCRIPT_DIR}/panel/package.json" ]]; then
  SRC_DIR="${SCRIPT_DIR}"
  log "Using local source: ${SRC_DIR}"
else
  CLONE_TMP="$(mktemp -d)"
  log "Cloning ${DPANEL_REPO} (branch ${DPANEL_BRANCH})..."
  git clone --depth 1 --branch "${DPANEL_BRANCH}" "${DPANEL_REPO}" "${CLONE_TMP}"
  SRC_DIR="${CLONE_TMP}"
fi

if [[ -f /etc/os-release ]]; then
  # shellcheck source=/dev/null
  source /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || log "Warning: script targets Ubuntu, running on ${ID:-unknown}"
fi

log "Updating system..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

log "Installing dependencies..."
apt-get install -y -qq \
  ca-certificates curl gnupg lsb-release git unzip rsync ufw \
  apache2-utils python3

if ! command -v docker &>/dev/null; then
  log "Installing Docker Engine..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
else
  log "Docker already installed."
fi

docker compose version &>/dev/null || die "docker compose plugin is not available"

if command -v ufw &>/dev/null; then
  ufw allow OpenSSH || true
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  ufw allow 8080/tcp || true
  ufw --force enable || true
fi

log "Deploying stack at ${STACK_ROOT}..."
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
else
  grep -q '^PANEL_DOMAIN=' "${STACK_ROOT}/.env" \
    && sed -i "s/^PANEL_DOMAIN=.*/PANEL_DOMAIN=${PANEL_DOMAIN}/" "${STACK_ROOT}/.env" \
    || echo "PANEL_DOMAIN=${PANEL_DOMAIN}" >> "${STACK_ROOT}/.env"
fi

log "Building control panel (Nuxt)..."
PANEL_SRC="${STACK_ROOT}/panel"
APP_DIR="${STACK_ROOT}/apps/${PANEL_DOMAIN}"

if command -v docker &>/dev/null; then
  docker run --rm -v "${PANEL_SRC}:/app" -w /app node:22-alpine sh -c \
    "npm ci && npm run build" 2>/dev/null \
    || docker run --rm -v "${PANEL_SRC}:/app" -w /app node:22-alpine sh -c \
    "npm install && npm run build"
fi

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}"
rsync -a "${PANEL_SRC}/.output/" "${APP_DIR}/.output/"
rsync -a "${PANEL_SRC}/package.json" "${PANEL_SRC}/node_modules" "${APP_DIR}/" 2>/dev/null || true

chmod +x "${STACK_ROOT}/infra/scripts/"*.sh 2>/dev/null || true

export STACK_ROOT
bash "${STACK_ROOT}/infra/scripts/nginx-reload.sh" panel-only 2>/dev/null || true

log "Starting Docker stack..."
cd "${STACK_ROOT}"
docker compose build --quiet 2>/dev/null || docker compose build
docker compose up -d --remove-orphans

SERVER_IP="$(curl -4 -s --max-time 3 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"

log ""
log "========== dpanel installed =========="
log "Panel URL:  http://${PANEL_DOMAIN}  (or http://${SERVER_IP}:8080 if DNS is not ready)"
log "Login:      ${ADMIN_EMAIL}"
log "Stack:      ${STACK_ROOT}"
log "Next: point panel subdomain DNS (Cloudflare) to this VPS; SSL via Cloudflare."
log "======================================"
