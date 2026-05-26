#!/usr/bin/env bash
set -euo pipefail
STACK_ROOT="${STACK_ROOT:-/opt/stack}"
cd "$STACK_ROOT"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"
# shellcheck source=_db_registry.sh
source "${STACK_ROOT}/infra/scripts/_db_registry.sh"
# shellcheck source=/dev/null
source .env

ensure_python3 || exit 1

mysql_dbs="$(stack_compose exec -T mariadb mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" -N -e \
  "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('information_schema','mysql','performance_schema','sys');" \
  2>/dev/null | awk '{print}' || true)"

mysql_users="$(stack_compose exec -T mariadb mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" -N -e \
  "SELECT DISTINCT table_schema,
    TRIM(BOTH \"'\" FROM SUBSTRING_INDEX(GRANTEE, '@', 1)) AS db_user
   FROM information_schema.schema_privileges
   WHERE table_schema NOT IN ('information_schema','mysql','performance_schema','sys')
   ORDER BY table_schema, db_user;" \
  2>/dev/null | awk '{print}' || true)"

export REGISTRY_PATH="$(_db_registry_path)" MYSQL_DBS="${mysql_dbs}" MYSQL_USERS="${mysql_users}"
"${PYBIN}" <<'PY'
import json, os
from collections import defaultdict

registry_path = os.environ.get("REGISTRY_PATH", "")
mysql_dbs = [l.strip() for l in os.environ.get("MYSQL_DBS", "").splitlines() if l.strip()]
mysql_users = os.environ.get("MYSQL_USERS", "").splitlines()

grant_users = defaultdict(list)
for line in mysql_users:
    parts = line.split(None, 1)
    if len(parts) == 2:
        db, user = parts[0].strip(), parts[1].strip()
        if user and user not in ("root", "mariadb", "mysql"):
            grant_users[db].append(user)

registry = {}
if registry_path and os.path.isfile(registry_path):
    try:
        with open(registry_path, encoding="utf-8") as f:
            for item in json.load(f):
                n = (item.get("name") or "").strip()
                if n:
                    registry[n] = item
    except (json.JSONDecodeError, OSError):
        pass

out = []
seen = set()
for name in sorted(mysql_dbs):
    seen.add(name)
    reg = registry.get(name) or {}
    user = (reg.get("user") or "").strip()
    if not user:
        candidates = grant_users.get(name) or []
        user = name if name in candidates else (candidates[0] if candidates else name)
    out.append({
        "name": name,
        "user": user,
        "createdAt": reg.get("createdAt"),
    })

# Prune registry to databases that still exist
if registry_path and registry:
    pruned = [registry[n] for n in sorted(seen) if n in registry]
    if len(pruned) != len(registry):
        with open(registry_path, "w", encoding="utf-8") as f:
            json.dump(pruned, f, indent=2)

print(json.dumps(out))
PY
