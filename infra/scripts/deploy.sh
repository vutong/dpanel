#!/usr/bin/env bash
set -euo pipefail
cd /opt/stack
docker compose pull --ignore-pull-failures 2>/dev/null || true
docker compose build
docker compose up -d --remove-orphans
docker compose ps
