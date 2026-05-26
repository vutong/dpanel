# Database registry (name + user metadata). Source from db-*.sh — do not execute directly.
_db_registry_path() {
  echo "${STACK_ROOT}/data/panel/databases.json"
}

db_registry_upsert() {
  local name="$1" user="$2"
  ensure_python3 || return 1
  mkdir -p "${STACK_ROOT}/data/panel"
  export REGISTRY_PATH="$(_db_registry_path)" DB_NAME="${name}" DB_USER="${user}"
  "${PYBIN}" <<'PY'
import json, os
from datetime import datetime, timezone

path = os.environ["REGISTRY_PATH"]
name = os.environ["DB_NAME"]
user = os.environ["DB_USER"]
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

items = []
if os.path.isfile(path):
    try:
        with open(path, encoding="utf-8") as f:
            items = json.load(f)
    except (json.JSONDecodeError, OSError):
        items = []

items = [x for x in items if x.get("name") != name]
items.append({"name": name, "user": user, "createdAt": now})

with open(path, "w", encoding="utf-8") as f:
    json.dump(items, f, indent=2)
PY
}

db_registry_remove() {
  local name="$1"
  ensure_python3 || return 0
  local path
  path="$(_db_registry_path)"
  [[ -f "${path}" ]] || return 0
  export REGISTRY_PATH="${path}" DB_NAME="${name}"
  "${PYBIN}" <<'PY'
import json, os

path = os.environ["REGISTRY_PATH"]
name = os.environ["DB_NAME"]
try:
    with open(path, encoding="utf-8") as f:
        items = json.load(f)
except (json.JSONDecodeError, OSError):
    items = []
new = [x for x in items if x.get("name") != name]
if len(new) != len(items):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(new, f, indent=2)
PY
}
