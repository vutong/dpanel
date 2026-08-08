#!/bin/sh
set -e
cd /app

export STACK_ROOT="${STACK_ROOT:-/opt/stack}"
export NUXT_HOST="${NUXT_HOST:-0.0.0.0}"
export NUXT_PORT="${NUXT_PORT:-3000}"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
  # shellcheck disable=SC1091
  . /node-env-bridge.sh 2>/dev/null || true
fi

if [ -f package.json ]; then
  if [ -f .output/server/index.mjs ]; then
    if [ ! -d node_modules/.bin ]; then
      echo "[dpanel] Installing production dependencies..."
      npm ci --omit=dev 2>/dev/null || npm install --omit=dev
    fi
    exec node .output/server/index.mjs
  fi
  echo "[dpanel] No .output build yet — use Rebuild in the panel or: dpanel site-rebuild <domain>"
  echo "[dpanel] Container waiting (nginx will return 502 until build completes)."
  exec sleep infinity
fi

echo "[dpanel] /app is empty — deploy code then Rebuild in the panel"
exec sleep infinity
