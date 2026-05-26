#!/usr/bin/env bash
# Usage: db-create.sh <db_name> [db_user] [db_password]
set -euo pipefail
STACK_ROOT="${STACK_ROOT:-/opt/stack}"
DB_NAME="${1:-}"
DB_USER="${2:-}"
DB_PASS="${3:-}"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

[[ -n "$DB_NAME" ]] || die "Missing database name"
[[ "$DB_NAME" =~ ^[a-zA-Z0-9_]+$ ]] || die "Invalid database name"

cd "$STACK_ROOT"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"
# shellcheck source=_db_registry.sh
source "${STACK_ROOT}/infra/scripts/_db_registry.sh"
# shellcheck source=/dev/null
source .env

DB_USER="${DB_USER:-${DB_NAME}}"
DB_PASS="${DB_PASS:-$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)}"

stack_compose exec -T mariadb mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" -e \
  "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
   GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
   FLUSH PRIVILEGES;" 2>/dev/null \
  || die "Failed to create database"

db_registry_upsert "${DB_NAME}" "${DB_USER}" 2>/dev/null || true

python3 -c "import json; print(json.dumps({'ok':True,'name':'${DB_NAME}','user':'${DB_USER}','password':'${DB_PASS}'}))"
