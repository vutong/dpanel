#!/bin/sh
# Export assignments from a dotenv file without executing values as shell.
load_dotenv() {
  _dotenv_file="${1:-.env}"
  if [ ! -f "${_dotenv_file}" ]; then
    unset _dotenv_file
    return 0
  fi
  if [ ! -f /load-dotenv.js ]; then
    echo "[dpanel] /load-dotenv.js missing — cannot load ${_dotenv_file}" >&2
    unset _dotenv_file
    return 1
  fi
  eval "$(node /load-dotenv.js "${_dotenv_file}")"
  _dotenv_rc=$?
  unset _dotenv_file
  return "${_dotenv_rc}"
}
