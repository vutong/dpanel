#!/usr/bin/env bash
# Extended ClamAV status JSON for panel (version, paths, services).
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host-chroot.sh
source "${SCRIPT_DIR}/host-chroot.sh"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || die "python3 required"

STACK_ROOT="${STACK_ROOT}" python3 <<'PY'
import json, os, subprocess

stack = os.environ.get("STACK_ROOT", "/opt/stack")

def in_container():
    return os.path.isfile("/.dockerenv")

def run_host(cmd):
    if in_container():
        try:
            q = cmd.replace("'", "'\"'\"'")
            r = subprocess.run(
                [
                    "docker", "run", "--rm", "--privileged", "--pid=host", "--network=host",
                    "-v", "/:/host",
                    "-v", "/run/systemd:/run/systemd",
                    "-v", "/run/dbus:/run/dbus",
                    "-e", f"STACK_ROOT={stack}",
                    "alpine:3.20", "sh", "-ec",
                    f"export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; "
                    f"chroot /host /bin/bash -lc '{q}'",
                ],
                capture_output=True, text=True, timeout=90,
            )
            return (r.stdout or "") + (r.stderr or "")
        except Exception as e:
            return str(e)
    try:
        r = subprocess.run(["bash", "-lc", cmd], capture_output=True, text=True, timeout=60)
        return (r.stdout or "") + (r.stderr or "")
    except Exception as e:
        return str(e)

out = {
    "ok": True,
    "installed": False,
    "daemonActive": False,
    "freshclamActive": False,
    "signatureDate": None,
    "version": None,
    "clamscanPath": None,
    "clamdscanPath": None,
    "logPaths": [],
}

if not run_host("command -v clamscan").strip():
    print(json.dumps(out))
    raise SystemExit(0)

out["installed"] = True
out["clamscanPath"] = run_host("command -v clamscan").strip() or None
out["clamdscanPath"] = run_host("command -v clamdscan").strip() or None

ver = run_host("clamscan --version 2>/dev/null | head -1 || true").strip()
if ver:
    out["version"] = ver.split()[-1] if ver.split() else ver

daemon = run_host("systemctl is-active clamav-daemon 2>/dev/null || true").strip()
fresh = run_host("systemctl is-active clamav-freshclam 2>/dev/null || true").strip()
out["daemonActive"] = daemon == "active"
out["freshclamActive"] = fresh == "active"

for p in [
    "/var/lib/clamav/daily.cld",
    "/var/lib/clamav/main.cvd",
    "/var/lib/clamav/bytecode.cvd",
]:
    ts = run_host(f"stat -c %y {p} 2>/dev/null | cut -d' ' -f1 || true").strip()
    if ts and (not out["signatureDate"] or ts > out["signatureDate"]):
        out["signatureDate"] = ts

for p in [
    "/var/log/clamav/clamav.log",
    "/var/log/clamav/freshclam.log",
    "/var/log/clamav/clamd.log",
]:
    if run_host(f"test -f {p} && echo yes || true").strip() == "yes":
        out["logPaths"].append(p)

print(json.dumps(out))
PY
