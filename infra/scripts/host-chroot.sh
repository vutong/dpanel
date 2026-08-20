#!/usr/bin/env bash
# Run a command on the VPS host (from panel container via chroot, or directly on host).
# Usage: source this file, then host_exec 'your command'
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"

host_exec() {
  local cmd="$1"
  if [[ -f /.dockerenv ]] && command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    docker run --rm --privileged \
      -v /:/host \
      -e "STACK_ROOT=${STACK_ROOT}" \
      alpine:3.20 sh -ec "
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        chroot /host /bin/bash -lc $(printf '%q' "$cmd")
      "
  else
    bash -lc "$cmd"
  fi
}

host_exec_capture() {
  host_exec "$1" 2>&1
}
