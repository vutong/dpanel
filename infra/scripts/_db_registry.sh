# Database registry (name + user + siteDomain). Source from db-*.sh — do not execute directly.
_db_registry_path() {
  echo "${STACK_ROOT}/data/panel/databases.json"
}

# db_registry_upsert <name> <user> [site_domain]
# If site_domain is omitted, preserves existing siteDomain on update.
db_registry_upsert() {
  local name="$1" user="$2" site="${3:-}"
  ensure_python3 || return 1
  mkdir -p "${STACK_ROOT}/data/panel"
  export REGISTRY_PATH="$(_db_registry_path)" DB_NAME="${name}" DB_USER="${user}" DB_SITE="${site}"
  "${PYBIN}" <<'PY'
import json, os
from datetime import datetime, timezone

path = os.environ["REGISTRY_PATH"]
name = os.environ["DB_NAME"]
user = os.environ["DB_USER"]
site = (os.environ.get("DB_SITE") or "").strip().lower()
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

items = []
if os.path.isfile(path):
    try:
        with open(path, encoding="utf-8") as f:
            items = json.load(f)
    except (json.JSONDecodeError, OSError):
        items = []

prev = next((x for x in items if x.get("name") == name), None)
created = (prev or {}).get("createdAt") or now
if not site and prev:
    site = (prev.get("siteDomain") or "").strip().lower()

entry = {"name": name, "user": user, "createdAt": created}
if site:
    entry["siteDomain"] = site

items = [x for x in items if x.get("name") != name]
items.append(entry)

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

# Print database names linked to a site domain (one per line).
db_registry_names_for_site() {
  local site="$1"
  ensure_python3 || return 0
  local path
  path="$(_db_registry_path)"
  [[ -f "${path}" ]] || return 0
  export REGISTRY_PATH="${path}" DB_SITE="${site}"
  "${PYBIN}" <<'PY'
import json, os

path = os.environ["REGISTRY_PATH"]
site = (os.environ.get("DB_SITE") or "").strip().lower()
try:
    with open(path, encoding="utf-8") as f:
        items = json.load(f)
except (json.JSONDecodeError, OSError):
    items = []
for item in items:
    if (item.get("siteDomain") or "").strip().lower() == site:
        name = (item.get("name") or "").strip()
        if name:
            print(name)
PY
}
