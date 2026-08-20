#!/usr/bin/env bash
# Backward-compatible alias — prefer host-clamav-query.sh detail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/host-clamav-query.sh" detail
