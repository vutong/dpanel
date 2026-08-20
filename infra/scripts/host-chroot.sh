#!/usr/bin/env bash
# Run a command on the VPS host (from panel container via chroot, or directly on host).
# Usage: source this file, then host_exec 'your command'
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"

# systemd (systemctl restart/enable) needs host PID namespace + D-Bus sockets inside chroot.
_HOST_DOCKER_OPTS=(
  --rm
  --privileged
  --pid=host
  --network=host
  -v /:/host
  -v /run/systemd:/run/systemd
  -v /run/dbus:/run/dbus
)

host_exec() {
  local cmd="$1"
  if [[ -f /.dockerenv ]] && command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    docker run "${_HOST_DOCKER_OPTS[@]}" \
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
