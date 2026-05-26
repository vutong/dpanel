#!/usr/bin/env bash
# Stack health check (+ optional auto-fix).
#   dpanel health
#   sudo dpanel health --fix
#
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
FIX=0
JSON_ONLY=0
HEALTH_LOG="${HEALTH_LOG:-/var/log/dpanel-health.log}"

RECHECK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix) FIX=1; shift ;;
    --json) JSON_ONLY=1; shift ;;
    --recheck) RECHECK=1; shift ;;
    -h|--help)
      echo "Usage: dpanel health [--fix]"
      exit 0
      ;;
    *) shift ;;
  esac
done

# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh" 2>/dev/null || {
  echo '{"ok":false,"error":"helpers missing"}'
  exit 2
}

log() {
  [[ "${JSON_ONLY}" -eq 0 ]] && echo "[dpanel] $*" | tee -a "${HEALTH_LOG}" >&2 || true
}

[[ -d "${STACK_ROOT}" ]] || { echo '{"ok":false,"error":"stack not found"}'; exit 2; }
cd "${STACK_ROOT}"
# shellcheck source=/dev/null
[[ -f .env ]] && source .env

CORE_SERVICES="nginx dpanel mariadb php-fpm"
OPTIONAL_SERVICES="redis phpmyadmin"
ISSUES=0
WARNINGS=0
declare -a REPORT_LINES=()

report() {
  local id="$1" ok="$2" msg="$3" fix_hint="${4:-}" severity="${5:-critical}"
  REPORT_LINES+=("${id}|${ok}|${msg}|${fix_hint}|${severity}")
  if [[ "${ok}" -eq 0 ]]; then
    if [[ "${severity}" == "critical" ]]; then
      ISSUES=$((ISSUES + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

run_fix() {
  local cmd="$1"
  [[ "${FIX}" -eq 0 || -z "${cmd}" ]] && return 0
  log "Applying fix: ${cmd}"
  # shellcheck disable=SC2086
  eval "${cmd}" >>"${HEALTH_LOG}" 2>&1 || true
}

# --- checks ---
[[ -f "${STACK_ROOT}/.env" ]] && report "stack_env" 1 ".env present" "" \
  || report "stack_env" 0 "missing .env" "re-run install"

if command -v systemctl >/dev/null 2>&1 && ! systemctl is-active docker >/dev/null 2>&1; then
  report "docker_daemon" 0 "Docker not running" "systemctl start docker"
  run_fix "systemctl start docker"
else
  report "docker_daemon" 1 "Docker OK" ""
fi

prune_orphan_site_artifacts 2>/dev/null || true
sync_site_configs 2>/dev/null || true
fix_legacy_nginx_vhosts 2>/dev/null || true
quarantine_legacy_static_nuxt_vhosts 2>/dev/null || true

if ! stack_compose ps >/dev/null 2>&1; then
  report "compose" 0 "docker compose error" "dpanel nginx-reload"
  run_fix "bash ${STACK_ROOT}/infra/scripts/nginx-reload.sh"
else
  for svc in ${CORE_SERVICES}; do
    state="$(stack_compose ps --format '{{.Service}} {{.State}}' 2>/dev/null | awk -v s="${svc}" '$1==s {print $2; exit}')"
    if [[ "${state}" == "running" ]]; then
      report "service_${svc}" 1 "${svc} running" "" "critical"
    else
      report "service_${svc}" 0 "${svc} is ${state:-down}" "stack_compose up -d ${svc}" "critical"
      run_fix "cd ${STACK_ROOT} && source infra/scripts/_helpers.sh && stack_compose up -d ${svc}"
    fi
  done
  for svc in ${OPTIONAL_SERVICES}; do
    state="$(stack_compose ps --format '{{.Service}} {{.State}}' 2>/dev/null | awk -v s="${svc}" '$1==s {print $2; exit}')"
    if [[ "${state}" == "running" ]]; then
      report "service_${svc}" 1 "${svc} running" "" "warn"
    else
      report "service_${svc}" 0 "${svc} is ${state:-down}" "stack_compose up -d ${svc}" "warn"
      run_fix "cd ${STACK_ROOT} && source infra/scripts/_helpers.sh && stack_compose up -d ${svc}"
    fi
  done
fi

if stack_compose run --rm --no-deps nginx nginx -t >/dev/null 2>&1; then
  report "nginx_config" 1 "nginx -t OK" ""
else
  report "nginx_config" 0 "nginx config invalid" "dpanel nginx-reload"
  run_fix "bash ${STACK_ROOT}/infra/scripts/nginx-reload.sh"
fi

ports_ok=1
for p in 80 8080; do
  stack_compose port nginx "${p}" 2>/dev/null | grep -qE ':[0-9]+' || ports_ok=0
done
if [[ "${ports_ok}" -eq 1 ]]; then
  report "nginx_ports" 1 "ports 80/8080 published" ""
else
  report "nginx_ports" 0 "ports 80/8080 not bound" "dpanel nginx-reload"
  run_fix "bash ${STACK_ROOT}/infra/scripts/nginx-reload.sh"
fi

_panel_api_ok() {
  local out try
  for try in 1 2 3 4 5; do
    out="$(stack_compose exec -T dpanel wget -q -O- --timeout=8 http://127.0.0.1:3000/api/health 2>/dev/null || true)"
    if printf '%s' "${out}" | grep -qE '"ok"[[:space:]]*:[[:space:]]*true'; then
      return 0
    fi
    [[ "${try}" -lt 5 ]] && sleep 3
  done
  return 1
}
if _panel_api_ok; then
  report "panel_api" 1 "panel API OK" "" "critical"
else
  report "panel_api" 0 "panel API down (still starting?)" "stack_compose restart dpanel" "critical"
  run_fix "cd ${STACK_ROOT} && source infra/scripts/_helpers.sh && stack_compose restart dpanel"
fi

if stack_compose exec -T mariadb healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1; then
  report "mariadb" 1 "MariaDB OK" ""
else
  report "mariadb" 0 "MariaDB not ready" "stack_compose restart mariadb"
  run_fix "cd ${STACK_ROOT} && source infra/scripts/_helpers.sh && stack_compose restart mariadb"
fi

if stack_compose exec -T dpanel sh -c 'command -v python3 >/dev/null' 2>/dev/null; then
  report "python3" 1 "python3 in panel container" ""
else
  report "python3" 0 "python3 missing in panel" "stack_compose exec dpanel apk add --no-cache python3"
  run_fix "cd ${STACK_ROOT} && source infra/scripts/_helpers.sh && stack_compose exec dpanel apk add --no-cache python3"
fi

disk_mb="$(df -BM "${STACK_ROOT}" 2>/dev/null | awk 'NR==2 {gsub(/M/,"",$4); print $4}' || echo 0)"
if [[ "${disk_mb}" -gt 512 ]] 2>/dev/null; then
  report "disk" 1 "disk free ${disk_mb}MB" "" "warn"
else
  report "disk" 0 "low disk space" "" "warn"
fi

VERSION="unknown"
if [[ -f "${STACK_ROOT}/data/panel/version.json" ]] && command -v python3 >/dev/null 2>&1; then
  VERSION="$(python3 -c "import json;print(json.load(open('${STACK_ROOT}/data/panel/version.json')).get('version','unknown'))" 2>/dev/null || echo unknown)"
elif grep -q '^DPANEL_VERSION=' "${STACK_ROOT}/.env" 2>/dev/null; then
  VERSION="$(grep '^DPANEL_VERSION=' "${STACK_ROOT}/.env" | cut -d= -f2-)"
fi

# After fixes, re-run once (keep human-readable logs for update)
if [[ "${FIX}" -eq 1 && "${ISSUES}" -gt 0 && "${RECHECK}" -eq 0 ]]; then
  log "Waiting for services after fixes..."
  sleep 10
  exec bash "${BASH_SOURCE[0]}" --recheck
fi

OK=true
[[ "${ISSUES}" -gt 0 ]] && OK=false

# Build JSON
JSON_FILE="$(mktemp)"
{
  echo -n '{"ok":'; [[ "${ISSUES}" -eq 0 ]] && echo -n 'true' || echo -n 'false'
  echo -n ',"service":"dpanel","version":"'${VERSION}'","issues":'${ISSUES}',"warnings":'${WARNINGS}',"checks":['
  local first=1
  for line in "${REPORT_LINES[@]}"; do
    IFS='|' read -r id ok msg fix_hint _severity <<< "${line}"
    [[ "${first}" -eq 0 ]] && echo -n ','
    first=0
    okj=$([[ "${ok}" -eq 1 ]] && echo true || echo false)
    msg="${msg//\\/\\\\}"; msg="${msg//\"/\\\"}"
    fix_hint="${fix_hint//\\/\\\\}"; fix_hint="${fix_hint//\"/\\\"}"
    echo -n "{\"id\":\"${id}\",\"ok\":${okj},\"message\":\"${msg}\",\"fix\":\"${fix_hint}\"}"
  done
  echo ']}'
} > "${JSON_FILE}"

if [[ "${JSON_ONLY}" -eq 0 ]]; then
  if [[ "${ISSUES}" -eq 0 ]]; then
    [[ "${WARNINGS}" -gt 0 ]] && log "Health OK (with ${WARNINGS} warning(s)) — version ${VERSION}" \
      || log "Health OK — version ${VERSION}"
  else
    log "Health: ${ISSUES} critical issue(s) — version ${VERSION}"
    for line in "${REPORT_LINES[@]}"; do
      IFS='|' read -r id ok msg fix_hint severity <<< "${line}"
      [[ "${ok}" -eq 0 ]] && [[ "${severity:-critical}" == "critical" ]] && {
        log "  [FAIL] ${id}: ${msg}"
        [[ -n "${fix_hint}" ]] && log "         → ${fix_hint}"
      }
    done
    for line in "${REPORT_LINES[@]}"; do
      IFS='|' read -r id ok msg fix_hint severity <<< "${line}"
      [[ "${ok}" -eq 0 ]] && [[ "${severity}" == "warn" ]] && log "  [WARN] ${id}: ${msg}"
    done
    log "Try: sudo dpanel health --fix"
  fi
fi

cat "${JSON_FILE}"
rm -f "${JSON_FILE}"

exit $([[ "${ISSUES}" -eq 0 ]] && echo 0 || echo 1)
