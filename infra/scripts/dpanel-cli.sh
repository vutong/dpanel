#!/usr/bin/env bash
# dpanel command-line helper (symlinked to /usr/local/bin/dpanel after install).
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
CMD="${1:-help}"

cd "${STACK_ROOT}" 2>/dev/null || { echo "[dpanel] Stack not found at ${STACK_ROOT}" >&2; exit 1; }

# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh" 2>/dev/null || true

show_help() {
  local ver="unknown"
  if [[ -f "${STACK_ROOT}/data/panel/version.json" ]]; then
    ver="$(python3 -c "import json; print(json.load(open('${STACK_ROOT}/data/panel/version.json')).get('version',''))" 2>/dev/null || true)"
  fi
  if [[ -z "${ver}" || "${ver}" == "unknown" ]]; then
    ver="$(grep -E '^DPANEL_VERSION=' "${STACK_ROOT}/.env" 2>/dev/null | cut -d= -f2- || echo unknown)"
  fi

  cat <<EOF
dpanel — Docker hosting control panel CLI
Stack: ${STACK_ROOT}   Version: ${ver}

Usage: dpanel <command> [options]

System
  help, -h, --help           Show this help
  version                    Installed version (JSON)
  status                     Docker Compose service status
  health [--fix]             Full stack health (services, nginx, DB, ports)
  credentials, cred          Install summary (CREDENTIALS.txt)

Update
  update [--check] [--no-build] [--no-health-fix] [--no-nginx-reload]
                             One command: sync, rebuild, health --fix, nginx-reload
  update-check               Compare installed vs latest version
  update-panel               Rebuild panel UI only (no git pull)
  deploy                     docker compose build && up -d

Services
  logs [service] [lines]     Follow logs (default: dpanel, 100 lines)
  restart [service]        Restart one or all services

Websites
  site-remove <domain> [--purge]
                             Remove site (nginx, compose.d, container; --purge deletes app files)

Security
  setpass <password>         Change panel login password

Examples
  dpanel status
  dpanel update-check
  sudo dpanel update
  dpanel setpass 'NewSecurePass'
  dpanel logs nginx 200

Logs: /var/log/dpanel-install.log  /var/log/dpanel-update.log
EOF
}

ensure_update_script() {
  if [[ -f "${STACK_ROOT}/infra/scripts/update.sh" ]]; then
    return 0
  fi
  echo "[dpanel] Fetching update.sh..." >&2
  install -d "${STACK_ROOT}/infra/scripts"
  curl -fsSL "${DPANEL_RAW_URL:-https://raw.githubusercontent.com/vutong/dpanel/main}/infra/scripts/update.sh" \
    -o "${STACK_ROOT}/infra/scripts/update.sh"
  chmod +x "${STACK_ROOT}/infra/scripts/update.sh"
}

case "${CMD}" in
  help|-h|--help)
    show_help
    ;;
  status)
    stack_compose ps
    ;;
  logs)
    stack_compose logs -f "${2:-dpanel}" --tail "${3:-100}"
    ;;
  restart)
    stack_compose restart "${2:-}"
    ;;
  nginx-reload|fix-nginx)
    exec bash "${STACK_ROOT}/infra/scripts/nginx-reload.sh"
    ;;
  update)
    ensure_update_script
    exec bash "${STACK_ROOT}/infra/scripts/update.sh" "${@:2}"
    ;;
  update-check|update-check-only)
    ensure_update_script
    exec bash "${STACK_ROOT}/infra/scripts/update.sh" --check
    ;;
  update-panel)
    exec bash "${STACK_ROOT}/infra/scripts/update-panel.sh"
    ;;
  deploy)
    exec bash "${STACK_ROOT}/infra/scripts/deploy.sh"
    ;;
  credentials|cred)
    if [[ -f "${STACK_ROOT}/CREDENTIALS.txt" ]]; then
      cat "${STACK_ROOT}/CREDENTIALS.txt"
    else
      echo "No CREDENTIALS.txt — see ${STACK_ROOT}/.env"
    fi
    ;;
  health|doctor)
    hc="${STACK_ROOT}/infra/scripts/health-check.sh"
    if [[ ! -f "${hc}" ]]; then
      curl -fsSL "${DPANEL_RAW_URL:-https://raw.githubusercontent.com/vutong/dpanel/main}/infra/scripts/health-check.sh" \
        -o "${hc}"
      chmod +x "${hc}"
    fi
    exec bash "${hc}" "${@:2}"
    ;;
  site-remove|site-delete)
    exec bash "${STACK_ROOT}/infra/scripts/site-delete.sh" "${@:2}"
    ;;
  setpass)
    exec bash "${STACK_ROOT}/infra/scripts/setpass.sh" "${2:-}"
    ;;
  version)
    if [[ -f "${STACK_ROOT}/data/panel/version.json" ]]; then
      cat "${STACK_ROOT}/data/panel/version.json"
    elif grep -E '^DPANEL_VERSION=' "${STACK_ROOT}/.env" 2>/dev/null; then
      grep -E '^DPANEL_VERSION=' "${STACK_ROOT}/.env"
    else
      echo '{"version":"unknown"}'
      echo "Run: sudo dpanel update" >&2
    fi
    ;;
  *)
    echo "[dpanel] Unknown command: ${CMD}" >&2
    echo "Run: dpanel help" >&2
    exit 1
    ;;
esac
