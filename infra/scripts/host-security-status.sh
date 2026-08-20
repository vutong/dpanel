#!/usr/bin/env bash
# JSON status for Fail2ban + ClamAV on VPS host.
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host-chroot.sh
source "${SCRIPT_DIR}/host-chroot.sh"

PYBIN=""
if command -v python3 >/dev/null 2>&1; then
  PYBIN="$(command -v python3)"
fi

emit_json() {
  if [[ -n "${PYBIN}" ]]; then
    STACK_ROOT="${STACK_ROOT}" FAIL2BAN_RAW="${FAIL2BAN_RAW:-}" CLAMAV_RAW="${CLAMAV_RAW:-}" \
      "${PYBIN}" - <<'PY'
import json, os, subprocess, re

stack = os.environ.get("STACK_ROOT", "/opt/stack")

def host_run(cmd):
    try:
        r = subprocess.run(
            ["bash", "-lc", cmd],
            capture_output=True, text=True, timeout=30,
        )
        return (r.stdout or "") + (r.stderr or "")
    except Exception as e:
        return str(e)

def in_container():
    return os.path.isfile("/.dockerenv")

def run_host(cmd):
    if in_container():
        try:
            q = cmd.replace("'", "'\"'\"'")
            r = subprocess.run(
                [
                    "docker", "run", "--rm", "--privileged", "--pid=host", "--network", "host",
                    "-v", "/:/host",
                    "-v", "/run/systemd:/run/systemd",
                    "-v", "/run/dbus:/run/dbus",
                    "-e", f"STACK_ROOT={stack}",
                    "alpine:3.20", "sh", "-ec",
                    f"export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; "
                    f"chroot /host /bin/bash -lc '{q}'",
                ],
                capture_output=True, text=True, timeout=60,
            )
            return (r.stdout or "") + (r.stderr or "")
        except Exception as e:
            return str(e)
    return host_run(cmd)

out = {
    "ok": True,
    "fail2ban": {"installed": False, "active": False, "jails": [], "bannedIps": []},
    "clamav": {
        "installed": False,
        "daemonActive": False,
        "freshclamActive": False,
        "signatureDate": None,
    },
}

# fail2ban
if run_host("command -v fail2ban-client").strip():
    out["fail2ban"]["installed"] = True
    active = run_host("systemctl is-active fail2ban 2>/dev/null || true").strip()
    out["fail2ban"]["active"] = active == "active"
    if out["fail2ban"]["active"]:
        status = run_host("fail2ban-client status 2>/dev/null || true")
        jails = []
        banned = []
        m = re.search(r"Jail list:\s*(.+)", status)
        if m:
            jails = [j.strip() for j in m.group(1).split(",") if j.strip()]
        for jail in jails:
            js = run_host(f"fail2ban-client status {jail} 2>/dev/null || true")
            jm = re.search(r"Currently banned:\s*(.+)", js)
            if jm:
                for ip in jm.group(1).split():
                    ip = ip.strip()
                    if ip and ip not in banned:
                        banned.append(ip)
            out["fail2ban"]["jails"].append({
                "name": jail,
                "bannedIps": [
                    ip.strip()
                    for ip in (re.search(r"Currently banned:\s*(.+)", js) or [None, ""])[1].split()
                    if ip.strip()
                ],
            })
        out["fail2ban"]["bannedIps"] = banned

# clamav
if run_host("command -v clamscan").strip() or run_host("command -v clamdscan").strip():
    out["clamav"]["installed"] = True
    da = run_host("systemctl is-active clamav-daemon 2>/dev/null || true").strip()
    fc = run_host("systemctl is-active clamav-freshclam 2>/dev/null || true").strip()
    out["clamav"]["daemonActive"] = da == "active"
    out["clamav"]["freshclamActive"] = fc == "active"
    sig = run_host(
        "stat -c %y /var/lib/clamav/daily.cld 2>/dev/null || "
        "stat -c %y /var/lib/clamav/daily.cvd 2>/dev/null || true"
    ).strip()
    if sig:
        out["clamav"]["signatureDate"] = sig.split(".")[0]

print(json.dumps(out))
PY
  else
    echo '{"ok":false,"error":"python3 required"}'
  fi
}

emit_json
