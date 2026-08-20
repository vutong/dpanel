#!/usr/bin/env bash
# Fail2ban host query — one chroot session per call. Modes: summary | jails | banned
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host-chroot.sh
source "${SCRIPT_DIR}/host-chroot.sh"

MODE="${1:-summary}"
case "$MODE" in
  summary | jails | banned) ;;
  *)
    echo "{\"ok\":false,\"error\":\"Invalid mode: ${MODE}\"}" >&2
    exit 1
    ;;
esac

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || die "python3 required"

QUERY_PY="${STACK_ROOT}/infra/scripts/host-fail2ban-query.py"
[[ -f "${QUERY_PY}" ]] || die "Missing ${QUERY_PY}"

# Short command — python logic lives in .py file (avoids ARG_MAX / heredoc in host_exec).
HOST_CMD="export FAIL2BAN_QUERY_MODE='${MODE}'; python3 '${QUERY_PY}'"

OUT="$(host_exec_capture "${HOST_CMD}")" || die "${OUT:-Fail2ban host query failed}"

JSON_LINE="$(echo "${OUT}" | grep -E '^\{.*\}$' | tail -1 || true)"
if [[ -z "${JSON_LINE}" ]]; then
  die "Fail2ban query did not return JSON: ${OUT:0:400}"
fi

echo "${JSON_LINE}"
