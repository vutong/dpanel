#!/usr/bin/env bash
# Backward-compatible alias — full detail in one chroot (prefer mode-specific query for panel UI).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/host-fail2ban-query.sh" jails
# Note: legacy callers expecting banned data should use banned mode separately.
