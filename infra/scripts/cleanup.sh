#!/usr/bin/env bash
set -euo pipefail
cd /opt/stack
docker image prune -f
docker builder prune -f --filter "until=168h" 2>/dev/null || true
find /opt/stack/logs -type f -name "*.log" -mtime +30 -delete 2>/dev/null || true
echo "Cleanup xong."
