#!/usr/bin/env bash
set -euo pipefail
STACK_ROOT="${STACK_ROOT:-/opt/stack}"
cd "$STACK_ROOT"
# shellcheck source=/dev/null
source .env

docker compose exec -T mariadb mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" -N -e \
  "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('information_schema','mysql','performance_schema','sys');" \
  2>/dev/null | awk '{print}' | python3 -c "
import sys, json
dbs = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(dbs))
"
