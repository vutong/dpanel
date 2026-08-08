#!/usr/bin/env bash
set -euo pipefail
STACK_ROOT="${STACK_ROOT:-/opt/stack}"
cd "$STACK_ROOT"

bash "${STACK_ROOT}/infra/scripts/site-purge-expired.sh" || true

docker image prune -f
docker builder prune -f --filter "until=168h" 2>/dev/null || true
find "${STACK_ROOT}/logs" -type f -name "*.log" -mtime +30 -delete 2>/dev/null || true
echo "Cleanup complete."
