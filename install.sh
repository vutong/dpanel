#!/usr/bin/env bash
#
# dpanel — Bootstrap VPS + Control Panel (một lệnh duy nhất)
# Chạy qua SSH:
#   curl -fsSL https://raw.githubusercontent.com/vutong/dpanel/main/install.sh | sudo bash
# hoặc:
#   chmod +x install.sh && sudo ./install.sh
#
set -euo pipefail

STACK_ROOT="/opt/stack"
PROJECT_NAME="${PROJECT_NAME:-dpanel}"
DPANEL_REPO="${DPANEL_REPO:-https://github.com/vutong/dpanel.git}"
DPANEL_BRANCH="${DPANEL_BRANCH:-main}"
PANEL_DOMAIN="${PANEL_DOMAIN:-}"

log() { echo "[dpanel] $*"; }
die() { echo "[dpanel] ERROR: $*" >&2; exit 1; }

[[ "${EUID:-0}" -eq 0 ]] || die "Chạy với quyền root: sudo bash install.sh"

log "Cấu hình dpanel — nhập thông tin bên dưới."
echo

# --- Thu thập cấu hình panel (chỉ cần chạy install.sh) ---
if [[ -z "${PANEL_DOMAIN}" ]]; then
  while true; do
    read -r -p "Panel domain (vd: panel.example.com): " PANEL_DOMAIN
    PANEL_DOMAIN="$(echo "${PANEL_DOMAIN}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    [[ -n "${PANEL_DOMAIN}" ]] || { echo "Domain không được để trống."; continue; }
    [[ "${PANEL_DOMAIN}" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || {
      echo "Domain không hợp lệ (vd: panel.example.com)."
      continue
    }
    break
  done
else
  PANEL_DOMAIN="$(echo "${PANEL_DOMAIN}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  log "Panel domain (từ biến môi trường): ${PANEL_DOMAIN}"
fi

read -r -p "Email đăng nhập panel: " ADMIN_EMAIL
[[ -n "${ADMIN_EMAIL}" ]] || die "Email không được để trống."

while true; do
  read -r -s -p "Mật khẩu: " ADMIN_PASSWORD
  echo
  read -r -s -p "Nhập lại mật khẩu: " ADMIN_PASSWORD2
  echo
  [[ "${ADMIN_PASSWORD}" == "${ADMIN_PASSWORD2}" ]] || { echo "Mật khẩu không khớp, thử lại."; continue; }
  [[ ${#ADMIN_PASSWORD} -ge 8 ]] || { echo "Mật khẩu tối thiểu 8 ký tự."; continue; }
  break
done

log "Panel domain: ${PANEL_DOMAIN}"
log "Email:        ${ADMIN_EMAIL}"
echo

# --- Nguồn mã ---
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
CLONE_TMP=""

cleanup_clone() {
  [[ -n "${CLONE_TMP}" && -d "${CLONE_TMP}" ]] && rm -rf "${CLONE_TMP}"
}
trap cleanup_clone EXIT

if [[ -f "${SCRIPT_DIR}/panel/package.json" ]]; then
  SRC_DIR="${SCRIPT_DIR}"
  log "Dùng mã nguồn local: ${SRC_DIR}"
else
  CLONE_TMP="$(mktemp -d)"
  log "Clone ${DPANEL_REPO} (branch ${DPANEL_BRANCH})..."
  git clone --depth 1 --branch "${DPANEL_BRANCH}" "${DPANEL_REPO}" "${CLONE_TMP}"
  SRC_DIR="${CLONE_TMP}"
fi

# --- Hệ thống ---
if [[ -f /etc/os-release ]]; then
  # shellcheck source=/dev/null
  source /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || log "Cảnh báo: script viết cho Ubuntu, đang chạy trên ${ID:-unknown}"
fi

log "Cập nhật hệ thống..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

log "Cài dependencies..."
apt-get install -y -qq \
  ca-certificates curl gnupg lsb-release git unzip rsync ufw \
  apache2-utils python3

if ! command -v docker &>/dev/null; then
  log "Cài Docker Engine..."
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
  log "Docker đã có sẵn."
fi

docker compose version &>/dev/null || die "docker compose plugin chưa sẵn sàng"

if command -v ufw &>/dev/null; then
  ufw allow OpenSSH || true
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  ufw allow 8080/tcp || true
  ufw --force enable || true
fi

# --- Đồng bộ repo vào stack ---
log "Triển khai stack tại ${STACK_ROOT}..."
mkdir -p "${STACK_ROOT}"
rsync -a --delete \
  --exclude '.git' \
  --exclude 'node_modules' \
  --exclude '.output' \
  --exclude '.nuxt' \
  "${SRC_DIR}/" "${STACK_ROOT}/"

# --- Thư mục dữ liệu ---
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

# --- Auth panel (bcrypt qua htpasswd) ---
ADMIN_HASH="$(htpasswd -nbBC 10 dpanel "${ADMIN_PASSWORD}" | cut -d: -f2)"
cat > "${STACK_ROOT}/data/panel/auth.json" <<EOF
{"email":"${ADMIN_EMAIL}","passwordHash":"${ADMIN_HASH}"}
EOF
chmod 600 "${STACK_ROOT}/data/panel/auth.json"

echo '[]' > "${STACK_ROOT}/data/panel/sites.json"
chmod 644 "${STACK_ROOT}/data/panel/sites.json"

# --- .env ---
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
  # Cập nhật domain panel nếu .env đã có
  grep -q '^PANEL_DOMAIN=' "${STACK_ROOT}/.env" \
    && sed -i "s/^PANEL_DOMAIN=.*/PANEL_DOMAIN=${PANEL_DOMAIN}/" "${STACK_ROOT}/.env" \
    || echo "PANEL_DOMAIN=${PANEL_DOMAIN}" >> "${STACK_ROOT}/.env"
fi

# --- Build & copy panel vào apps ---
log "Build control panel (Nuxt)..."
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

# --- Nginx vhost panel ---
export STACK_ROOT
bash "${STACK_ROOT}/infra/scripts/nginx-reload.sh" panel-only 2>/dev/null || true

log "Khởi động Docker stack..."
cd "${STACK_ROOT}"
docker compose build --quiet 2>/dev/null || docker compose build
docker compose up -d --remove-orphans

SERVER_IP="$(curl -4 -s --max-time 3 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"

log ""
log "========== dpanel đã cài xong =========="
log "Panel URL:  http://${PANEL_DOMAIN}  (hoặc http://${SERVER_IP}:8080 nếu chưa có DNS)"
log "Đăng nhập:  ${ADMIN_EMAIL}"
log "Stack:      ${STACK_ROOT}"
log "Tiếp theo: trỏ DNS (Cloudflare) subdomain panel về VPS, SSL do Cloudflare."
log "=========================================="
