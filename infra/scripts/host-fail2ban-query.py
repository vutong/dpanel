#!/usr/bin/env python3
"""Fail2ban host query — runs on VPS host (inside chroot). Mode via FAIL2BAN_QUERY_MODE."""
import json
import os
import re
import subprocess
import sys

MODE = os.environ.get("FAIL2BAN_QUERY_MODE", "summary")
DPANEL_JAILS = {"nginx-dpanel-login", "nginx-php-exploit"}


def run(cmd):
    try:
        r = subprocess.run(["bash", "-lc", cmd], capture_output=True, text=True, timeout=30)
        return (r.stdout or "") + (r.stderr or "")
    except Exception as e:
        return str(e)


def f2b(subcmd):
    return run(f"fail2ban-client {subcmd} 2>/dev/null || true").strip()


def parse_int(s, default=0):
    try:
        return int(str(s).strip())
    except Exception:
        return default


def jail_managed(name):
    return "dpanel" if name in DPANEL_JAILS else "system"


def parse_ignoreip():
    ips = []
    for path in ["/etc/fail2ban/jail.local", "/etc/fail2ban/jail.d/dpanel-ignoreip.conf"]:
        content = run(f"test -f {path} && cat {path} 2>/dev/null || true")
        for line in content.splitlines():
            line = line.strip()
            if line.lower().startswith("ignoreip"):
                rest = line.split("=", 1)[-1].strip()
                for part in rest.split():
                    p = part.strip()
                    if p and not p.startswith("#"):
                        ips.append(p)
    if not ips:
        ips = ["127.0.0.1/8", "::1"]
    seen = set()
    out = []
    for ip in ips:
        if ip not in seen:
            seen.add(ip)
            out.append(ip)
    return out


def is_valid_ban_ip(s):
    s = (s or "").strip()
    if not s or not re.match(r"^[0-9a-fA-F:.]+$", s):
        return False
    if re.match(r"^\d+$", s):
        return False
    if "." not in s and ":" not in s:
        return False
    return True


def parse_banned_from_status(status):
    entries = []
    m = re.search(r"Banned IP list:\s*(.+)", status)
    if m:
        rest = m.group(1).strip()
        if rest and rest not in ("-", "none", "None"):
            for ip in rest.split():
                ip = ip.strip()
                if is_valid_ban_ip(ip):
                    entries.append({"ip": ip, "bannedAt": None})
    return entries


def parse_banned_with_time(jail, jail_status):
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
                if is_valid_ban_ip(ip):
                    entries.append({"ip": ip, "bannedAt": banned_at})
    if entries:
        return entries
    return parse_banned_from_status(jail_status)


def stat_field(status, label):
    mm = re.search(rf"{re.escape(label)}:\s*(\d+)", status)
    return parse_int(mm.group(1)) if mm else 0


def jail_names_from_status(status):
    m = re.search(r"Jail list:\s*(.+)", status)
    if not m:
        return []
    return [j.strip() for j in m.group(1).split(",") if j.strip()]


def base_out():
    return {
        "ok": True,
        "mode": MODE,
        "installed": False,
        "active": False,
        "version": None,
        "global": {"ignoreip": []},
        "jails": [],
        "bannedIps": [],
    }


def main():
    if MODE not in ("summary", "jails", "banned"):
        print(json.dumps({"ok": False, "error": f"Invalid mode: {MODE}"}))
        sys.exit(1)

    out = base_out()

    if not run("command -v fail2ban-client").strip():
        print(json.dumps(out))
        return

    out["installed"] = True
    active = run("systemctl is-active fail2ban 2>/dev/null || true").strip()
    out["active"] = active == "active"
    ver = run("fail2ban-client --version 2>/dev/null | head -1 || true").strip()
    if ver:
        out["version"] = ver.split()[-1] if ver.split() else ver

    if MODE == "jails":
        out["global"]["ignoreip"] = parse_ignoreip()

    if not out["active"]:
        print(json.dumps(out))
        return

    global_status = f2b("status")
    jail_names = jail_names_from_status(global_status)
    all_banned = []

    if MODE == "summary":
        for jail in jail_names:
            js = f2b(f"status {jail}")
            banned_ips = [e["ip"] for e in parse_banned_from_status(js)]
            for ip in banned_ips:
                if ip not in all_banned:
                    all_banned.append(ip)
            out["jails"].append(
                {
                    "name": jail,
                    "managedBy": jail_managed(jail),
                    "currentlyFailed": stat_field(js, "Currently failed"),
                    "totalFailed": stat_field(js, "Total failed"),
                    "totalBanned": stat_field(js, "Total banned"),
                }
            )
        out["bannedIps"] = all_banned

    elif MODE == "jails":
        for jail in jail_names:
            js = f2b(f"status {jail}")
            enabled_raw = f2b(f"get {jail} enabled").strip().lower()
            enabled = enabled_raw in ("true", "1", "yes")
            out["jails"].append(
                {
                    "name": jail,
                    "managedBy": jail_managed(jail),
                    "enabled": enabled,
                    "filter": f2b(f"get {jail} filter").strip() or None,
                    "logpath": f2b(f"get {jail} logpath").strip() or None,
                    "maxretry": parse_int(f2b(f"get {jail} maxretry"), 5),
                    "findtime": parse_int(f2b(f"get {jail} findtime"), 600),
                    "bantime": parse_int(f2b(f"get {jail} bantime"), 3600),
                    "currentlyFailed": stat_field(js, "Currently failed"),
                    "totalFailed": stat_field(js, "Total failed"),
                    "totalBanned": stat_field(js, "Total banned"),
                    "bannedIps": [],
                }
            )

    elif MODE == "banned":
        for jail in jail_names:
            js = f2b(f"status {jail}")
            banned_entries = parse_banned_with_time(jail, js)
            for entry in banned_entries:
                if entry["ip"] not in all_banned:
                    all_banned.append(entry["ip"])
            out["jails"].append({"name": jail, "bannedIps": banned_entries})
        out["bannedIps"] = all_banned

    print(json.dumps(out))


if __name__ == "__main__":
    main()
