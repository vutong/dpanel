#!/usr/bin/env bash
# One-shot: convert compose.d/nuxt-*.yml → node-*.yml, stop old containers, regenerate nginx.
# No dual-read afterward — runtime code only knows node-*. Safe no-op when no nuxt-* files remain.
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"

log() { echo "[dpanel] $*" >&2; }

shopt -s nullglob
legacy_files=("${STACK_ROOT}"/compose.d/nuxt-*.yml)
shopt -u nullglob

if [[ ${#legacy_files[@]} -eq 0 ]]; then
  exit 0
fi

log "Migrating ${#legacy_files[@]} compose fragment(s) nuxt-* → node-*"
cd "${STACK_ROOT}"
# shellcheck source=/dev/null
[[ -f .env ]] && source .env

site_ops_lock_acquire

SITES_FILE="${STACK_ROOT}/data/panel/sites.json"
ensure_python3 || {
  log "WARNING: python3 required for migrate — skipping"
  site_ops_lock_release
  exit 0
}

domain_for_slug() {
  local slug="$1"
  export SITES_FILE SLUG="${slug}"
  "${PYBIN}" -c "
import json, os, re
slug = os.environ['SLUG']
path = os.environ.get('SITES_FILE', '')
if not os.path.isfile(path):
    raise SystemExit(0)
with open(path) as f:
    for s in json.load(f):
        d = (s.get('domain') or '').strip()
        if not d:
            continue
        sslug = re.sub(r'[^a-zA-Z0-9-]', '', d.replace('.', '-'))
        if sslug == slug and (s.get('runtime') or '') == 'node':
            print(d)
            break
" 2>/dev/null || true
}

project="$(_stack_project_name)"
migrated=0

for f in "${legacy_files[@]}"; do
  [[ -f "$f" ]] || continue
  slug="${f##*/nuxt-}"
  slug="${slug%.yml}"
  domain="$(domain_for_slug "${slug}")"
  old_cname="${project}-nuxt-${slug}"

  if [[ -n "${domain}" ]]; then
    log "Converting ${domain} (slug=${slug})"
    write_node_compose_fragment "${domain}"
    write_nginx_node_site "${domain}"
    migrated=$((migrated + 1))
  else
    log "WARNING: no registered node site for slug=${slug} — removing orphan ${f}"
  fi

  docker_stop_container_by_name "${old_cname}"
  rm -f "$f"
  log "Removed ${f}"
done

# Any leftover nuxt-* nginx refs on registered node sites: regenerate from registry.
if [[ -f "${SITES_FILE}" ]]; then
  export SITES_FILE
  while IFS= read -r domain; do
    [[ -n "${domain}" ]] || continue
    write_nginx_node_site "${domain}" 2>/dev/null || true
  done < <("${PYBIN}" -c "
import json, os
with open(os.environ['SITES_FILE']) as f:
    for s in json.load(f):
        if (s.get('runtime') or '') == 'node' and (s.get('domain') or '').strip():
            print(s['domain'].strip())
" 2>/dev/null || true)
fi

cd "${STACK_ROOT}"
stack_compose up -d --remove-orphans 2>/dev/null || true
nginx_reload_stack 2>/dev/null || true

site_ops_lock_release
log "Migrate nuxt→node done (converted=${migrated})"
exit 0
