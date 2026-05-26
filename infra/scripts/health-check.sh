#!/usr/bin/env bash
# Stack health check (+ optional auto-fix).
#   dpanel health
#   sudo dpanel health --fix
#   (from update) DPANEL_HEALTH_FROM_UPDATE=1 health-check.sh --fix --from-update
#
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
FIX=0
JSON_ONLY=0
HEALTH_LOG="${HEALTH_LOG:-/var/log/dpanel-health.log}"
RECHECK=0
FROM_UPDATE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix) FIX=1; shift ;;
    --json) JSON_ONLY=1; shift ;;
    --recheck) RECHECK=1; shift ;;
    --from-update) FROM_UPDATE=1; shift ;;
    -h|--help)
      echo "Usage: dpanel health [--fix]"
      exit 0
      ;;
    *) shift ;;
  esac
done

[[ "${DPANEL_HEALTH_FROM_UPDATE:-}" == 1 ]] && FROM_UPDATE=1

# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh" 2>/dev/null || {
  echo '{"ok":false,"error":"helpers missing"}'
  exit 2
}

log() {
  [[ "${JSON_ONLY}" -eq 0 ]] && echo "[dpanel] $*" | tee -a "${HEALTH_LOG}" >&2 || true
}

step() { log "$1"; }

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
  eval "${cmd}" 2>&1 | tee -a "${HEALTH_LOG}" >&2 || true
}

check_core_services() {
  if ! stack_compose ps >/dev/null 2>&1; then
    report "compose" 0 "docker compose error" "dpanel nginx-reload"
    run_fix "bash ${STACK_ROOT}/infra/scripts/nginx-reload.sh"
    return
  fi
  local svc state
  for svc in ${CORE_SERVICES}; do
    state="$(stack_compose ps --format '{{.Service}} {{.State}}' 2>/dev/null | awk -v s="${svc}" '$1==s {print $2; exit}')"
    if [[ "${state}" == "running" ]]; then
      report "service_${svc}" 1 "${svc} running" "" "critical"
    else
      report "service_${svc}" 0 "${svc} is ${state:-down}" "stack_compose up -d ${svc}" "critical"
      run_fix "cd ${STACK_ROOT} && source infra/scripts/_helpers.sh && stack_compose up -d ${svc}"
    fi
  done
}

check_disk_space() {
  local disk_mb
  disk_mb="$(df -BM "${STACK_ROOT}" 2>/dev/null | awk 'NR==2 {gsub(/M/,"",$4); print $4}' || echo 0)"
  if [[ "${disk_mb}" -gt 512 ]] 2>/dev/null; then
    report "disk" 1 "disk free ${disk_mb}MB" "" "warn"
  else
    report "disk" 0 "low disk space (${disk_mb}MB free)" "" "warn"
  fi
}

check_panel_tools() {
  if stack_compose exec -T dpanel sh -c 'command -v python3 >/dev/null' 2>/dev/null; then
    report "python3" 1 "python3 in panel container" ""
  else
    report "python3" 0 "python3 missing in panel" "stack_compose exec dpanel apk add --no-cache python3"
    run_fix "cd ${STACK_ROOT} && source infra/scripts/_helpers.sh && stack_compose exec dpanel apk add --no-cache python3"
  fi
  check_disk_space
}

check_optional_services() {
  local svc state
  for svc in ${OPTIONAL_SERVICES}; do
    state="$(stack_compose ps --format '{{.Service}} {{.State}}' 2>/dev/null | awk -v s="${svc}" '$1==s {print $2; exit}')"
    if [[ "${state}" == "running" ]]; then
      report "service_${svc}" 1 "${svc} running" "" "warn"
    else
      report "service_${svc}" 0 "${svc} is ${state:-down}" "stack_compose up -d ${svc}" "warn"
      run_fix "cd ${STACK_ROOT} && source infra/scripts/_helpers.sh && stack_compose up -d ${svc}"
    fi
  done
}

check_panel_api() {
  local wait_sec="${1:-30}"
  step "Checking panel API (wait up to ${wait_sec}s)..."
  if wait_for_dpanel_ready "${wait_sec}"; then
    report "panel_api" 1 "panel API OK (/api/ping)" "" "critical"
    return
  fi
  report "panel_api" 0 "panel API not ready on /api/ping" "stack_compose restart dpanel" "critical"
  run_fix "cd ${STACK_ROOT} && source infra/scripts/_helpers.sh && stack_compose restart dpanel && sleep 5"
}

check_nginx() {
  step "Checking nginx..."
  if nginx_test_stack 1; then
    report "nginx_config" 1 "nginx -t OK" ""
  else
    report "nginx_config" 0 "nginx config invalid" "dpanel nginx-reload"
    run_fix "bash ${STACK_ROOT}/infra/scripts/nginx-reload.sh"
  fi
  local p ports_ok=1
  for p in 80 8080; do
    stack_compose port nginx "${p}" 2>/dev/null | grep -qE ':[0-9]+' || ports_ok=0
  done
  if [[ "${ports_ok}" -eq 1 ]]; then
    report "nginx_ports" 1 "ports 80/8080 published" ""
  else
    report "nginx_ports" 0 "ports 80/8080 not bound" "dpanel nginx-reload"
    run_fix "bash ${STACK_ROOT}/infra/scripts/nginx-reload.sh"
  fi
}

# --- Fast re-check after --fix (no site sync, no nginx -t) ---
if [[ "${RECHECK}" -eq 1 ]]; then
  step "Re-checking critical services..."
  check_core_services
  check_panel_api 60
  step "Checking MariaDB..."
  if stack_compose exec -T mariadb healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1; then
    report "mariadb" 1 "MariaDB OK" ""
  else
    report "mariadb" 0 "MariaDB not ready" "stack_compose restart mariadb"
  fi
else
  [[ "${FIX}" -eq 1 ]] && step "Health check (auto-fix enabled)..."
  [[ "${FROM_UPDATE}" -eq 1 ]] && step "Health check (update — site/nginx handled by nginx-reload next)"

  step "Checking stack environment..."
  [[ -f "${STACK_ROOT}/.env" ]] && report "stack_env" 1 ".env present" "" \
    || report "stack_env" 0 "missing .env" "re-run install"

  if command -v systemctl >/dev/null 2>&1 && ! systemctl is-active docker >/dev/null 2>&1; then
    report "docker_daemon" 0 "Docker not running" "systemctl start docker"
    run_fix "systemctl start docker"
  else
    report "docker_daemon" 1 "Docker OK" ""
  fi

  if [[ "${FROM_UPDATE}" -eq 0 ]]; then
    step "Syncing site configs..."
    prune_orphan_site_artifacts 2>/dev/null || true
    sync_site_configs 2>/dev/null || true
    fix_legacy_nginx_vhosts 2>/dev/null || true
    quarantine_legacy_static_nuxt_vhosts 2>/dev/null || true
  fi

  step "Checking Docker services..."
  check_core_services
  check_optional_services

  if [[ "${FROM_UPDATE}" -eq 0 ]]; then
    check_nginx
  else
    log "Skipping nginx -t here (dpanel nginx-reload runs after this)"
  fi

  if [[ "${FROM_UPDATE}" -eq 1 ]]; then
    check_panel_api 90
  else
    check_panel_api 30
  fi

  step "Checking MariaDB..."
  if stack_compose exec -T mariadb healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1; then
    report "mariadb" 1 "MariaDB OK" ""
  else
    report "mariadb" 0 "MariaDB not ready" "stack_compose restart mariadb"
    run_fix "cd ${STACK_ROOT} && source infra/scripts/_helpers.sh && stack_compose restart mariadb"
  fi

  if [[ "${FROM_UPDATE}" -eq 0 ]]; then
    step "Checking panel tools..."
    check_panel_tools
  fi
fi

VERSION="unknown"
if [[ -f "${STACK_ROOT}/data/panel/version.json" ]] && command -v python3 >/dev/null 2>&1; then
  VERSION="$(python3 -c "import json;print(json.load(open('${STACK_ROOT}/data/panel/version.json')).get('version','unknown'))" 2>/dev/null || echo unknown)"
elif grep -q '^DPANEL_VERSION=' "${STACK_ROOT}/.env" 2>/dev/null; then
  VERSION="$(grep '^DPANEL_VERSION=' "${STACK_ROOT}/.env" | cut -d= -f2-)"
fi

if [[ "${FIX}" -eq 1 && "${ISSUES}" -gt 0 && "${RECHECK}" -eq 0 ]]; then
  log "Waiting 10s after fixes, then re-check..."
  sleep 10
  export DPANEL_HEALTH_FROM_UPDATE="${DPANEL_HEALTH_FROM_UPDATE:-}"
  exec bash "${BASH_SOURCE[0]}" --recheck ${FROM_UPDATE:+--from-update}
fi

JSON_FILE="$(mktemp)"
first=1
{
  echo -n '{"ok":'; [[ "${ISSUES}" -eq 0 ]] && echo -n 'true' || echo -n 'false'
  echo -n ',"service":"dpanel","version":"'${VERSION}'","issues":'${ISSUES}',"warnings":'${WARNINGS}',"checks":['
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
    [[ "${FIX}" -eq 0 ]] && log "Try: sudo dpanel health --fix"
  fi
else
  cat "${JSON_FILE}"
fi

rm -f "${JSON_FILE}"

exit $([[ "${ISSUES}" -eq 0 ]] && echo 0 || echo 1)
