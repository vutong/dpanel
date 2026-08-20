#!/usr/bin/env bash
# Start (or restart) fail2ban on VPS host and return status JSON.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host-chroot.sh
source "${SCRIPT_DIR}/host-chroot.sh"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || die "python3 required"

START_CMD="
python3 << 'PYAPPLY'
import json, subprocess, sys

def sh(cmd):
    r = subprocess.run(['bash', '-lc', cmd], capture_output=True, text=True)
    return (r.stdout or '') + (r.stderr or '')

def running():
    ping = sh('fail2ban-client ping 2>/dev/null || true').strip().lower()
    if 'pong' in ping:
        return True
    active = sh('systemctl is-active fail2ban 2>/dev/null || true').strip()
    return active == 'active'

if not sh('command -v fail2ban-client').strip():
    print(json.dumps({'ok': False, 'error': 'fail2ban not installed'}))
    sys.exit(0)

sh('systemctl enable fail2ban 2>/dev/null || true')
out = sh('systemctl restart fail2ban 2>&1') or ''

if not running():
    out = (out + '\\n' + sh('fail2ban-client start 2>&1 || true')).strip()

if running():
    print(json.dumps({'ok': True, 'started': True, 'active': True}))
    sys.exit(0)

journal = sh('journalctl -u fail2ban -n 15 --no-pager 2>/dev/null || true')
cfg = sh('fail2ban-client -d 2>&1 | tail -20 || true')
detail = (out or journal or cfg or 'fail2ban failed to start').strip()[-1500:]
active = sh('systemctl is-active fail2ban 2>/dev/null || true').strip()
print(json.dumps({
    'ok': False,
    'error': 'fail2ban service is not active',
    'active': active or 'inactive',
    'detail': detail,
}))
PYAPPLY
"

OUT="$(host_exec_capture "${START_CMD}")" || die "${OUT:-Start failed}"
echo "${OUT}" | grep -E '^\{.*\}$' | tail -1 || die "Start did not return JSON"
