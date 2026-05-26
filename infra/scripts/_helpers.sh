#!/usr/bin/env bash
# Shared helpers for /opt/stack/infra/scripts (source, do not execute directly).

ensure_python3() {
  if command -v python3 >/dev/null 2>&1; then
    PYBIN="$(command -v python3)"
    return 0
  fi
  if command -v python >/dev/null 2>&1 && python -c 'import json' 2>/dev/null; then
    PYBIN="$(command -v python)"
    return 0
  fi
  if [[ "${EUID:-0}" -ne 0 ]]; then
    echo "[dpanel] python3 is required. Run: sudo apt-get install -y python3" >&2
    return 1
  fi
  echo "[dpanel] Installing python3-minimal..." >&2
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y python3-minimal
  PYBIN="$(command -v python3)"
  [[ -n "${PYBIN}" ]]
}
