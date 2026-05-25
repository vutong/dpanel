#!/usr/bin/env bash
set -euo pipefail
STACK_ROOT="${STACK_ROOT:-/opt/stack}"
DB_NAME="${1:-}"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }
[[ -n "$DB_NAME" ]] || die "Missing database name"
[[ "$DB_NAME" =~ ^[a-zA-Z0-9_]+$ ]] || die "Invalid name"

for protected in mysql information_schema performance_schema sys dpanel; do
  [[ "$DB_NAME" == "$protected" ]] && die "Cannot delete system database: ${DB_NAME}"
done

cd "$STACK_ROOT"
# shellcheck source=/dev/null
source .env

docker compose exec -T mariadb mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" -e \
  "DROP DATABASE IF EXISTS \`${DB_NAME}\`;" 2>/dev/null \
  || die "Failed to delete database"

echo "{\"ok\":true,\"name\":\"${DB_NAME}\"}"
