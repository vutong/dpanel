#!/usr/bin/env bash
set -euo pipefail
STACK_ROOT="${STACK_ROOT:-/opt/stack}"
MODE="${1:-}"

cd "$STACK_ROOT"
# shellcheck source=/dev/null
[[ -f .env ]] && source .env

PANEL_DOMAIN="${PANEL_DOMAIN:-panel.local}"

cat > "${STACK_ROOT}/infra/nginx/conf.d/00-panel.conf" <<EOF
server {
    listen 80;
    listen 8080;
    server_name ${PANEL_DOMAIN};

    location / {
        proxy_pass http://dpanel:3000;
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

cat > "${STACK_ROOT}/infra/nginx/conf.d/99-pma.conf" <<'EOF'
server {
    listen 80;
    server_name _;

    location /pma/ {
        proxy_pass http://phpmyadmin:80/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_buffering off;
    }
}
EOF

if [[ "$MODE" != "panel-only" ]]; then
  docker compose exec -T nginx nginx -s reload 2>/dev/null \
    || docker compose restart nginx 2>/dev/null \
    || true
fi
