#!/usr/bin/env bash
set -euo pipefail

ip="$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || true)"
if [ -n "$ip" ]; then
  echo "$ip"
  exit 0
fi

hostname -I 2>/dev/null | awk '{print $1}'
