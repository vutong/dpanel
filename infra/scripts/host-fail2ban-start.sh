#!/usr/bin/env bash
# Start (or restart) fail2ban on VPS host and return status JSON.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host-chroot.sh
source "${SCRIPT_DIR}/host-chroot.sh"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || die "python3 required"

PY='
import json, os, subprocess

def in_container():
    return os.path.isfile("/.dockerenv")

def run_host(cmd):
    if in_container():
        try:
            q = cmd.replace("'", "'\"'\"'")
            r = subprocess.run(
                [
                    "docker", "run", "--rm", "--privileged", "--network", "host",
                    "-v", "/:/host",
                    "alpine:3.20", "sh", "-ec",
                    f"export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; "
                    f"chroot /host /bin/bash -lc '{q}'",
                ],
                capture_output=True, text=True, timeout=90,
            )
            return (r.stdout or "") + (r.stderr or ""), r.returncode
        except Exception as e:
            return str(e), 1
    try:
        r = subprocess.run(["bash", "-lc", cmd], capture_output=True, text=True, timeout=60)
        return (r.stdout or "") + (r.stderr or ""), r.returncode
    except Exception as e:
        return str(e), 1

if not run_host("command -v fail2ban-client")[0].strip():
    print(json.dumps({"ok": False, "error": "fail2ban not installed"}))
    raise SystemExit(1)

run_host("systemctl enable fail2ban 2>/dev/null || true")

out, code = run_host("systemctl restart fail2ban 2>&1")
active = run_host("systemctl is-active fail2ban 2>/dev/null || true")[0].strip()

if active != "active":
    journal, _ = run_host("journalctl -u fail2ban -n 15 --no-pager 2>/dev/null || true")
    cfg_test, _ = run_host("fail2ban-client -d 2>&1 | tail -20 || true")
    detail = (out or journal or cfg_test or "fail2ban failed to start").strip()
    print(json.dumps({
        "ok": False,
        "error": "fail2ban service is not active",
        "active": active,
        "detail": detail[-1500:],
    }))
    raise SystemExit(0)

print(json.dumps({"ok": True, "started": True, "active": True}))
'

python3 -c "${PY}"
