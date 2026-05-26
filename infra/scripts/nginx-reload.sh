#!/usr/bin/env bash
set -euo pipefail
STACK_ROOT="${STACK_ROOT:-/opt/stack}"
MODE="${1:-}"

log() { echo "[dpanel] $*"; }
die() { log "ERROR: $*"; exit 1; }

cd "$STACK_ROOT"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"
# shellcheck source=/dev/null
[[ -f .env ]] && source .env

PANEL_DOMAIN="${PANEL_DOMAIN:-panel.local}"

PMA_ABSOLUTE_URI="http://${PANEL_DOMAIN}/mariadb/"
if grep -q '^PMA_ABSOLUTE_URI=' "${STACK_ROOT}/.env" 2>/dev/null; then
  sed -i "s|^PMA_ABSOLUTE_URI=.*|PMA_ABSOLUTE_URI=${PMA_ABSOLUTE_URI}|" "${STACK_ROOT}/.env"
else
  echo "PMA_ABSOLUTE_URI=${PMA_ABSOLUTE_URI}" >> "${STACK_ROOT}/.env"
fi

mkdir -p "${STACK_ROOT}/infra/nginx/conf.d"
touch "${STACK_ROOT}/logs/nginx/access.log" "${STACK_ROOT}/logs/nginx/error.log"

log "Removing orphan site artifacts (not in sites.json)..."
prune_orphan_site_artifacts

log "Syncing site configs from sites.json..."
sync_site_configs

log "Migrating legacy Nuxt nginx vhosts (static upstream → resolver)..."
fix_legacy_nginx_vhosts
if quarantine_legacy_static_nuxt_vhosts; then
  log "Quarantined remaining legacy vhosts under conf.d/disabled/"
fi

log "Starting site containers (compose.d)..."
stack_compose_up_sites

cat > "${STACK_ROOT}/infra/nginx/conf.d/00-panel.conf" <<EOF
server {
    listen 80 default_server;
    listen 8080 default_server;
    server_name ${PANEL_DOMAIN} _;

    location /mariadb/ {
        proxy_pass http://phpmyadmin:80/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_redirect off;
    }

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

rm -f "${STACK_ROOT}/infra/nginx/conf.d/99-pma.conf" "${STACK_ROOT}/infra/nginx/conf.d/99-mariadb.conf"

log "Testing nginx configuration..."
if ! nginx_test_stack 1; then
  log "nginx configuration errors:"
  nginx_test_stack 0 2>&1 | tail -15 || true
  log "Invalid config in ${STACK_ROOT}/infra/nginx/conf.d/"
  log "Quarantining broken site configs (keeping 00-panel.conf)..."
  mkdir -p "${STACK_ROOT}/infra/nginx/conf.d/disabled"
  for f in "${STACK_ROOT}"/infra/nginx/conf.d/*.conf; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == "00-panel.conf" ]] && continue
    mv -f "$f" "${STACK_ROOT}/infra/nginx/conf.d/disabled/" 2>/dev/null || true
  done
  if ! nginx_test_stack 1; then
    nginx_test_stack 0 2>&1 | tail -15 || true
    log "Tip: fix sites in panel or restore configs from conf.d/disabled/"
    die "nginx config still invalid — run: dpanel nginx-reload after fixing sites"
  fi
  log "Panel nginx OK — disabled site vhosts moved to conf.d/disabled/"
fi

_nginx_running() {
  nginx_container_running || {
    stack_compose ps --format '{{.Service}} {{.State}}' 2>/dev/null | grep -E '^nginx running' >/dev/null
  }
}

if ! _nginx_running; then
  log "nginx is not running — starting stack..."
  stack_compose up -d
  sleep 3
fi

if ! _nginx_running; then
  log "nginx still not running — quarantining site vhosts and retrying..."
  mkdir -p "${STACK_ROOT}/infra/nginx/conf.d/disabled"
  for f in "${STACK_ROOT}"/infra/nginx/conf.d/*.conf; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == "00-panel.conf" ]] && continue
    mv -f "$f" "${STACK_ROOT}/infra/nginx/conf.d/disabled/" 2>/dev/null || true
  done
  fix_legacy_nginx_vhosts
  stack_compose up -d nginx 2>&1 || true
  sleep 3
fi

if ! _nginx_running; then
  log "nginx still not running. Last logs:"
  stack_compose logs nginx --tail 30 2>&1 || true
  die "nginx failed to start — run: dpanel site-remove <domain> or remove conf.d/*.conf (keep 00-panel.conf)"
fi

if [[ "$MODE" != "panel-only" ]]; then
  nginx_reload_stack 2>/dev/null \
    || stack_compose exec -T nginx nginx -s reload 2>/dev/null \
    || stack_compose restart nginx 2>/dev/null \
    || true
  sleep 2
fi

if ss -tln 2>/dev/null | grep -qE ':80 |:8080 '; then
  log "nginx listening on port 80 / 8080"
else
  log "Warning: ports 80/8080 not visible on host — run: dpanel status && dpanel logs nginx"
fi

log "Done — panel: http://${PANEL_DOMAIN} or http://$(hostname -I | awk '{print $1}'):8080"
