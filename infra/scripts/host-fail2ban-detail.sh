#!/usr/bin/env bash
# Detailed Fail2ban status JSON for panel (jails, settings, banned IPs with time).
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host-chroot.sh
source "${SCRIPT_DIR}/host-chroot.sh"

die() { echo "{\"ok\":false,\"error\":\"$*\"}" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || die "python3 required"

STACK_ROOT="${STACK_ROOT}" python3 <<'PY'
import json, os, re, subprocess

stack = os.environ.get("STACK_ROOT", "/opt/stack")
DPANEL_JAILS = {"nginx-dpanel-login", "nginx-php-exploit"}

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

def f2b(cmd):
    return run_host(f"fail2ban-client {cmd} 2>/dev/null || true").strip()

def parse_int(s, default=0):
    try:
        return int(str(s).strip())
    except Exception:
        return default

def jail_managed(name):
    return "dpanel" if name in DPANEL_JAILS else "system"

def parse_ignoreip():
    ips = []
    for path in [
        "/etc/fail2ban/jail.local",
        "/etc/fail2ban/jail.d/dpanel-ignoreip.conf",
    ]:
        content = run_host(f"test -f {path} && cat {path} 2>/dev/null || true")
        for line in content.splitlines():
            line = line.strip()
            if line.lower().startswith("ignoreip"):
                rest = line.split("=", 1)[-1].strip()
                for part in rest.split():
                    p = part.strip()
                    if p and not p.startswith("#"):
                        ips.append(p)
    # defaults
    if not ips:
        ips = ["127.0.0.1/8", "::1"]
    seen = set()
    out = []
    for ip in ips:
        if ip not in seen:
            seen.add(ip)
            out.append(ip)
    return out

def parse_banned_with_time(jail):
    raw = f2b(f"get {jail} banip --with-time")
    entries = []
    if raw and "invalid" not in raw.lower() and "error" not in raw.lower():
        for line in raw.splitlines():
            line = line.strip()
            if not line or line.startswith("["):
                continue
            parts = line.split(None, 1)
            if parts:
                ip = parts[0].strip()
                banned_at = parts[1].strip() if len(parts) > 1 else None
                if ip and re.match(r"^[0-9a-fA-F:.]+$", ip):
                    entries.append({"ip": ip, "bannedAt": banned_at})
    if entries:
        return entries
    status = f2b(f"status {jail}")
    m = re.search(r"Currently banned:\s*(.+)", status)
    if not m:
        return []
    for ip in m.group(1).split():
        ip = ip.strip()
        if ip and re.match(r"^[0-9a-fA-F:.]+$", ip):
            entries.append({"ip": ip, "bannedAt": None})
    return entries

out = {
    "ok": True,
    "installed": False,
    "active": False,
    "version": None,
    "global": {"ignoreip": []},
    "jails": [],
    "bannedIps": [],
}

if not run_host("command -v fail2ban-client").strip():
    print(json.dumps(out))
    raise SystemExit(0)

out["installed"] = True
active = run_host("systemctl is-active fail2ban 2>/dev/null || true").strip()
out["active"] = active == "active"
ver = run_host("fail2ban-client --version 2>/dev/null | head -1 || true").strip()
if ver:
    out["version"] = ver.split()[-1] if ver.split() else ver

out["global"]["ignoreip"] = parse_ignoreip()

if not out["active"]:
    print(json.dumps(out))
    raise SystemExit(0)

status = f2b("status")
jail_names = []
m = re.search(r"Jail list:\s*(.+)", status)
if m:
    jail_names = [j.strip() for j in m.group(1).split(",") if j.strip()]

all_banned = []
for jail in jail_names:
    js = f2b(f"status {jail}")
    banned_entries = parse_banned_with_time(jail)
    banned_ips = [e["ip"] for e in banned_entries]
    for ip in banned_ips:
        if ip not in all_banned:
            all_banned.append(ip)

    def stat_field(label):
        mm = re.search(rf"{re.escape(label)}:\s*(\d+)", js)
        return parse_int(mm.group(1)) if mm else 0

    enabled_raw = f2b(f"get {jail} enabled").strip().lower()
    enabled = enabled_raw in ("true", "1", "yes")

    out["jails"].append({
        "name": jail,
        "managedBy": jail_managed(jail),
        "enabled": enabled,
        "filter": f2b(f"get {jail} filter").strip() or None,
        "logpath": f2b(f"get {jail} logpath").strip() or None,
        "maxretry": parse_int(f2b(f"get {jail} maxretry"), 5),
        "findtime": parse_int(f2b(f"get {jail} findtime"), 600),
        "bantime": parse_int(f2b(f"get {jail} bantime"), 3600),
        "currentlyFailed": stat_field("Currently failed"),
        "totalFailed": stat_field("Total failed"),
        "totalBanned": stat_field("Total banned"),
        "bannedIps": banned_entries,
    })

out["bannedIps"] = all_banned
print(json.dumps(out))
PY
