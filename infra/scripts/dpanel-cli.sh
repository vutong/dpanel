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
  update|update-panel)
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
  help|*)
    cat <<'EOF'
dpanel — stack management

  dpanel status              Docker services status
  dpanel health              Panel API health check
  dpanel logs [svc] [lines]  Follow logs (default: dpanel)
  dpanel restart [svc]       Restart service(s)
  dpanel update-panel        Rebuild & restart panel UI
  dpanel deploy              docker compose build & up
  dpanel credentials         Show install summary (if saved)
  dpanel setpass <password>  Change panel login password

Stack root: /opt/stack
EOF
    ;;
esac
