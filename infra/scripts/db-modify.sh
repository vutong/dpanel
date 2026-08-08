#!/usr/bin/env bash
# Usage: db-modify.sh <db_name> [db_user] [db_password]
# Resets MariaDB user password (auto-generates if password omitted).
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
DB_NAME="${1:-}"
DB_USER="${2:-}"
DB_PASS="${3:-}"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

[[ -n "$DB_NAME" ]] || die "Missing database name"
[[ "$DB_NAME" =~ ^[a-zA-Z0-9_]+$ ]] || die "Invalid database name"

for protected in mysql information_schema performance_schema sys; do
  [[ "$DB_NAME" == "$protected" ]] && die "Cannot modify system database: ${DB_NAME}"
done

cd "${STACK_ROOT}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"
# shellcheck source=_db_registry.sh
source "${STACK_ROOT}/infra/scripts/_db_registry.sh"
# shellcheck source=/dev/null
[[ -f .env ]] && source .env

ensure_python3 || die "python3 required"

DB_USER="${DB_USER:-}"
if [[ -z "${DB_USER}" ]]; then
  reg_path="$(_db_registry_path)"
  if [[ -f "${reg_path}" ]]; then
    DB_USER="$("${PYBIN}" -c "
import json, os
path, name = os.environ['REGISTRY_PATH'], os.environ['DB_NAME']
with open(path, encoding='utf-8') as f:
    for item in json.load(f):
        if item.get('name') == name:
            print((item.get('user') or '').strip())
            break
" 2>/dev/null REGISTRY_PATH="${reg_path}" DB_NAME="${DB_NAME}" || true)"
  fi
fi
DB_USER="${DB_USER:-${DB_NAME}}"

[[ "$DB_USER" =~ ^[a-zA-Z0-9_]+$ ]] || die "Invalid database user"
for protected in root mysql mariadb; do
  [[ "$DB_USER" == "$protected" ]] && die "Cannot reset password for system user: ${DB_USER}"
done

DB_PASS="${DB_PASS:-$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)}"

stack_compose exec -T mariadb mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" -e \
  "ALTER USER IF EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
   FLUSH PRIVILEGES;" 2>/dev/null \
  || die "Failed to reset password for user ${DB_USER}"

# Preserve existing siteDomain (third arg omitted).
db_registry_upsert "${DB_NAME}" "${DB_USER}" 2>/dev/null || true

python3 -c "import json; print(json.dumps({'ok':True,'name':'${DB_NAME}','user':'${DB_USER}','password':'${DB_PASS}','action':'modify'}))"
