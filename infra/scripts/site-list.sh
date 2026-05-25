#!/usr/bin/env bash
set -euo pipefail
STACK_ROOT="${STACK_ROOT:-/opt/stack}"
SITES_FILE="${STACK_ROOT}/data/panel/sites.json"
[[ -f "$SITES_FILE" ]] || echo '[]'
[[ -f "$SITES_FILE" ]] && cat "$SITES_FILE"
