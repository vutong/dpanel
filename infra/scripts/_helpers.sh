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

# Serialize site create/delete Docker work (avoids concurrent compose → panel 502).
_site_ops_lock_dir() {
  echo "${STACK_ROOT}/data/panel/.site-ops.lock"
}

site_ops_lock_acquire() {
  local lock="$(_site_ops_lock_dir)"
  mkdir -p "$(dirname "${lock}")"
  local i
  for ((i = 0; i < 180; i++)); do
    if mkdir "${lock}" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "[dpanel] WARNING: site ops lock busy — proceeding anyway" >&2
  return 0
}

site_ops_lock_release() {
  rmdir "$(_site_ops_lock_dir)" 2>/dev/null || true
}

site_op_status_file() {
  local domain="$1"
  mkdir -p "${STACK_ROOT}/data/panel/site-ops"
  echo "${STACK_ROOT}/data/panel/site-ops/${domain}.json"
}

# Panel polls data/panel/site-ops/<domain>.json for pull/rebuild progress.
site_op_status_write() {
  local domain="$1" op="$2" status="$3" message="${4:-}"
  ensure_python3 >/dev/null 2>&1 || {
    echo "[dpanel] WARNING: site_op_status_write skipped (python3 unavailable)" >&2
    return 1
  }
  local path
  path="$(site_op_status_file "${domain}")"
  export STATUS_PATH="${path}" DOMAIN="${domain}" OP="${op}" STATUS="${status}" MSG="${message}"
  "${PYBIN}" <<'PY'
import json, os
from datetime import datetime, timezone

path = os.environ["STATUS_PATH"]
data = {
    "domain": os.environ["DOMAIN"],
    "op": os.environ["OP"],
    "status": os.environ["STATUS"],
    "message": os.environ.get("MSG") or "",
    "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
PY
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

# YAML lines for Docker resource limits (from data/panel/site-resources/<slug>.json).
_site_resource_compose_lines() {
  local domain="$1"
  local slug res cpu mem disk
  slug="$(site_slug "$domain")"
  res="${STACK_ROOT}/data/panel/site-resources/${slug}.json"
  cpu=0
  mem=0
  disk=0
  if [[ -f "${res}" ]] && ensure_python3 >/dev/null 2>&1; then
    read -r cpu mem disk <<< "$("${PYBIN}" -c "
import json
with open('${res}') as f:
    d = json.load(f)
print(float(d.get('cpuLimit') or 0), int(d.get('memoryMb') or 0), int(d.get('diskGb') or 0))
" 2>/dev/null || echo "0 0 0")"
  fi
  if awk "BEGIN {exit !(${cpu} > 0)}" 2>/dev/null; then
    echo "    cpus: ${cpu}"
  fi
  if [[ "${mem}" -gt 0 ]] 2>/dev/null; then
    echo "    mem_limit: ${mem}m"
  fi
  if [[ "${disk}" -gt 0 ]] 2>/dev/null; then
    echo "    storage_opt:"
    echo "      size: ${disk}G"
  fi
}

write_nuxt_compose_fragment() {
  local domain="$1"
  local slug frag extras
  slug="$(site_slug "$domain")"
  frag="${STACK_ROOT}/compose.d/nuxt-${slug}.yml"
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
      DPANEL_SITE_DOMAIN: ${domain}
      DPANEL_INTERNAL_SECRET: \${DPANEL_INTERNAL_SECRET}
    volumes:
      - ./apps/${domain}:/app
    networks:
      - stack
EOF
  extras="$(_site_resource_compose_lines "${domain}" || true)"
  if [[ -n "${extras}" ]]; then
    printf '%s\n' "${extras}" >> "${frag}"
  fi
}

write_nginx_node_site() {
  local domain="$1"
  local slug server_names wildcard_base extra_line
  slug="$(site_slug "$domain")"
  server_names="${domain}"
  local routing_json="${STACK_ROOT}/data/panel/site-routing/${slug}.json"
  if [[ -f "${routing_json}" ]]; then
    if ensure_python3 >/dev/null 2>&1 && [[ -n "${PYBIN:-}" ]]; then
      wildcard_base="$("${PYBIN}" -c "
import json, os
path = os.environ['ROUTING_JSON_PATH']
with open(path) as f:
    data = json.load(f)
print((data.get('wildcardBase') or '').strip().lower())
" ROUTING_JSON_PATH="${routing_json}" 2>/dev/null || true)"
      extra_line="$("${PYBIN}" -c "
import json, os
path = os.environ['ROUTING_JSON_PATH']
with open(path) as f:
    data = json.load(f)
domains = data.get('extraDomains') or []
print(' '.join(str(d).strip().lower() for d in domains if str(d).strip()))
" ROUTING_JSON_PATH="${routing_json}" 2>/dev/null || true)"
    elif command -v node >/dev/null 2>&1; then
      wildcard_base="$(node -e "
const fs = require('fs');
const p = process.argv[1];
try {
  const data = JSON.parse(fs.readFileSync(p, 'utf8'));
  process.stdout.write(String(data.wildcardBase || '').trim().toLowerCase());
} catch {}
" "${routing_json}" 2>/dev/null || true)"
      extra_line="$(node -e "
const fs = require('fs');
const p = process.argv[1];
try {
  const data = JSON.parse(fs.readFileSync(p, 'utf8'));
  const arr = Array.isArray(data.extraDomains) ? data.extraDomains : [];
  process.stdout.write(arr.map(v => String(v || '').trim().toLowerCase()).filter(Boolean).join(' '));
} catch {}
" "${routing_json}" 2>/dev/null || true)"
    else
      echo "[dpanel] Warning: cannot parse ${routing_json} (python3/node unavailable) — using primary domain only" >&2
    fi
      if [[ -n "${wildcard_base}" ]]; then
        server_names="${server_names} ${wildcard_base} www.${wildcard_base} *.${wildcard_base}"
      fi
      [[ -n "${extra_line}" ]] && server_names="${server_names} ${extra_line}"
  fi
  cat > "${STACK_ROOT}/infra/nginx/conf.d/${domain}.conf" <<EOF
server {
    listen 80;
    server_name ${server_names};
    resolver 127.0.0.11 valid=10s ipv6=off;

    location / {
        set \$nuxt_upstream nuxt-${slug}:3000;
        proxy_pass http://\$nuxt_upstream;
        proxy_http_version 1.1;
        proxy_connect_timeout 30s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
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

# Regenerate nginx vhost from data/panel/site-routing/<slug>.json (wildcard + extraDomains) and reload.
site_apply_nginx_routing() {
  local domain="$1"
  [[ -n "${domain}" ]] || return 1
  write_nginx_node_site "${domain}"
  nginx_test_stack 1 || return 1
  nginx_reload_stack 2>/dev/null || return 1
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

# Wait until site Nuxt container is running and not in a restart loop.
_nuxt_container_wait_ready() {
  local cname="$1"
  local max_wait="${2:-90}"
  local i cid status restarting
  for ((i = 0; i < max_wait; i++)); do
    cid="$(docker ps -aq -f "name=^${cname}$" 2>/dev/null | head -1)"
    [[ -n "${cid}" ]] || { sleep 2; continue; }
    status="$(docker inspect -f '{{.State.Status}}' "${cid}" 2>/dev/null || echo "")"
    restarting="$(docker inspect -f '{{.State.Restarting}}' "${cid}" 2>/dev/null || echo false)"
    if [[ "${status}" == "running" && "${restarting}" != "true" ]]; then
      echo "${cid}"
      return 0
    fi
    sleep 2
  done
  return 1
}

_nuxt_container_log_tail() {
  local cname="$1"
  local lines="${2:-60}"
  echo "[dpanel] --- docker logs ${cname} (last ${lines} lines) ---" >&2
  docker logs --tail "${lines}" "${cname}" 2>&1 || true
  echo "[dpanel] --- end docker logs ---" >&2
}

# npm install + build inside the per-site Nuxt container, then restart (caller should hold site_ops_lock).
nuxt_container_build() {
  local domain="$1"
  local node_modules_mode="${2:-auto}"
  local slug svc cname nuxt_cid app_dir
  [[ -n "${domain}" ]] || return 1
  slug="$(site_slug "${domain}")"
  svc="nuxt-${slug}"
  cname="$(_nuxt_container_name "${slug}")"
  app_dir="${STACK_ROOT}/apps/${domain}"

  [[ -f "${app_dir}/package.json" ]] || {
    echo "[dpanel] No package.json in apps/${domain}/ — deploy code first" >&2
    return 1
  }

  cd "${STACK_ROOT}"
  stack_compose up -d "${svc}" 2>/dev/null || true

  nuxt_cid="$(_nuxt_container_wait_ready "${cname}" 90)" || {
    echo "[dpanel] Nuxt container not ready (${cname}) — check: docker ps -a | grep ${slug}" >&2
    _nuxt_container_log_tail "${cname}" 40
    return 1
  }

  echo "[dpanel] npm install & build for ${domain} (container ${cname})…" >&2
  docker exec -e DPANEL_NODE_MODULES_MODE="${node_modules_mode}" "${nuxt_cid}" bash -lc '
    set -euo pipefail
    if [ -f .env ]; then set -a; . ./.env; set +a; fi
    mode="${DPANEL_NODE_MODULES_MODE:-auto}"

    install_once() {
      if [ -f package-lock.json ]; then
        npm ci || return 1
      else
        npm install || return 1
      fi
    }

    if [ "${mode}" = "clean" ]; then
      rm -rf node_modules
      install_once
    elif [ "${mode}" = "keep" ]; then
      install_once
    elif [ "${mode}" = "auto" ] || [ -z "${mode}" ]; then
      if ! install_once; then
        echo "[dpanel] auto: npm install failed; cleaning node_modules and retrying…" >&2
        rm -rf node_modules
        install_once
      fi
    else
      echo "[dpanel] Invalid DPANEL_NODE_MODULES_MODE='${mode}' — defaulting to auto" >&2
      if ! install_once; then
        rm -rf node_modules
        install_once
      fi
    fi
    if grep -q "\"mongoose\"" package.json 2>/dev/null && [ ! -d node_modules/mongoose ]; then
      echo "[dpanel] Installing mongoose (listed in package.json)…"
      npm install mongoose
    fi
    npm run build
  ' || {
    _nuxt_container_log_tail "${cname}" 40
    return 1
  }

  if [[ ! -f "${app_dir}/.output/server/index.mjs" ]]; then
    echo "[dpanel] Build finished but missing .output/server/index.mjs — check package.json build script" >&2
    return 1
  fi

  echo "[dpanel] Restarting ${cname}…" >&2
  docker restart "${cname}" 2>/dev/null || return 1

  nuxt_cid="$(_nuxt_container_wait_ready "${cname}" 90)" || {
    echo "[dpanel] Container did not become ready after restart" >&2
    _nuxt_container_log_tail "${cname}" 80
    return 1
  }

  local i
  for ((i = 0; i < 45; i++)); do
    if docker exec "${nuxt_cid}" wget -q -O- --timeout=3 http://127.0.0.1:3000/ >/dev/null 2>&1 \
      || docker exec "${nuxt_cid}" wget -q -O- --timeout=3 http://127.0.0.1:3000/api/health >/dev/null 2>&1; then
      echo "[dpanel] App responding on :3000" >&2
      break
    fi
    sleep 2
  done

  if ! docker exec "${nuxt_cid}" wget -q -O- --timeout=3 http://127.0.0.1:3000/ >/dev/null 2>&1 \
    && ! docker exec "${nuxt_cid}" wget -q -O- --timeout=3 http://127.0.0.1:3000/api/health >/dev/null 2>&1; then
    echo "[dpanel] Build OK but app not listening on :3000 yet" >&2
    _nuxt_container_log_tail "${cname}" 80
    if ! docker exec "${nuxt_cid}" sh -c 'test -d node_modules/mongoose' 2>/dev/null; then
      echo "[dpanel] Hint: add mongoose to package.json (npm install mongoose) and Rebuild" >&2
    fi
    if [[ ! -f "${app_dir}/.env" ]]; then
      echo "[dpanel] Hint: set MONGODB_URI in apps/${domain}/.env (panel → Edit .env) then restart" >&2
    fi
    return 1
  fi

  if docker exec "${nuxt_cid}" sh -c 'node -e "const p=require(\"./package.json\"); process.exit(p.scripts && p.scripts[\"sync:dpanel-routing\"] ? 0 : 1)"' 2>/dev/null; then
    echo "[dpanel] Syncing custom store domains from MongoDB (sync:dpanel-routing)…" >&2
    if ! docker exec "${nuxt_cid}" sh -c '
      set -e
      if [ -f .env ]; then set -a; . ./.env; set +a; fi
      npm run sync:dpanel-routing
    ' 2>&1; then
      echo "[dpanel] Warning: custom domain sync failed — rebuild OK; fix MongoDB/dpanel env and run: npm run sync:dpanel-routing" >&2
    fi
  fi

  return 0
}

# After site create from panel: start Nuxt service + reload nginx (never "compose up nginx" — depends_on dpanel → 502).
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
    site_ops_lock_acquire
    [[ -n \"${nuxt_svc}\" ]] && stack_compose up -d \"${nuxt_svc}\" 2>/dev/null || true
    nginx_reload_stack 2>/dev/null || true
    site_ops_lock_release
  " >> "${STACK_ROOT}/logs/node/${log_name}.log" 2>&1 &
  disown 2>/dev/null || true
}

# Background finish after site-delete.sh removed registry + configs (docker-only — no compose up/stop).
site_delete_finish_background() {
  local domain="$1"
  local slug="$2"
  local had_nuxt="${3:-0}"
  local app_dir="${STACK_ROOT}/apps/${domain}"
  local log_name="site-delete-${slug}"
  mkdir -p "${STACK_ROOT}/logs/node"
  nohup bash -c "
    sleep 0.3
    export STACK_ROOT='${STACK_ROOT}'
    cd \"\${STACK_ROOT}\"
    # shellcheck source=_helpers.sh
    source \"\${STACK_ROOT}/infra/scripts/_helpers.sh\"
    site_ops_lock_acquire
    if [[ -d '${app_dir}' ]]; then
      rm -rf '${app_dir}'
      echo '[dpanel] Deleted ${app_dir}/' >&2
    fi
    if [[ ${had_nuxt} -eq 1 ]]; then
      docker_stop_container_by_name \"\$(_nuxt_container_name '${slug}')\"
    fi
    prune_orphan_site_artifacts --no-up --docker-only 2>/dev/null || true
    nginx_reload_stack 2>/dev/null || true
    site_ops_lock_release
    echo '[dpanel] Site delete background done: ${domain}' >&2
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

# Reload nginx in the running container (plain docker only — compose exec/restart can disturb dpanel).
nginx_reload_stack() {
  local cid
  cid="$(_nginx_container_id)"
  if [[ -n "${cid}" ]]; then
    docker exec "${cid}" nginx -s reload 2>/dev/null && return 0
    docker restart "${cid}" 2>/dev/null && return 0
  fi
  return 1
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
    [[ "${domain}" == "00-default-404" || "${domain}" == "10-panel" ]] && continue
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
    [[ "${domain}" == "00-default-404" || "${domain}" == "10-panel" ]] && continue
    is_legacy_nuxt_vhost "$f" || continue
    mv -f "$f" "${STACK_ROOT}/infra/nginx/conf.d/disabled/${domain}.conf"
    moved=$((moved + 1))
  done
  shopt -u nullglob
  [[ "${moved}" -gt 0 ]]
}

# Remove nginx/compose/container artifacts for domains not listed in sites.json.
# --no-up: skip "compose up --remove-orphans" (panel site-delete — full up restarts dpanel → 502).
# --docker-only: stop orphans via docker stop/rm, not "compose stop" (compose file may already be gone).
prune_orphan_site_artifacts() {
  local skip_up=0 docker_only=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-up) skip_up=1 ;;
      --docker-only) docker_only=1 ;;
    esac
    shift
  done

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
    [[ "${domain}" == "00-default-404" || "${domain}" == "10-panel" ]] && continue
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
      if [[ "${docker_only}" -eq 1 ]]; then
        docker_stop_container_by_name "$(_nuxt_container_name "${slug}")"
      else
        svc="nuxt-${slug}"
        stack_compose stop "${svc}" 2>/dev/null || true
        stack_compose rm -f "${svc}" 2>/dev/null || true
      fi
      rm -f "$f"
    fi
  done
  shopt -u nullglob

  [[ "${skip_up}" -eq 1 ]] && return 0
  cd "${STACK_ROOT}"
  stack_compose up -d --remove-orphans 2>/dev/null || true
}
