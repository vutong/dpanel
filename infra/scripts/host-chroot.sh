#!/usr/bin/env bash
# Run a command on the VPS host (from panel container via chroot, or directly on host).
# Usage: source this file, then host_exec 'your command'
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"

host_exec() {
  local cmd="$1"
  if [[ -f /.dockerenv ]] && command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    # --network host: chroot reads host /etc/resolv.conf (often 127.0.0.53). In bridge
    # mode that stub is unreachable, so apt-get/git/curl fail with "Temporary failure resolving".
    docker run --rm --privileged --network host \
      -v /:/host \
      -e "STACK_ROOT=${STACK_ROOT}" \
      --entrypoint chroot \
      alpine:3.20 \
      /host /bin/bash -lc "$cmd"
  else
    bash -lc "$cmd"
  fi
}

host_exec_capture() {
  host_exec "$1" 2>&1
}
