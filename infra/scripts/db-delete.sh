#!/usr/bin/env bash
# Usage: db-delete.sh <db_name> [--keep-user] [db_user]
# Drops database; optionally drops MariaDB user (default: drop user matching db name).
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
DB_NAME="${1:-}"
DROP_USER=1
DB_USER=""

shift 2>/dev/null || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-user) DROP_USER=0; shift ;;
    --drop-user) DROP_USER=1; shift ;;
    -h|--help)
      echo "Usage: db-delete.sh <db_name> [--keep-user] [db_user]" >&2
      exit 0
      ;;
    *)
      DB_USER="$1"
      shift
      ;;
  esac
done

log() { echo "[dpanel] $*" >&2; }

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

[[ -n "$DB_NAME" ]] || die "Missing database name"
[[ "$DB_NAME" =~ ^[a-zA-Z0-9_]+$ ]] || die "Invalid database name"

for protected in mysql information_schema performance_schema sys; do
  [[ "$DB_NAME" == "$protected" ]] && die "Cannot delete system database: ${DB_NAME}"
done

cd "${STACK_ROOT}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"
# shellcheck source=_db_registry.sh
source "${STACK_ROOT}/infra/scripts/_db_registry.sh"
# shellcheck source=/dev/null
[[ -f .env ]] && source .env

DB_USER="${DB_USER:-${DB_NAME}}"

log "Deleting database: ${DB_NAME}"
stack_compose exec -T mariadb mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" -e \
  "DROP DATABASE IF EXISTS \`${DB_NAME}\`;" 2>/dev/null \
  || die "Failed to drop database ${DB_NAME}"
log "Dropped database ${DB_NAME}"

DROPPED_USER=""
if [[ "${DROP_USER}" -eq 1 && -n "${DB_USER}" ]]; then
  safe_user=1
  for protected in root mysql mariadb; do
    [[ "${DB_USER}" == "$protected" ]] && safe_user=0
  done
  if [[ "${safe_user}" -eq 1 ]]; then
    if stack_compose exec -T mariadb mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" -e \
      "DROP USER IF EXISTS '${DB_USER}'@'%'; FLUSH PRIVILEGES;" 2>/dev/null; then
      DROPPED_USER="${DB_USER}"
      log "Dropped user ${DB_USER}@%"
    else
      log "Warning: could not drop user ${DB_USER} (may not exist)"
    fi
  fi
fi

db_registry_remove "${DB_NAME}" 2>/dev/null || true

printf '{"ok":true,"name":"%s","droppedUser":%s}\n' \
  "${DB_NAME}" \
  "$( [[ -n "${DROPPED_USER}" ]] && echo "\"${DROPPED_USER}\"" || echo 'null' )"
