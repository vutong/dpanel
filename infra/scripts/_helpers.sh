#!/usr/bin/env bash
# Shared helpers for /opt/stack/infra/scripts (source, do not execute directly).

STACK_ROOT="${STACK_ROOT:-/opt/stack}"

ensure_python3() {
  if command -v python3 >/dev/null 2>&1; then
    PYBIN="$(command -v python3)"
    return 0
  fi
  if command -v python >/dev/null 2>&1 && python -c 'import json' 2>/dev/null; then
    PYBIN="$(command -v python)"
    return 0
  fi
  if [[ "${EUID:-0}" -ne 0 ]]; then
    echo "[dpanel] python3 is required. Rebuild panel: dpanel update  OR  apt/apk install python3 on host" >&2
    return 1
  fi
  echo "[dpanel] Installing python3..." >&2
  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache python3
  elif command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y python3-minimal
  else
    echo "[dpanel] No apk/apt — install python3 manually" >&2
    return 1
  fi
  PYBIN="$(command -v python3)"
  [[ -n "${PYBIN}" ]]
}

# Colon-separated dirs for the docker compose CLI plugin (panel container often lacks it).
_stack_compose_plugin_dirs() {
  local -a dirs=()
  local d
  for d in \
    /usr/libexec/docker/cli-plugins \
    /usr/local/lib/docker/cli-plugins \
    /usr/lib/docker/cli-plugins; do
    if [[ -d "$d" ]] && [[ -x "$d/docker-compose" || -f "$d/docker-compose" ]]; then
      dirs+=("$d")
    fi
  done
  if [[ ${#dirs[@]} -gt 0 ]]; then
    local IFS=:
    echo "${dirs[*]}"
  fi
}

# docker compose with compose.yml + all compose.d/*.yml (per-site Nuxt services).
stack_compose() {
  local -a args=(-f "${STACK_ROOT}/compose.yml")
  local f plugin_dirs
  shopt -s nullglob
  for f in "${STACK_ROOT}"/compose.d/*.yml; do
    args+=(-f "$f")
  done
  shopt -u nullglob

  plugin_dirs="$(_stack_compose_plugin_dirs)"
  if [[ -n "${plugin_dirs}" ]]; then
    if DOCKER_CLI_PLUGIN_EXTRA_DIRS="${plugin_dirs}" docker compose version &>/dev/null 2>&1; then
      DOCKER_CLI_PLUGIN_EXTRA_DIRS="${plugin_dirs}" docker compose "${args[@]}" "$@"
      return $?
    fi
  fi
  if docker compose version &>/dev/null 2>&1; then
    docker compose "${args[@]}" "$@"
    return $?
  fi
  if command -v docker-compose &>/dev/null 2>&1; then
    docker-compose "${args[@]}" "$@"
    return $?
  fi
  echo "[dpanel] ERROR: docker compose unavailable (rebuild panel: sudo dpanel update)" >&2
  return 1
}

_stack_compose_available() {
  local plugin_dirs
  plugin_dirs="$(_stack_compose_plugin_dirs)"
  if [[ -n "${plugin_dirs}" ]] && DOCKER_CLI_PLUGIN_EXTRA_DIRS="${plugin_dirs}" docker compose version &>/dev/null 2>&1; then
    return 0
  fi
  docker compose version &>/dev/null 2>&1 && return 0
  command -v docker-compose &>/dev/null 2>&1
}

_stack_project_name() {
  local p="dpanel"
  if [[ -f "${STACK_ROOT}/.env" ]]; then
    # shellcheck source=/dev/null
    source "${STACK_ROOT}/.env"
    p="${COMPOSE_PROJECT_NAME:-dpanel}"
  fi
  echo "${p}"
}

# Running nginx container (works with plain docker CLI — no compose plugin required).
_nginx_container_id() {
  local project cid
  project="$(_stack_project_name)"
  cid="$(docker ps -q -f "name=^${project}-nginx\$" -f "status=running" 2>/dev/null | head -1)"
  [[ -n "${cid}" ]] && { echo "${cid}"; return 0; }
  cid="$(docker ps -q -f "name=nginx" -f "status=running" 2>/dev/null | head -1)"
  [[ -n "${cid}" ]] && echo "${cid}"
}

_nuxt_container_name() {
  local slug="$1"
  echo "$(_stack_project_name)-nuxt-${slug}"
}

docker_stop_container_by_name() {
  local name="$1"
  [[ -n "${name}" ]] || return 0
  docker stop "${name}" 2>/dev/null || true
  docker rm -f "${name}" 2>/dev/null || true
}

# compose.yml only (for nginx -t when compose.d should not affect the test).
stack_compose_base() {
  local -a args=(-f "${STACK_ROOT}/compose.yml")
  local plugin_dirs
  plugin_dirs="$(_stack_compose_plugin_dirs)"
  if [[ -n "${plugin_dirs}" ]]; then
    if DOCKER_CLI_PLUGIN_EXTRA_DIRS="${plugin_dirs}" docker compose version &>/dev/null 2>&1; then
      DOCKER_CLI_PLUGIN_EXTRA_DIRS="${plugin_dirs}" docker compose "${args[@]}" "$@"
      return $?
    fi
  fi
  if docker compose version &>/dev/null 2>&1; then
    docker compose "${args[@]}" "$@"
    return $?
  fi
  if command -v docker-compose &>/dev/null 2>&1; then
    docker-compose "${args[@]}" "$@"
    return $?
  fi
  return 1
}

nginx_container_running() {
  [[ -n "$(_nginx_container_id)" ]]
}

site_slug() {
  echo "$1" | tr '.' '-' | tr -cd 'a-zA-Z0-9-'
}

write_nuxt_compose_fragment() {
  local domain="$1"
  local slug
  slug="$(site_slug "$domain")"
  local frag="${STACK_ROOT}/compose.d/nuxt-${slug}.yml"
  mkdir -p "${STACK_ROOT}/compose.d"
  # shellcheck source=/dev/null
  [[ -f "${STACK_ROOT}/.env" ]] && source "${STACK_ROOT}/.env"
  cat > "${frag}" <<EOF
services:
  nuxt-${slug}:
    build:
      context: ./infra/docker/node
      dockerfile: Dockerfile
    container_name: ${PROJECT_NAME:-${COMPOSE_PROJECT_NAME:-dpanel}}-nuxt-${slug}
    restart: unless-stopped
    env_file: .env
    environment:
      NUXT_HOST: 0.0.0.0
      NUXT_PORT: 3000
    volumes:
      - ./apps/${domain}:/app
    networks:
      - stack
EOF
}

write_nginx_node_site() {
  local domain="$1"
  local slug
  slug="$(site_slug "$domain")"
  cat > "${STACK_ROOT}/infra/nginx/conf.d/${domain}.conf" <<EOF
server {
    listen 80;
    server_name ${domain};
    resolver 127.0.0.11 valid=10s ipv6=off;

    location / {
        set \$nuxt_upstream nuxt-${slug}:3000;
        proxy_pass http://\$nuxt_upstream;
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
}

write_nginx_php_site() {
  local domain="$1"
  cat > "${STACK_ROOT}/infra/nginx/conf.d/${domain}.conf" <<EOF
server {
    listen 80;
    server_name ${domain};
    root /var/www/apps/${domain}/public;
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
}

# Regenerate site nginx + compose.d from panel registry (fixes stale upstream configs).
sync_site_configs() {
  local sites_file="${STACK_ROOT}/data/panel/sites.json"
  [[ -f "${sites_file}" ]] || return 0
  ensure_python3 >/dev/null 2>&1 || return 0

  export SITES_FILE="${sites_file}"
  while IFS='|' read -r domain runtime; do
    [[ -n "${domain}" ]] || continue
    if [[ "${runtime}" == "node" ]]; then
      write_nuxt_compose_fragment "${domain}"
      write_nginx_node_site "${domain}"
    elif [[ "${runtime}" == "php" ]]; then
      write_nginx_php_site "${domain}"
    fi
  done < <("${PYBIN}" -c "
import json, os
with open(os.environ['SITES_FILE']) as f:
    for s in json.load(f):
        d = s.get('domain') or ''
        r = s.get('runtime') or ''
        if d:
            print(f'{d}|{r}')
" 2>/dev/null)
}

stack_compose_up_sites() {
  cd "${STACK_ROOT}"
  stack_compose up -d --remove-orphans 2>/dev/null || true
}

# After site create/delete from panel UI: reload nginx without full "compose up" (avoids restarting dpanel mid-request → 502).
site_finalize_async() {
  local log_name="${1:-site-ops}"
  local nuxt_svc="${2:-}"
  mkdir -p "${STACK_ROOT}/logs/node"
  nohup bash -c "
    sleep 0.5
    export STACK_ROOT='${STACK_ROOT}'
    cd \"\${STACK_ROOT}\"
    # shellcheck source=_helpers.sh
    source \"\${STACK_ROOT}/infra/scripts/_helpers.sh\"
    [[ -n \"${nuxt_svc}\" ]] && stack_compose up -d \"${nuxt_svc}\" 2>/dev/null || true
    stack_compose up -d nginx 2>/dev/null || true
    nginx_reload_stack 2>/dev/null || true
  " >> "${STACK_ROOT}/logs/node/${log_name}.log" 2>&1 &
  disown 2>/dev/null || true
}

# Wait until dpanel container healthcheck is healthy (or /api/ping responds).
wait_for_dpanel_ready() {
  local max_wait="${1:-90}"
  local i cid status out
  for ((i = 1; i <= max_wait; i++)); do
    cid="$(stack_compose ps -q dpanel 2>/dev/null | head -1)"
    if [[ -n "${cid}" ]]; then
      status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${cid}" 2>/dev/null || echo none)"
      if [[ "${status}" == "healthy" ]]; then
        return 0
      fi
      out="$(stack_compose exec -T dpanel wget -q -O- --timeout=2 http://127.0.0.1:3000/api/ping 2>/dev/null || true)"
      if printf '%s' "${out}" | grep -qE '"ok"[[:space:]]*:[[:space:]]*true'; then
        return 0
      fi
    fi
    sleep 1
  done
  return 1
}

# nginx -t — prefer docker exec on the running nginx container (no compose plugin needed).
nginx_test_stack() {
  local quiet="${1:-1}"
  local cid
  cid="$(_nginx_container_id)"
  if [[ -n "${cid}" ]]; then
    if [[ "${quiet}" -eq 1 ]]; then
      docker exec "${cid}" nginx -t >/dev/null 2>&1
    else
      docker exec "${cid}" nginx -t
    fi
    return $?
  fi
  if [[ "${quiet}" -eq 1 ]]; then
    stack_compose_base run --rm --no-deps nginx nginx -t >/dev/null 2>&1 && return 0
    stack_compose run --rm --no-deps nginx nginx -t >/dev/null 2>&1
    return $?
  fi
  stack_compose_base run --rm --no-deps nginx nginx -t \
    || stack_compose run --rm --no-deps nginx nginx -t
}

# Reload nginx in the running container (compose plugin not required).
nginx_reload_stack() {
  local cid
  cid="$(_nginx_container_id)"
  if [[ -n "${cid}" ]]; then
    docker exec "${cid}" nginx -s reload 2>/dev/null && return 0
    docker restart "${cid}" 2>/dev/null && return 0
  fi
  _stack_compose_available || return 1
  stack_compose exec -T nginx nginx -s reload 2>/dev/null \
    || stack_compose restart nginx
}

# Legacy v1 nginx: proxy_pass http://nuxt-<slug>:3000 (resolved at boot → fails if container down).
is_legacy_nuxt_vhost() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  grep -qE 'proxy_pass[[:space:]]+http://nuxt-' "$f" 2>/dev/null \
    && ! grep -q 'resolver 127.0.0.11' "$f" 2>/dev/null
}

site_runtime_from_registry() {
  local domain="$1"
  local sites_file="${STACK_ROOT}/data/panel/sites.json"
  [[ -f "${sites_file}" ]] || return 0
  ensure_python3 >/dev/null 2>&1 || return 0
  export SITES_FILE="${sites_file}" DOMAIN="${domain}"
  "${PYBIN}" -c "
import json, os, sys
domain = os.environ.get('DOMAIN', '')
with open(os.environ['SITES_FILE']) as f:
    for s in json.load(f):
        if s.get('domain') == domain:
            print(s.get('runtime') or '')
            sys.exit(0)
" 2>/dev/null || true
}

# Rewrite or quarantine old static-upstream Nuxt vhosts (safe when nuxt container is not up yet).
fix_legacy_nginx_vhosts() {
  local f domain runtime
  mkdir -p "${STACK_ROOT}/infra/nginx/conf.d/disabled"
  shopt -s nullglob
  for f in "${STACK_ROOT}"/infra/nginx/conf.d/*.conf; do
    [[ -f "$f" ]] || continue
    domain="$(basename "$f" .conf)"
    [[ "${domain}" == "00-panel" ]] && continue
    is_legacy_nuxt_vhost "$f" || continue
    runtime="$(site_runtime_from_registry "${domain}")"
    if [[ "${runtime}" == "node" ]]; then
      write_nginx_node_site "${domain}"
    else
      mv -f "$f" "${STACK_ROOT}/infra/nginx/conf.d/disabled/${domain}.conf" 2>/dev/null \
        || rm -f "$f"
    fi
  done
  shopt -u nullglob
}

quarantine_legacy_static_nuxt_vhosts() {
  local f domain moved=0
  mkdir -p "${STACK_ROOT}/infra/nginx/conf.d/disabled"
  shopt -s nullglob
  for f in "${STACK_ROOT}"/infra/nginx/conf.d/*.conf; do
    [[ -f "$f" ]] || continue
    domain="$(basename "$f" .conf)"
    [[ "${domain}" == "00-panel" ]] && continue
    is_legacy_nuxt_vhost "$f" || continue
    mv -f "$f" "${STACK_ROOT}/infra/nginx/conf.d/disabled/${domain}.conf"
    moved=$((moved + 1))
  done
  shopt -u nullglob
  [[ "${moved}" -gt 0 ]]
}

# Remove nginx/compose/container artifacts for domains not listed in sites.json.
prune_orphan_site_artifacts() {
  local sites_file="${STACK_ROOT}/data/panel/sites.json"
  # shellcheck source=/dev/null
  [[ -f "${STACK_ROOT}/.env" ]] && source "${STACK_ROOT}/.env"
  local panel_domain="${PANEL_DOMAIN:-}"
  ensure_python3 >/dev/null 2>&1 || return 0

  export SITES_FILE="${sites_file}" PANEL_DOMAIN="${panel_domain}"
  local registered_slugs registered_domains
  registered_slugs="$("${PYBIN}" -c "
import json, os, re
path = os.environ.get('SITES_FILE', '')
slugs = set()
if os.path.isfile(path):
    with open(path) as f:
        for s in json.load(f):
            d = (s.get('domain') or '').strip()
            if d:
                s = d.replace('.', '-')
                slugs.add(re.sub(r'[^a-zA-Z0-9-]', '', s))
print(' '.join(sorted(slugs)))
" 2>/dev/null || true)"
  registered_domains="$("${PYBIN}" -c "
import json, os
path = os.environ.get('SITES_FILE', '')
domains = []
if os.path.isfile(path):
    with open(path) as f:
        for s in json.load(f):
            d = (s.get('domain') or '').strip()
            if d:
                domains.append(d)
print(' '.join(domains))
" 2>/dev/null || true)"

  _is_registered_domain() {
    local d="$1"
    [[ " ${registered_domains} " == *" ${d} "* ]]
  }

  _is_registered_slug() {
    local s="$1"
    [[ " ${registered_slugs} " == *" ${s} "* ]]
  }

  local f domain slug svc
  shopt -s nullglob
  for f in "${STACK_ROOT}"/infra/nginx/conf.d/*.conf "${STACK_ROOT}"/infra/nginx/conf.d/disabled/*.conf; do
    [[ -f "$f" ]] || continue
    domain="$(basename "$f" .conf)"
    [[ "${domain}" == "00-panel" ]] && continue
    [[ -n "${panel_domain}" && "${domain}" == "${panel_domain}" ]] && continue
    if ! _is_registered_domain "${domain}"; then
      rm -f "$f"
    fi
  done

  for f in "${STACK_ROOT}"/compose.d/nuxt-*.yml; do
    [[ -f "$f" ]] || continue
    slug="${f##*/nuxt-}"
    slug="${slug%.yml}"
    if ! _is_registered_slug "${slug}"; then
      svc="nuxt-${slug}"
      stack_compose stop "${svc}" 2>/dev/null || true
      stack_compose rm -f "${svc}" 2>/dev/null || true
      rm -f "$f"
    fi
  done
  shopt -u nullglob

  cd "${STACK_ROOT}"
  stack_compose up -d --remove-orphans 2>/dev/null || true
}
