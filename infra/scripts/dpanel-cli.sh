#!/usr/bin/env bash
# dpanel command-line helper (symlinked to /usr/local/bin/dpanel after install).
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
CMD="${1:-help}"

cd "${STACK_ROOT}" 2>/dev/null || { echo "Stack not found at ${STACK_ROOT}" >&2; exit 1; }

case "${CMD}" in
  status)
    docker compose ps
    ;;
  logs)
    docker compose logs -f "${2:-dpanel}" --tail "${3:-100}"
    ;;
  restart)
    docker compose restart "${2:-}"
    ;;
  update)
    if [[ ! -f "${STACK_ROOT}/infra/scripts/update.sh" ]]; then
      echo "Fetching update.sh..." >&2
      install -d "${STACK_ROOT}/infra/scripts"
      curl -fsSL "${DPANEL_RAW_URL:-https://raw.githubusercontent.com/vutong/dpanel/main}/infra/scripts/update.sh" \
        -o "${STACK_ROOT}/infra/scripts/update.sh"
      chmod +x "${STACK_ROOT}/infra/scripts/update.sh"
    fi
    exec bash "${STACK_ROOT}/infra/scripts/update.sh" "${@:2}"
    ;;
  update-check|update-check-only)
    if [[ ! -f "${STACK_ROOT}/infra/scripts/update.sh" ]]; then
      install -d "${STACK_ROOT}/infra/scripts"
      curl -fsSL "${DPANEL_RAW_URL:-https://raw.githubusercontent.com/vutong/dpanel/main}/infra/scripts/update.sh" \
        -o "${STACK_ROOT}/infra/scripts/update.sh"
      chmod +x "${STACK_ROOT}/infra/scripts/update.sh"
    fi
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
  health)
    docker compose exec -T dpanel wget -q -O- http://127.0.0.1:3000/api/health 2>/dev/null \
      || curl -fsS "http://127.0.0.1:3000/api/health" 2>/dev/null \
      || echo "Panel health check failed — run: dpanel logs dpanel"
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
      echo "Version unknown — run: dpanel update"
    fi
    ;;
  help|*)
    cat <<'EOF'
dpanel — stack management

  dpanel status              Docker services status
  dpanel health              Panel API health check
  dpanel logs [svc] [lines]  Follow logs (default: dpanel)
  dpanel restart [svc]       Restart service(s)
  dpanel update [--check]    Pull latest stack from GitHub & restart
  dpanel update-check        Show installed vs latest version
  dpanel update-panel        Rebuild panel UI only (no git pull)
  dpanel version             Show installed version
  dpanel deploy              docker compose build & up
  dpanel credentials         Show install summary (if saved)
  dpanel setpass <password>  Change panel login password

Stack root: /opt/stack
EOF
    ;;
esac
