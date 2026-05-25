#!/usr/bin/env bash
#
# ubuntu-docker — Bootstrap Ubuntu 24.04 LTS
# Chạy: sudo bash setup-vps.sh
#
# Domain mặc định chỉ là VÍ DỤ. Override trước khi chạy:
#   export APP_DOMAIN=app.yourdomain.com
#   export BLOG_DOMAIN=blog.yourdomain.com
#   export ADMIN_DOMAIN=admin.yourdomain.com
#
set -euo pipefail

STACK_ROOT="/opt/stack"
PROJECT_NAME="${PROJECT_NAME:-ubuntu-docker}"

# --- Domain ví dụ (thay bằng domain thật) ---
APP_DOMAIN="${APP_DOMAIN:-app.example.com}"
BLOG_DOMAIN="${BLOG_DOMAIN:-blog.example.com}"
ADMIN_DOMAIN="${ADMIN_DOMAIN:-admin.example.com}"

log() { echo "[setup] $*"; }
die() { echo "[setup] ERROR: $*" >&2; exit 1; }

[[ "${EUID:-0}" -eq 0 ]] || die "Chạy script với quyền root: sudo bash setup-vps.sh"

if [[ -f /etc/os-release ]]; then
  # shellcheck source=/dev/null
  source /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || log "Cảnh báo: script được viết cho Ubuntu, đang chạy trên ${ID:-unknown}"
fi

log "Dự án: ${PROJECT_NAME}"
log "Domain (ví dụ — chỉnh bằng biến môi trường hoặc .env sau bootstrap):"
log "  APP=${APP_DOMAIN}  BLOG=${BLOG_DOMAIN}  ADMIN=${ADMIN_DOMAIN}"

log "Cập nhật hệ thống..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

log "Cài dependencies..."
apt-get install -y -qq \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  git \
  unzip \
  rsync \
  ufw

# --- Docker Engine ---
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
  log "Docker đã có sẵn, bỏ qua cài đặt."
fi

docker compose version &>/dev/null || die "docker compose plugin chưa sẵn sàng"

# --- Firewall cơ bản ---
if command -v ufw &>/dev/null; then
  ufw allow OpenSSH || true
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  ufw --force enable || true
  log "UFW: mở SSH, 80, 443 (HTTPS do Cloudflare terminate)."
fi

# --- Cây thư mục ---
log "Tạo cấu trúc thư mục tại ${STACK_ROOT}..."

DIRS=(
  "${STACK_ROOT}"
  "${STACK_ROOT}/infra/nginx/conf.d"
  "${STACK_ROOT}/infra/nginx/templates"
  "${STACK_ROOT}/infra/docker/node/runtime"
  "${STACK_ROOT}/infra/docker/php/config"
  "${STACK_ROOT}/infra/docker/base/node"
  "${STACK_ROOT}/infra/docker/base/php"
  "${STACK_ROOT}/infra/scripts"
  "${STACK_ROOT}/apps/${APP_DOMAIN}"
  "${STACK_ROOT}/apps/${BLOG_DOMAIN}"
  "${STACK_ROOT}/apps/${ADMIN_DOMAIN}"
  "${STACK_ROOT}/data/mariadb/volume"
  "${STACK_ROOT}/data/mariadb/backup"
  "${STACK_ROOT}/data/redis/dump"
  "${STACK_ROOT}/data/redis/persistence"
  "${STACK_ROOT}/data/uploads/${APP_DOMAIN}"
  "${STACK_ROOT}/data/uploads/${BLOG_DOMAIN}"
  "${STACK_ROOT}/data/uploads/${ADMIN_DOMAIN}"
  "${STACK_ROOT}/logs/nginx"
  "${STACK_ROOT}/logs/node"
  "${STACK_ROOT}/logs/php"
  "${STACK_ROOT}/logs/mariadb"
  "${STACK_ROOT}/logs/redis"
)

for d in "${DIRS[@]}"; do
  mkdir -p "$d"
done

touch "${STACK_ROOT}/logs/nginx/access.log" "${STACK_ROOT}/logs/nginx/error.log"

# --- .env ---
if [[ ! -f "${STACK_ROOT}/.env" ]]; then
  DB_ROOT_PASS="$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)"
  DB_APP_PASS="$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)"
  REDIS_PASS="$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)"

  cat > "${STACK_ROOT}/.env" <<EOF
# ubuntu-docker — sinh bởi setup-vps.sh
COMPOSE_PROJECT_NAME=${PROJECT_NAME}

# Domain (ví dụ — thay bằng domain thật; Cloudflare proxy, không SSL local)
APP_DOMAIN=${APP_DOMAIN}
BLOG_DOMAIN=${BLOG_DOMAIN}
ADMIN_DOMAIN=${ADMIN_DOMAIN}

# MariaDB
MARIADB_ROOT_PASSWORD=${DB_ROOT_PASS}
MARIADB_DATABASE=appdb
MARIADB_USER=appuser
MARIADB_PASSWORD=${DB_APP_PASS}

# Redis
REDIS_PASSWORD=${REDIS_PASS}

# Node / Nuxt
NODE_ENV=production
NUXT_HOST=0.0.0.0
NUXT_PORT=3000

# PHP
PHP_MEMORY_LIMIT=256M
EOF
  chmod 600 "${STACK_ROOT}/.env"
  log "Đã tạo ${STACK_ROOT}/.env (mật khẩu ngẫu nhiên)."
else
  log "${STACK_ROOT}/.env đã tồn tại, giữ nguyên."
fi

# --- compose.yml ---
cat > "${STACK_ROOT}/compose.yml" <<EOF
services:
  nginx:
    image: nginx:1.27-alpine
    container_name: ${PROJECT_NAME}-nginx
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - ./infra/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./infra/nginx/conf.d:/etc/nginx/conf.d:ro
      - ./infra/nginx/templates:/etc/nginx/templates:ro
      - ./apps:/var/www/apps:ro
      - ./data/uploads:/var/www/uploads:ro
      - ./logs/nginx:/var/log/nginx
    depends_on:
      - nuxt
      - php-fpm
    networks:
      - stack

  nuxt:
    build:
      context: ./infra/docker/node
      dockerfile: Dockerfile
    container_name: ${PROJECT_NAME}-nuxt
    restart: unless-stopped
    env_file: .env
    volumes:
      - ./apps/${APP_DOMAIN}:/app:ro
      - ./data/uploads/${APP_DOMAIN}:/app/public/uploads
      - ./logs/node:/var/log/node
    networks:
      - stack

  php-fpm:
    build:
      context: ./infra/docker/php
      dockerfile: Dockerfile
    container_name: ${PROJECT_NAME}-php
    restart: unless-stopped
    env_file: .env
    volumes:
      - ./apps/${BLOG_DOMAIN}:/var/www/blog:ro
      - ./apps/${ADMIN_DOMAIN}:/var/www/admin:ro
      - ./data/uploads/${BLOG_DOMAIN}:/var/www/uploads/blog
      - ./data/uploads/${ADMIN_DOMAIN}:/var/www/uploads/admin
      - ./infra/docker/php/config:/usr/local/etc/php/conf.d/custom:ro
      - ./logs/php:/var/log/php
    networks:
      - stack

  mariadb:
    image: mariadb:11
    container_name: ${PROJECT_NAME}-mariadb
    restart: unless-stopped
    env_file: .env
    environment:
      MARIADB_ROOT_PASSWORD: \${MARIADB_ROOT_PASSWORD}
      MARIADB_DATABASE: \${MARIADB_DATABASE}
      MARIADB_USER: \${MARIADB_USER}
      MARIADB_PASSWORD: \${MARIADB_PASSWORD}
    volumes:
      - ./data/mariadb/volume:/var/lib/mysql
      - ./data/mariadb/backup:/backup
      - ./logs/mariadb:/var/log/mysql
    networks:
      - stack

  redis:
    image: redis:7-alpine
    container_name: ${PROJECT_NAME}-redis
    restart: unless-stopped
    command: >
      sh -c "redis-server
      --requirepass \$\${REDIS_PASSWORD}
      --dir /data
      --appendonly yes"
    env_file: .env
    volumes:
      - ./data/redis/persistence:/data
      - ./data/redis/dump:/dump
      - ./logs/redis:/var/log/redis
    networks:
      - stack

networks:
  stack:
    driver: bridge
EOF

# --- nginx.conf ---
cat > "${STACK_ROOT}/infra/nginx/nginx.conf" <<'EOF'
user  nginx;
worker_processes  auto;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    keepalive_timeout  65;
    client_max_body_size 64m;

    # Cloudflare — tin cậy IP thật
    set_real_ip_from 103.21.244.0/22;
    set_real_ip_from 103.22.200.0/22;
    set_real_ip_from 103.31.4.0/22;
    set_real_ip_from 104.16.0.0/13;
    set_real_ip_from 104.24.0.0/14;
    set_real_ip_from 108.162.192.0/18;
    set_real_ip_from 131.0.72.0/22;
    set_real_ip_from 141.101.64.0/18;
    set_real_ip_from 162.158.0.0/15;
    set_real_ip_from 172.64.0.0/13;
    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 188.114.96.0/20;
    set_real_ip_from 190.93.240.0/20;
    set_real_ip_from 197.234.240.0/22;
    set_real_ip_from 198.41.128.0/17;
    real_ip_header CF-Connecting-IP;

    include /etc/nginx/conf.d/*.conf;
}
EOF

# --- nginx vhosts (domain ví dụ — sửa sau nếu cần) ---
cat > "${STACK_ROOT}/infra/nginx/conf.d/app.conf" <<EOF
server {
    listen 80;
    server_name ${APP_DOMAIN};

    location / {
        proxy_pass http://nuxt:3000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /uploads/ {
        alias /var/www/uploads/${APP_DOMAIN}/;
        access_log off;
        expires 30d;
    }
}
EOF

cat > "${STACK_ROOT}/infra/nginx/conf.d/blog.conf" <<EOF
server {
    listen 80;
    server_name ${BLOG_DOMAIN};
    root /var/www/blog/public;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \\.php\$ {
        fastcgi_pass php-fpm:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location /uploads/ {
        alias /var/www/uploads/blog/;
        access_log off;
        expires 30d;
    }
}
EOF

cat > "${STACK_ROOT}/infra/nginx/conf.d/admin.conf" <<EOF
server {
    listen 80;
    server_name ${ADMIN_DOMAIN};
    root /var/www/admin/public;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \\.php\$ {
        fastcgi_pass php-fpm:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location /uploads/ {
        alias /var/www/uploads/admin/;
        access_log off;
        expires 30d;
    }
}
EOF

# --- Dockerfiles ---
cat > "${STACK_ROOT}/infra/docker/node/Dockerfile" <<'EOF'
FROM node:22-alpine

WORKDIR /app

RUN apk add --no-cache tini

COPY runtime/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/entrypoint.sh"]
EOF

cat > "${STACK_ROOT}/infra/docker/node/runtime/entrypoint.sh" <<EOF
#!/bin/sh
set -e
cd /app

if [ -f package.json ]; then
  if [ ! -d node_modules/.bin ]; then
    echo "[nuxt] Cài dependencies..."
    npm ci --omit=dev 2>/dev/null || npm install --omit=dev
  fi
  if [ -f .output/server/index.mjs ]; then
    exec node .output/server/index.mjs
  fi
  echo "[nuxt] Chưa có build .output — deploy mã Nuxt và chạy npm run build trước."
  exec sleep infinity
fi

echo "[nuxt] Thư mục /app trống — copy mã vào apps/${APP_DOMAIN}"
exec sleep infinity
EOF
chmod +x "${STACK_ROOT}/infra/docker/node/runtime/entrypoint.sh"

cat > "${STACK_ROOT}/infra/docker/php/Dockerfile" <<'EOF'
FROM php:8.3-fpm-alpine

RUN apk add --no-cache \
    libzip-dev \
    icu-dev \
    oniguruma-dev \
    freetype-dev \
    libjpeg-turbo-dev \
    libpng-dev \
  && docker-php-ext-configure gd --with-freetype --with-jpeg \
  && docker-php-ext-install -j$(nproc) \
    pdo_mysql \
    mysqli \
    zip \
    intl \
    opcache \
    gd \
    bcmath \
  && rm -rf /var/cache/apk/*

COPY config/99-custom.ini /usr/local/etc/php/conf.d/99-custom.ini

WORKDIR /var/www

EXPOSE 9000
EOF

cat > "${STACK_ROOT}/infra/docker/php/config/99-custom.ini" <<'EOF'
memory_limit = 256M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 120
EOF

# --- Ops scripts ---
cat > "${STACK_ROOT}/infra/scripts/deploy.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/stack
docker compose pull --ignore-pull-failures 2>/dev/null || true
docker compose build
docker compose up -d --remove-orphans
docker compose ps
EOF
chmod +x "${STACK_ROOT}/infra/scripts/deploy.sh"

cat > "${STACK_ROOT}/infra/scripts/backup.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/stack
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="/opt/stack/data/mariadb/backup/${STAMP}"
mkdir -p "$BACKUP_DIR"

source .env
docker compose exec -T mariadb mariadb-dump \
  -u root -p"${MARIADB_ROOT_PASSWORD}" \
  --all-databases --single-transaction \
  > "${BACKUP_DIR}/all-databases.sql"

tar -czf "${BACKUP_DIR}/uploads.tar.gz" -C /opt/stack/data uploads
echo "Backup: ${BACKUP_DIR}"
EOF
chmod +x "${STACK_ROOT}/infra/scripts/backup.sh"

cat > "${STACK_ROOT}/infra/scripts/migrate.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/stack

if docker compose exec -T php-fpm test -f /var/www/blog/artisan 2>/dev/null; then
  docker compose exec -T php-fpm php /var/www/blog/artisan migrate --force
fi

if docker compose exec -T php-fpm test -f /var/www/admin/artisan 2>/dev/null; then
  docker compose exec -T php-fpm php /var/www/admin/artisan migrate --force
fi

echo "Migration hoàn tất (hoặc không có artisan)."
EOF
chmod +x "${STACK_ROOT}/infra/scripts/migrate.sh"

cat > "${STACK_ROOT}/infra/scripts/cleanup.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/stack
docker image prune -f
docker builder prune -f --filter "until=168h"
find /opt/stack/logs -type f -name "*.log" -mtime +30 -delete 2>/dev/null || true
echo "Cleanup xong."
EOF
chmod +x "${STACK_ROOT}/infra/scripts/cleanup.sh"

# --- Placeholder apps ---
for app in "${APP_DOMAIN}" "${BLOG_DOMAIN}" "${ADMIN_DOMAIN}"; do
  if [[ ! -f "${STACK_ROOT}/apps/${app}/.gitkeep" ]]; then
    echo "Deploy mã nguồn vào đây (domain ví dụ: ${app})" > "${STACK_ROOT}/apps/${app}/.gitkeep"
  fi
done

# --- Quyền ---
chown -R root:root "${STACK_ROOT}"
chmod 755 "${STACK_ROOT}"
chmod 600 "${STACK_ROOT}/.env" 2>/dev/null || true

log "Hoàn tất bootstrap."
log ""
log "Tiếp theo:"
log "  1. Đổi domain trong .env và nginx/conf.d/ nếu chưa dùng domain thật"
log "  2. Copy mã vào ${STACK_ROOT}/apps/<domain>/"
log "  3. cd ${STACK_ROOT} && docker compose up -d --build"
log "  4. Trỏ DNS Cloudflare về IP VPS — SSL do Cloudflare, không cần cert local"
log ""
log "Script vận hành: ${STACK_ROOT}/infra/scripts/{deploy,backup,migrate,cleanup}.sh"
