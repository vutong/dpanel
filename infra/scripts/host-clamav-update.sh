#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host-chroot.sh
source "${SCRIPT_DIR}/host-chroot.sh"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

CMD="
if ! command -v freshclam >/dev/null 2>&1; then
  echo 'clamav not installed' >&2; exit 1
fi
freshclam 2>&1 || true
systemctl restart clamav-daemon 2>/dev/null || true
"

if [[ -f /.dockerenv ]] && command -v docker >/dev/null 2>&1; then
  OUT="$(host_exec_capture "${CMD}")" || die "freshclam failed"
else
  OUT="$(bash -lc "${CMD}")" || die "freshclam failed"
fi

export CLAM_UPDATE_LOG="${OUT}"
python3 - <<'PY'
import json, os
print(json.dumps({
    "ok": True,
    "message": "Signature update finished",
    "log": (os.environ.get("CLAM_UPDATE_LOG") or "")[-4000:],
}))
PY
