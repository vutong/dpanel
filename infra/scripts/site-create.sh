#!/usr/bin/env bash
# Usage: site-create.sh <domain> <node|php> [github_url]
# Private repo: set GITHUB_TOKEN in env (not argv — avoids leaking in logs)
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
DOMAIN="${1:-}"
RUNTIME="${2:-}"
GITHUB_URL="${3:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-${4:-}}"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

[[ -n "$DOMAIN" && -n "$RUNTIME" ]] || die "Missing domain or runtime"
[[ "$RUNTIME" == "node" || "$RUNTIME" == "php" ]] || die "Runtime must be node or php"
[[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || die "Invalid domain"

SITES_FILE="${STACK_ROOT}/data/panel/sites.json"
APP_DIR="${STACK_ROOT}/apps/${DOMAIN}"
NGINX_CONF="${STACK_ROOT}/infra/nginx/conf.d/${DOMAIN}.conf"

mkdir -p "$APP_DIR"

if [[ -n "$GITHUB_URL" ]]; then
  rm -rf "${APP_DIR:?}"/*
  export GIT_TERMINAL_PROMPT=0

  _github_owner_repo() {
    if [[ "$GITHUB_URL" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
      GITHUB_OWNER="${BASH_REMATCH[1]}"
      GITHUB_REPO="${BASH_REMATCH[2]}"
      return 0
    fi
    return 1
  }

  _github_preflight() {
    [[ -n "${GITHUB_TOKEN:-}" ]] || return 0
    _github_owner_repo || return 0
    local code
    code="$(curl -sS -o /dev/null -w '%{http_code}' \
      -H "Authorization: bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}" 2>/dev/null || echo 000)"
    case "$code" in
      200) return 0 ;;
      404) die "GitHub: repository ${GITHUB_OWNER}/${GITHUB_REPO} not found or token has no access" ;;
      401|403)
        die "GitHub token rejected for ${GITHUB_OWNER}/${GITHUB_REPO}. Use classic PAT (ghp_) with repo scope, or fine-grained PAT with this repo selected and Contents: Read access (org may require admin approval)"
        ;;
      *) die "GitHub API check failed (HTTP ${code})" ;;
    esac
  }

  _redact_log() {
    local f="$1"
    [[ -n "${GITHUB_TOKEN:-}" ]] && sed "s/${GITHUB_TOKEN}/***REDACTED***/g" "$f" >&2 || cat "$f" >&2
  }

  _clone_with_github() {
    local base_url="${GITHUB_URL%.git}.git"
    export GITHUB_TOKEN
    local git_user="${GITHUB_USER:-x-access-token}"

    if [[ -n "${GITHUB_TOKEN}" ]]; then
      # 1) credential helper (classic ghp_ and many fine-grained tokens)
      if git -c "credential.helper=!f() { echo username=${git_user}; echo password=\${GITHUB_TOKEN}; }; f" \
        clone --depth 1 "$base_url" "${APP_DIR}/_repo_tmp" 2>>"${CLONE_ERR}" \
        || git -c "credential.helper=!f() { echo username=${git_user}; echo password=\${GITHUB_TOKEN}; }; f" \
        clone "$base_url" "${APP_DIR}/_repo_tmp" 2>>"${CLONE_ERR}"; then
        return 0
      fi

      # 2) x-access-token@github.com URL
      if [[ "$base_url" =~ ^https://github\.com/(.+)$ ]]; then
        local gh_path="${BASH_REMATCH[1]}"
        if git clone --depth 1 "https://x-access-token:${GITHUB_TOKEN}@github.com/${gh_path}" "${APP_DIR}/_repo_tmp" 2>>"${CLONE_ERR}" \
          || git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/${gh_path}" "${APP_DIR}/_repo_tmp" 2>>"${CLONE_ERR}"; then
          return 0
        fi
      fi

      # 3) Authorization bearer header
      if git -c "http.https://github.com/.extraheader=AUTHORIZATION: bearer ${GITHUB_TOKEN}" \
        clone --depth 1 "$base_url" "${APP_DIR}/_repo_tmp" 2>>"${CLONE_ERR}" \
        || git -c "http.https://github.com/.extraheader=AUTHORIZATION: bearer ${GITHUB_TOKEN}" \
        clone "$base_url" "${APP_DIR}/_repo_tmp" 2>>"${CLONE_ERR}"; then
        return 0
      fi
      return 1
    fi

    git clone --depth 1 "$base_url" "${APP_DIR}/_repo_tmp" 2>>"${CLONE_ERR}" \
      || git clone "$base_url" "${APP_DIR}/_repo_tmp" 2>>"${CLONE_ERR}"
  }

  _github_preflight
  CLONE_ERR="$(mktemp)"
  if ! _clone_with_github; then
    _redact_log "${CLONE_ERR}"
    rm -f "${CLONE_ERR}"
    die "git clone failed — see stderr above; try classic PAT (ghp_) with repo scope if fine-grained fails"
  fi
  rm -f "${CLONE_ERR}"
  shopt -s dotglob
  mv "${APP_DIR}/_repo_tmp"/* "$APP_DIR/" 2>/dev/null || true
  rm -rf "${APP_DIR}/_repo_tmp"
  shopt -u dotglob
else
  echo "Deploy application code to ${DOMAIN}" > "${APP_DIR}/.gitkeep"
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
