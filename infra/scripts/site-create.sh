#!/usr/bin/env bash
# Usage: site-create.sh <domain> <node|php> [github_url]
# Private repo: set GITHUB_TOKEN in env (not argv — avoids leaking in logs)
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh" 2>/dev/null || true
# shellcheck source=_github.sh
source "${STACK_ROOT}/infra/scripts/_github.sh" 2>/dev/null || true

DOMAIN="${1:-}"
RUNTIME="${2:-}"
GITHUB_URL="${3:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-${4:-}}"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

[[ -n "$DOMAIN" && -n "$RUNTIME" ]] || die "Missing domain or runtime"
[[ "$RUNTIME" == "node" || "$RUNTIME" == "php" ]] || die "Runtime must be node or php"
[[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || die "Invalid domain"

SITES_FILE="${STACK_ROOT}/data/panel/sites.json"
APP_DIR="${STACK_ROOT}/apps/${DOMAIN}"
SLUG="$(site_slug "${DOMAIN}")"
NODE_SVC=""
mkdir -p "$APP_DIR"

if [[ -n "$GITHUB_URL" ]]; then
  [[ -f "${STACK_ROOT}/infra/scripts/_github.sh" ]] \
    || die "Missing infra/scripts/_github.sh — run: sudo dpanel update"
  export GITHUB_TOKEN
  gh_err="$(mktemp)"
  if ! github_preflight 2>"${gh_err}"; then
    die "$(tr -d '\r' < "${gh_err}" | head -5 | tr '\n' ' ')"
  fi
  rm -f "${gh_err}"
  if ! github_clone_into "${APP_DIR}" "${GITHUB_URL}"; then
    die "git clone failed — token may be expired; use a new PAT (ghp_) with repo scope"
  fi
else
  echo "Deploy application code to ${DOMAIN}" > "${APP_DIR}/.gitkeep"
fi

if [[ "$RUNTIME" == "node" ]]; then
  write_node_compose_fragment "${DOMAIN}"
  write_nginx_node_site "${DOMAIN}"
  NODE_SVC="node-${SLUG}"
else
  write_nginx_php_site "${DOMAIN}"
fi

ensure_python3 || die "python3 required — run: sudo apt-get install -y python3"
export SITES_FILE DOMAIN RUNTIME GITHUB_URL
"${PYBIN}" <<'PY'
import json, os
from datetime import datetime, timezone
path = os.environ["SITES_FILE"]
domain = os.environ["DOMAIN"]
runtime = os.environ["RUNTIME"]
github = os.environ.get("GITHUB_URL", "")

sites = []
if os.path.isfile(path):
    with open(path) as f:
        sites = json.load(f)

sites = [s for s in sites if s.get("domain") != domain]
sites.append({
    "domain": domain,
    "runtime": runtime,
    "githubUrl": github or None,
    "createdAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
})

with open(path, "w") as f:
    json.dump(sites, f, indent=2)
PY

# JSON first — panel API must respond before async Docker work (full nginx-reload restarts dpanel → 502).
echo "{\"ok\":true,\"domain\":\"${DOMAIN}\",\"runtime\":\"${RUNTIME}\"}"

site_finalize_async "site-create-${SLUG}" "${NODE_SVC}"
echo "[dpanel] Site ${DOMAIN} registered — nginx/Node apply in background (see logs/node/site-create-${SLUG}.log)" >&2
