#!/bin/sh
set -e
cd /app

export STACK_ROOT="${STACK_ROOT:-/opt/stack}"
export NUXT_HOST="${NUXT_HOST:-0.0.0.0}"
export NUXT_PORT="${NUXT_PORT:-3000}"

if [ -f package.json ]; then
  if [ ! -d node_modules/.bin ]; then
    echo "[dpanel] Installing dependencies..."
    npm ci --omit=dev 2>/dev/null || npm install --omit=dev
  fi
  if [ -f .output/server/index.mjs ]; then
    exec node .output/server/index.mjs
  fi
  echo "[dpanel] No .output build — run install.sh on the VPS."
fi

echo "[dpanel] /app is empty — run: sudo bash install.sh"
exec sleep infinity
