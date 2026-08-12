#!/usr/bin/env bash
# Usage: db-create.sh <db_name> <site_domain> [db_user] [db_password]
set -euo pipefail
STACK_ROOT="${STACK_ROOT:-/opt/stack}"
DB_NAME="${1:-}"
SITE_DOMAIN="${2:-}"
DB_USER="${3:-}"
DB_PASS="${4:-}"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

[[ -n "$DB_NAME" ]] || die "Missing database name"
[[ "$DB_NAME" =~ ^[a-zA-Z0-9_]+$ ]] || die "Invalid database name"
[[ -n "$SITE_DOMAIN" ]] || die "Missing site domain — every database must belong to a website"
SITE_DOMAIN="$(printf '%s' "${SITE_DOMAIN}" | tr '[:upper:]' '[:lower:]')"
[[ "${SITE_DOMAIN}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || die "Invalid site domain"

cd "$STACK_ROOT"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"
# shellcheck source=_db_registry.sh
source "${STACK_ROOT}/infra/scripts/_db_registry.sh"
# shellcheck source=/dev/null
source .env

ensure_python3 || die "python3 required"

SITES_FILE="${STACK_ROOT}/data/panel/sites.json"
[[ -f "${SITES_FILE}" ]] || die "sites.json not found"
export SITES_FILE SITE_DOMAIN
SITE_OK="$("${PYBIN}" -c "
import json, os
domain = os.environ['SITE_DOMAIN']
with open(os.environ['SITES_FILE']) as f:
    print('1' if any((s.get('domain') or '').strip().lower() == domain for s in json.load(f)) else '0')
" 2>/dev/null || echo 0)"
[[ "${SITE_OK}" == "1" ]] || die "Site not found: ${SITE_DOMAIN}"

DB_USER="${DB_USER:-${DB_NAME}}"
DB_PASS="${DB_PASS:-$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)}"

stack_compose exec -T mariadb mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" -e \
  "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
   GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
   FLUSH PRIVILEGES;" 2>/dev/null \
  || die "Failed to create database"

db_registry_upsert "${DB_NAME}" "${DB_USER}" "${SITE_DOMAIN}" 2>/dev/null || true

"${PYBIN}" -c "import json; print(json.dumps({'ok':True,'name':'${DB_NAME}','user':'${DB_USER}','password':'${DB_PASS}','siteDomain':'${SITE_DOMAIN}'}))"
