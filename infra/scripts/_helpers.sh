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
    echo "[dpanel] python3 is required. Rebuild panel: dpanel update  OR  apt/apk install python3 on host" >&2
    return 1
  fi
  echo "[dpanel] Installing python3..." >&2
  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache python3
  elif command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y python3-minimal
  else
    echo "[dpanel] No apk/apt — install python3 manually" >&2
    return 1
  fi
  PYBIN="$(command -v python3)"
  [[ -n "${PYBIN}" ]]
}
