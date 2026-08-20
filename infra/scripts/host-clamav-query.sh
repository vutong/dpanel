#!/usr/bin/env bash
# ClamAV host query — one chroot session per call. Modes: summary | detail
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host-chroot.sh
source "${SCRIPT_DIR}/host-chroot.sh"

MODE="${1:-summary}"
case "$MODE" in
  summary | detail) ;;
  *)
    echo "{\"ok\":false,\"error\":\"Invalid mode: ${MODE}\"}"
    exit 1
    ;;
esac

die() {
  python3 -c 'import json,sys; print(json.dumps({"ok":False,"error":sys.argv[1]}))' "$*" 2>/dev/null \
    || echo "{\"ok\":false,\"error\":\"query failed\"}"
  exit 1
}

command -v python3 >/dev/null 2>&1 || die "python3 required"

QUERY_PY="${SCRIPT_DIR}/host-clamav-query.py"
[[ -f "${QUERY_PY}" ]] || die "Missing host-clamav-query.py — run: sudo dpanel update"

HOST_PY="${STACK_ROOT}/infra/scripts/host-clamav-query.py"
HOST_CMD="export CLAMAV_QUERY_MODE='${MODE}'; python3 '${HOST_PY}'"

if ! OUT="$(host_exec_capture "${HOST_CMD}")"; then
  die "${OUT:-ClamAV host query failed}"
fi

JSON_LINE="$(printf '%s\n' "${OUT}" | grep -E '^\{.*\}$' | tail -1 || true)"
if [[ -z "${JSON_LINE}" ]]; then
  die "No JSON from ClamAV query: ${OUT:0:300}"
fi

echo "${JSON_LINE}"
