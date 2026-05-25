#!/usr/bin/env bash
set -euo pipefail
STACK_ROOT="${STACK_ROOT:-/opt/stack}"
DB_NAME="${1:-}"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }
[[ -n "$DB_NAME" ]] || die "Thiếu tên database"
[[ "$DB_NAME" =~ ^[a-zA-Z0-9_]+$ ]] || die "Tên không hợp lệ"

for protected in mysql information_schema performance_schema sys dpanel; do
  [[ "$DB_NAME" == "$protected" ]] && die "Không được xóa database hệ thống: ${DB_NAME}"
done

cd "$STACK_ROOT"
# shellcheck source=/dev/null
source .env

docker compose exec -T mariadb mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" -e \
  "DROP DATABASE IF EXISTS \`${DB_NAME}\`;" 2>/dev/null \
  || die "Không xóa được database"

echo "{\"ok\":true,\"name\":\"${DB_NAME}\"}"
