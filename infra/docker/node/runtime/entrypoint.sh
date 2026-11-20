#!/bin/sh
set -e
cd /app

export STACK_ROOT="${STACK_ROOT:-/opt/stack}"

if [ -f .env ]; then
  # shellcheck disable=SC1091
  . /load-dotenv.sh
  load_dotenv .env
  # shellcheck disable=SC1091
  . /node-env-bridge.sh 2>/dev/null || true
fi

# Nitro/listhen bind via HOST / NITRO_HOST (NOT NUXT_HOST — that is runtimeConfig only).
# Default 0.0.0.0 so nginx + health probes reach the app; respect app .env if set.
if [ -z "${HOST:-}" ] && [ -z "${NITRO_HOST:-}" ]; then
  export HOST=0.0.0.0
  export NITRO_HOST=0.0.0.0
else
  export HOST="${HOST:-$NITRO_HOST}"
  export NITRO_HOST="${NITRO_HOST:-$HOST}"
fi
export PORT="${PORT:-${NITRO_PORT:-3000}}"
export NITRO_PORT="${NITRO_PORT:-$PORT}"
export NUXT_HOST="${NUXT_HOST:-$HOST}"
export NUXT_PORT="${NUXT_PORT:-$PORT}"

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
