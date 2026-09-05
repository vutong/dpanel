#!/usr/bin/env bash
# Build JSON payload for cache/site-resources/{slug}.json (config + app dir size).
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
DOMAIN="${1:-}"
[[ -n "$DOMAIN" ]] || exit 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_helpers.sh
source "${SCRIPT_DIR}/_helpers.sh"

ensure_python3 >/dev/null 2>&1 || die "python3 required"

SLUG="$(site_slug "$DOMAIN")"
APP_DIR="${STACK_ROOT}/apps/${DOMAIN}"
CFG_PATH="${STACK_ROOT}/data/panel/site-resources/${SLUG}.json"

export DOMAIN SLUG CFG_PATH APP_DIR
"${PYBIN}" <<'PY'
import json, os, subprocess

domain = os.environ["DOMAIN"]
slug = os.environ["SLUG"]
cfg_path = os.environ["CFG_PATH"]
app_dir = os.environ["APP_DIR"]

def parse_limit(raw, mx):
    try:
        n = float(raw)
    except (TypeError, ValueError):
        return 0
    if n < 0 or n != n:
        return 0
    return min(mx, round(n * 100) / 100)

cfg = {"cpuLimit": 0, "memoryMb": 0, "diskGb": 0}
if os.path.isfile(cfg_path):
    try:
        with open(cfg_path, encoding="utf-8") as f:
            raw = json.load(f)
        cfg = {
            "cpuLimit": parse_limit(raw.get("cpuLimit"), 64),
            "memoryMb": int(parse_limit(raw.get("memoryMb"), 1024 * 1024)),
            "diskGb": int(parse_limit(raw.get("diskGb"), 10000)),
        }
    except (OSError, json.JSONDecodeError, TypeError):
        pass

app_bytes = None
if os.path.isdir(app_dir):
    try:
        out = subprocess.check_output(["du", "-sb", app_dir], text=True, timeout=120, stderr=subprocess.DEVNULL)
        n = int(out.split()[0])
        app_bytes = n if n >= 0 else None
    except (subprocess.CalledProcessError, ValueError, subprocess.TimeoutExpired, OSError):
        app_bytes = None

print(json.dumps({"domain": domain, "slug": slug, "config": cfg, "appDirBytes": app_bytes}))
PY
