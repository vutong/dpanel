#!/usr/bin/env bash
# Usage: site-create.sh <domain> <node|php> [github_url] [github_token]
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
DOMAIN="${1:-}"
RUNTIME="${2:-}"
GITHUB_URL="${3:-}"
GITHUB_TOKEN="${4:-}"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

[[ -n "$DOMAIN" && -n "$RUNTIME" ]] || die "Thiếu domain hoặc runtime"
[[ "$RUNTIME" == "node" || "$RUNTIME" == "php" ]] || die "Runtime phải là node hoặc php"
[[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || die "Domain không hợp lệ"

SITES_FILE="${STACK_ROOT}/data/panel/sites.json"
APP_DIR="${STACK_ROOT}/apps/${DOMAIN}"
NGINX_CONF="${STACK_ROOT}/infra/nginx/conf.d/${DOMAIN}.conf"

mkdir -p "$APP_DIR"

if [[ -n "$GITHUB_URL" ]]; then
  CLONE_URL="$GITHUB_URL"
  if [[ -n "$GITHUB_TOKEN" ]]; then
    CLONE_URL="${GITHUB_URL/https:\/\//https://${GITHUB_TOKEN}@}"
    CLONE_URL="${CLONE_URL/http:\/\//http://${GITHUB_TOKEN}@}"
  fi
  rm -rf "${APP_DIR:?}"/*
  git clone --depth 1 "$CLONE_URL" "${APP_DIR}/_repo_tmp" 2>/dev/null \
    || git clone "$CLONE_URL" "${APP_DIR}/_repo_tmp" \
    || die "Không clone được từ GitHub"
  shopt -s dotglob
  mv "${APP_DIR}/_repo_tmp"/* "$APP_DIR/" 2>/dev/null || true
  rm -rf "${APP_DIR}/_repo_tmp"
  shopt -u dotglob
else
  echo "Deploy mã vào ${DOMAIN}" > "${APP_DIR}/.gitkeep"
fi

if [[ "$RUNTIME" == "node" ]]; then
  SLUG="$(echo "$DOMAIN" | tr '.' '-' | tr -cd 'a-zA-Z0-9-')"
  COMPOSE_FRAG="${STACK_ROOT}/compose.d/nuxt-${SLUG}.yml"
  mkdir -p "${STACK_ROOT}/compose.d"
  cat > "$COMPOSE_FRAG" <<EOF
services:
  nuxt-${SLUG}:
    build:
      context: ./infra/docker/node
      dockerfile: Dockerfile
    container_name: ${PROJECT_NAME:-dpanel}-nuxt-${SLUG}
    restart: unless-stopped
    env_file: .env
    environment:
      NUXT_HOST: 0.0.0.0
      NUXT_PORT: 3000
    volumes:
      - ./apps/${DOMAIN}:/app
    networks:
      - stack
EOF
  cd "$STACK_ROOT"
  docker compose -f compose.yml -f "compose.d/nuxt-${SLUG}.yml" up -d "nuxt-${SLUG}" 2>/dev/null || true

  cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://nuxt-${SLUG}:3000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
else
  cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    root /var/www/apps/${DOMAIN}/public;
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
}
EOF
fi

# Cập nhật sites.json
export SITES_FILE DOMAIN RUNTIME GITHUB_URL
python3 <<'PY'
import json, os, datetime
path = os.environ["SITES_FILE"]
domain = os.environ["DOMAIN"]
runtime = os.environ["RUNTIME"]
github = os.environ.get("GITHUB_URL", "")

sites = []
if os.path.isfile(path):
    with open(path) as f:
        sites = json.load(f)

sites = [s for s in sites if s.get("domain") != domain]
sites.append({
    "domain": domain,
    "runtime": runtime,
    "githubUrl": github or None,
    "createdAt": datetime.datetime.utcnow().isoformat() + "Z"
})

with open(path, "w") as f:
    json.dump(sites, f, indent=2)
PY

bash "${STACK_ROOT}/infra/scripts/nginx-reload.sh"

echo "{\"ok\":true,\"domain\":\"${DOMAIN}\",\"runtime\":\"${RUNTIME}\"}"
