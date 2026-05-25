#!/bin/sh
set -e
cd /app

export STACK_ROOT="${STACK_ROOT:-/opt/stack}"
export NUXT_HOST="${NUXT_HOST:-0.0.0.0}"
export NUXT_PORT="${NUXT_PORT:-3000}"

if [ -f package.json ]; then
  if [ ! -d node_modules/.bin ]; then
    echo "[dpanel] Cài dependencies..."
    npm ci --omit=dev 2>/dev/null || npm install --omit=dev
  fi
  if [ -f .output/server/index.mjs ]; then
    exec node .output/server/index.mjs
  fi
  echo "[dpanel] Chưa có build .output — chạy install.sh trên VPS."
fi

echo "[dpanel] Thư mục /app trống — chạy: sudo bash install.sh"
exec sleep infinity
