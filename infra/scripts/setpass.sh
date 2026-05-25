#!/usr/bin/env bash
# Update panel login password in data/panel/auth.json
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
AUTH_FILE="${STACK_ROOT}/data/panel/auth.json"
NEW_PASS="${1:-}"

if [[ -z "${NEW_PASS}" ]]; then
  echo "Usage: dpanel setpass <new-password>" >&2
  exit 1
fi

if [[ ${#NEW_PASS} -lt 8 ]]; then
  echo "Password must be at least 8 characters." >&2
  exit 1
fi

if [[ ! -f "${AUTH_FILE}" ]]; then
  echo "Not found: ${AUTH_FILE} (run install first)" >&2
  exit 1
fi

command -v htpasswd >/dev/null 2>&1 || {
  echo "htpasswd not found — install apache2-utils" >&2
  exit 1
}

HASH="$(htpasswd -nbBC 10 dpanel "${NEW_PASS}" | cut -d: -f2)"

python3 - "${AUTH_FILE}" "${HASH}" <<'PY'
import json
import sys

path, password_hash = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["passwordHash"] = password_hash
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f)
PY

chmod 600 "${AUTH_FILE}"
echo "[dpanel] Password updated."
