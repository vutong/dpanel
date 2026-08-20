#!/usr/bin/env bash
# Start (or restart) clamav-daemon + freshclam on VPS host and return status JSON.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host-chroot.sh
source "${SCRIPT_DIR}/host-chroot.sh"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || die "python3 required"

START_CMD="
python3 << 'PYSTART'
import json, subprocess

def sh(cmd):
    r = subprocess.run(['bash', '-lc', cmd], capture_output=True, text=True)
    return (r.stdout or '') + (r.stderr or '')

def service_active(unit):
    return sh(f'systemctl is-active {unit} 2>/dev/null || true').strip() == 'active'

if not sh('command -v clamscan').strip():
    print(json.dumps({'ok': False, 'error': 'ClamAV not installed'}))
    raise SystemExit(0)

sh('systemctl enable clamav-freshclam clamav-daemon 2>/dev/null || true')
sh('systemctl restart clamav-freshclam 2>&1 || true')
sh('systemctl restart clamav-daemon 2>&1 || true')

daemon = service_active('clamav-daemon')
fresh = service_active('clamav-freshclam')

if daemon and fresh:
    print(json.dumps({'ok': True, 'started': True, 'daemonActive': True, 'freshclamActive': True}))
    raise SystemExit(0)

journal = sh('journalctl -u clamav-daemon -n 12 --no-pager 2>/dev/null || true')
detail = (journal or sh('systemctl status clamav-daemon --no-pager 2>&1 || true')).strip()[-1500:]
print(json.dumps({
    'ok': False,
    'error': 'ClamAV services are not fully active',
    'daemonActive': daemon,
    'freshclamActive': fresh,
    'detail': detail,
}))
PYSTART
"

OUT="$(host_exec_capture "${START_CMD}")" || die "${OUT:-Start failed}"
echo "${OUT}" | grep -E '^\{.*\}$' | tail -1 || die "Start did not return JSON"
