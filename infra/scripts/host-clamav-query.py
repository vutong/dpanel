#!/usr/bin/env python3
"""ClamAV host query — runs on VPS host (inside chroot). Mode via CLAMAV_QUERY_MODE."""
import json
import os
import subprocess
import sys

MODE = os.environ.get("CLAMAV_QUERY_MODE", "summary")


def run(cmd):
    try:
        r = subprocess.run(["bash", "-lc", cmd], capture_output=True, text=True, timeout=30)
        return (r.stdout or "") + (r.stderr or "")
    except Exception as e:
        return str(e)


def base_out():
    return {
        "ok": True,
        "mode": MODE,
        "installed": False,
        "daemonActive": False,
        "freshclamActive": False,
        "signatureDate": None,
        "version": None,
        "clamscanPath": None,
        "clamdscanPath": None,
        "logPaths": [],
    }


def fill_services(out):
    if not run("command -v clamscan").strip():
        return out

    out["installed"] = True
    out["clamscanPath"] = run("command -v clamscan").strip() or None
    out["clamdscanPath"] = run("command -v clamdscan").strip() or None

    ver = run("clamscan --version 2>/dev/null | head -1 || true").strip()
    if ver:
        out["version"] = ver.split()[-1] if ver.split() else ver

    daemon = run("systemctl is-active clamav-daemon 2>/dev/null || true").strip()
    fresh = run("systemctl is-active clamav-freshclam 2>/dev/null || true").strip()
    out["daemonActive"] = daemon == "active"
    out["freshclamActive"] = fresh == "active"

    for p in [
        "/var/lib/clamav/daily.cld",
        "/var/lib/clamav/daily.cvd",
        "/var/lib/clamav/main.cvd",
        "/var/lib/clamav/bytecode.cvd",
    ]:
        ts = run(f"stat -c %y {p} 2>/dev/null | cut -d' ' -f1 || true").strip()
        if ts and (not out["signatureDate"] or ts > out["signatureDate"]):
            out["signatureDate"] = ts

    return out


def fill_detail(out):
    for p in [
        "/var/log/clamav/clamav.log",
        "/var/log/clamav/freshclam.log",
        "/var/log/clamav/clamd.log",
    ]:
        if run(f"test -f {p} && echo yes || true").strip() == "yes":
            out["logPaths"].append(p)
    return out


def main():
    if MODE not in ("summary", "detail"):
        print(json.dumps({"ok": False, "error": f"Invalid mode: {MODE}"}))
        sys.exit(1)

    out = fill_services(base_out())
    if MODE == "detail" and out["installed"]:
        out = fill_detail(out)

    print(json.dumps(out))


if __name__ == "__main__":
    main()
