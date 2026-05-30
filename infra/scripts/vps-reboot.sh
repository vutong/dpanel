#!/usr/bin/env bash
# Reboot the VPS host — same as typing `reboot` over SSH on Ubuntu.
# Panel runs in Docker; bind-mount host / and chroot into the host reboot binary.
set -euo pipefail

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "docker CLI not available"
docker info >/dev/null 2>&1 || die "Cannot reach Docker daemon"

(
  sleep 2
  docker run --rm --privileged -v /:/host alpine:3.20 sh -c '
    if [ -x /host/usr/sbin/reboot ]; then
      exec chroot /host /usr/sbin/reboot
    fi
    if [ -x /host/sbin/reboot ]; then
      exec chroot /host /sbin/reboot
    fi
    if [ -x /host/usr/bin/systemctl ]; then
      exec chroot /host /usr/bin/systemctl reboot
    fi
    echo "Host reboot binary not found" >&2
    exit 1
  '
) >/dev/null 2>&1 &

disown 2>/dev/null || true

echo "{\"ok\":true,\"message\":\"VPS will reboot shortly\"}"
