#!/usr/bin/env bash
# Install Fail2ban + ClamAV (fresh VPS install — both packages).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "${SCRIPT_DIR}/host-fail2ban-install.sh"
bash "${SCRIPT_DIR}/host-clamav-install.sh"
