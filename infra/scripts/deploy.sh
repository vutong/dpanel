#!/usr/bin/env bash
set -euo pipefail
STACK_ROOT="${STACK_ROOT:-/opt/stack}"
cd "${STACK_ROOT}"
# shellcheck source=_helpers.sh
source "${STACK_ROOT}/infra/scripts/_helpers.sh"
stack_compose pull --ignore-pull-failures 2>/dev/null || true
stack_compose build
stack_compose up -d --remove-orphans
stack_compose ps
