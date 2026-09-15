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
OP_FINALIZED=0

die() {
  OP_FINALIZED=1
  if [[ -n "${GITHUB_URL}" && -n "${DOMAIN}" ]]; then
    site_op_status_write "${DOMAIN}" "create" "error" "$*" 2>/dev/null || true
  fi
  echo "{\"ok\":false,\"error\":\"$*\"}" >&2
  exit 1
}

on_exit() {
  if [[ "${OP_FINALIZED}" -eq 0 && -n "${DOMAIN}" && -n "${GITHUB_URL}" ]]; then
    site_op_status_write "${DOMAIN}" "create" "error" \
      "Create interrupted unexpectedly — check Websites or retry" 2>/dev/null || true
  fi
}

[[ -n "$DOMAIN" && -n "$RUNTIME" ]] || die "Missing domain or runtime"
[[ "$RUNTIME" == "node" || "$RUNTIME" == "php" ]] || die "Runtime must be node or php"
[[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || die "Invalid domain"

SITES_FILE="${STACK_ROOT}/data/panel/sites.json"
APP_DIR="${STACK_ROOT}/apps/${DOMAIN}"
SLUG="$(site_slug "${DOMAIN}")"
NODE_SVC=""
LOG="${STACK_ROOT}/logs/node/site-create-${SLUG}.log"

if [[ -n "$GITHUB_URL" ]]; then
  trap on_exit EXIT
  mkdir -p "${STACK_ROOT}/logs/node"
  : >"${LOG}"
  exec >>"${LOG}" 2>&1
  echo "[dpanel] $(date '+%Y-%m-%d %H:%M:%S') site-create ${DOMAIN} (${RUNTIME})"
  site_op_status_write "${DOMAIN}" "create" "running" "Cloning from GitHub…"
fi

if [[ -n "$GITHUB_URL" ]]; then
  [[ -f "${STACK_ROOT}/infra/scripts/_github.sh" ]] \
    || die "Missing infra/scripts/_github.sh — run: sudo dpanel update"
  export GITHUB_TOKEN GITHUB_URL
  site_op_status_write "${DOMAIN}" "create" "running" "Checking GitHub access…"
  gh_err="$(mktemp)"
  if ! github_preflight 2>"${gh_err}"; then
    die "$(tr -d '\r' < "${gh_err}" | head -5 | tr '\n' ' ')"
  fi
  rm -f "${gh_err}"
  site_op_status_write "${DOMAIN}" "create" "running" "Cloning repository…"
  if ! github_clone_into "${APP_DIR}" "${GITHUB_URL}"; then
    if grep -qiE 'no space left|unable to write new index file|checkout failed|disk may be full' "${LOG}" 2>/dev/null; then
      die "Git checkout failed — disk may be full under apps/. Check Dashboard disk usage, free space, then retry Create."
    fi
    die "git clone failed — see create log above (token, disk space, or repo URL)"
  fi
  if [[ "$RUNTIME" == "php" ]]; then
    site_op_status_write "${DOMAIN}" "create" "running" "Fixing permissions…"
    github_log "Fixing PHP file ownership (www-data)…"
    if ! site_fix_permissions "${DOMAIN}" "quick"; then
      github_log "WARNING: permission fix after clone had errors — use Fix permissions in Deploy & code"
    else
      github_log "Permissions OK"
    fi
  fi
else
  mkdir -p "$APP_DIR"
  echo "Deploy application code to ${DOMAIN}" > "${APP_DIR}/.gitkeep"
fi

if [[ -n "$GITHUB_URL" ]]; then
  site_op_status_write "${DOMAIN}" "create" "running" "Configuring site…"
  github_log "Writing nginx vhost for ${RUNTIME}…"
fi

if [[ "$RUNTIME" == "node" ]]; then
  write_node_compose_fragment "${DOMAIN}"
  write_nginx_node_site "${DOMAIN}"
  NODE_SVC="node-${SLUG}"
else
  write_nginx_php_site "${DOMAIN}"
fi

if [[ -n "$GITHUB_URL" ]]; then
  github_log "Nginx config written"
  github_log "Registering site in panel (sites.json)…"
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

if [[ -n "$GITHUB_URL" ]]; then
  github_log "Site registered in panel"
  site_op_status_write "${DOMAIN}" "create" "running" "Applying nginx & services…"
  OP_FINALIZED=1
  site_op_status_write "${DOMAIN}" "create" "ok" "Website created"
  trap - EXIT
fi

# JSON first — panel API must respond before async Docker work (full nginx-reload restarts dpanel → 502).
echo "{\"ok\":true,\"domain\":\"${DOMAIN}\",\"runtime\":\"${RUNTIME}\"}"

site_finalize_async "site-create-${SLUG}" "${NODE_SVC}"
if [[ -n "$GITHUB_URL" ]]; then
  github_log "Queued nginx reload / Node service start in background"
else
  echo "[dpanel] Site ${DOMAIN} registered — nginx/Node apply in background (see logs/node/site-create-${SLUG}.log)" >&2
fi
