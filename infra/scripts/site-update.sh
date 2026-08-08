#!/usr/bin/env bash
# Usage: site-update.sh <domain>
# Private repo: GITHUB_TOKEN in env (not saved on server)
# GIT_DISCARD_LOCAL=1 — git restore . before pull (panel: Checkout checkbox)
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"
# shellcheck source=_github.sh
source "${STACK_ROOT}/infra/scripts/_github.sh"

DOMAIN="${1:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
OP_FINALIZED=0

die() {
  OP_FINALIZED=1
  site_op_status_write "${DOMAIN}" "update" "error" "$*" 2>/dev/null || true
  echo "{\"ok\":false,\"error\":\"$*\"}" >&2
  exit 1
}

on_exit() {
  if [[ "${OP_FINALIZED}" -eq 0 && -n "${DOMAIN}" ]]; then
    site_op_status_write "${DOMAIN}" "update" "error" \
      "Update interrupted unexpectedly — retry Update from Git" 2>/dev/null || true
  fi
}

trap on_exit EXIT

[[ -n "${DOMAIN}" ]] || die "Missing domain"
[[ "${DOMAIN}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || die "Invalid domain"

ensure_python3 || die "python3 required — run: sudo dpanel update"

SLUG="$(site_slug "${DOMAIN}")"
LOG="${STACK_ROOT}/logs/node/site-update-${SLUG}.log"

mkdir -p "${STACK_ROOT}/logs/node"
: >>"${LOG}"
exec >>"${LOG}" 2>&1
echo "[dpanel] $(date '+%Y-%m-%d %H:%M:%S') site-update ${DOMAIN}"

site_op_status_write "${DOMAIN}" "update" "running" "Pulling from Git…"

SITES_FILE="${STACK_ROOT}/data/panel/sites.json"
APP_DIR="${STACK_ROOT}/apps/${DOMAIN}"

export SITES_FILE DOMAIN
read -r GITHUB_URL RUNTIME < <("${PYBIN}" -c "
import json, os, sys
path = os.environ['SITES_FILE']
domain = os.environ['DOMAIN']
if not os.path.isfile(path):
    sys.exit(1)
with open(path) as f:
    for s in json.load(f):
        if s.get('domain') == domain:
            print((s.get('githubUrl') or '').strip())
            print(s.get('runtime') or '')
            sys.exit(0)
sys.exit(1)
" 2>/dev/null) || die "Site not found in sites.json"

[[ -n "${GITHUB_URL}" ]] || die "No GitHub URL for this site — add repository when creating the site"

mkdir -p "${APP_DIR}"

gh_err="$(mktemp)"
if ! github_preflight 2>"${gh_err}"; then
  die "$(tr -d '\r' < "${gh_err}" | head -5 | tr '\n' ' ')"
fi
rm -f "${gh_err}"

if [[ -d "${APP_DIR}/.git" ]]; then
  if [[ "${GIT_DISCARD_LOCAL:-}" == "1" ]]; then
    echo "[dpanel] git restore . (discard local changes before pull)"
    (
      cd "${APP_DIR}"
      git restore . 2>/dev/null || git checkout -- . 2>/dev/null || true
    )
  fi
  if ! github_pull_into "${APP_DIR}"; then
    die "git pull failed — if the repo is private, provide a valid GitHub token"
  fi
else
  if ! github_clone_into "${APP_DIR}" "${GITHUB_URL}"; then
    die "git clone failed — check token (expired PAT is common) or repository URL"
  fi
fi

OP_FINALIZED=1
site_op_status_write "${DOMAIN}" "update" "ok" "Pull complete"
trap - EXIT

echo "{\"ok\":true,\"domain\":\"${DOMAIN}\",\"runtime\":\"${RUNTIME}\",\"action\":\"update\"}"
