#!/usr/bin/env bash
# Probe VPS host hardware (CPU model, RAM type, disk model). JSON on stdout.
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
export STACK_ROOT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_helpers.sh
source "${SCRIPT_DIR}/_helpers.sh"

ensure_python3 >/dev/null 2>&1 || die "python3 required"

"${PYBIN}" <<'PY'
import json, os, re, subprocess, time
from collections import Counter

stack_root = os.environ.get("STACK_ROOT", "/opt/stack")

def host_run(cmd, timeout=45):
    try:
        if os.path.isfile("/.dockerenv") and _sh.which("docker"):
            q = cmd.replace("'", "'\"'\"'")
            r = subprocess.run(
                [
                    "docker", "run", "--rm", "--privileged",
                    "-v", "/:/host",
                    "alpine:3.20", "sh", "-ec",
                    "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; "
                    f"chroot /host /bin/bash -lc '{q}'",
                ],
                capture_output=True, text=True, timeout=timeout,
            )
            return ((r.stdout or "") + (r.stderr or "")).strip()
        r = subprocess.run(
            ["bash", "-lc", cmd],
            capture_output=True, text=True, timeout=timeout,
        )
        return ((r.stdout or "") + (r.stderr or "")).strip()
    except (subprocess.TimeoutExpired, OSError, FileNotFoundError):
        return ""

class _sh:
    @staticmethod
    def which(name):
        for p in os.environ.get("PATH", "").split(":"):
            fp = os.path.join(p, name)
            if os.path.isfile(fp) and os.access(fp, os.X_OK):
                return fp
        return None

def mount_source(path):
    try:
        real = os.path.realpath(path)
    except OSError:
        return None
    best, best_len = None, 0
    try:
        with open("/proc/mounts") as f:
            for line in f:
                parts = line.split()
                if len(parts) < 2:
                    continue
                mp = parts[1]
                if real == mp or real.startswith(mp.rstrip("/") + "/"):
                    if len(mp) > best_len:
                        best_len = len(mp)
                        best = parts[0]
    except OSError:
        pass
    return best

def block_base(dev_path):
    if not dev_path:
        return None
    name = dev_path.replace("/dev/", "").split("/")[-1]
    m = re.match(r"(nvme\d+n\d+)", name)
    if m:
        return m.group(1)
    m = re.match(r"(mmcblk\d+)", name)
    if m:
        return m.group(1)
    m = re.match(r"((?:sd|vd|xvd)[a-z]+)", name)
    if m:
        return m.group(1)
    return name

def disk_kind(dev, block):
    if not block:
        return "Disk"
    if block.startswith("nvme"):
        return "NVMe"
    if block.startswith("mmcblk"):
        rem = host_run(f"cat /sys/block/{block}/removable 2>/dev/null")
        if rem.strip() == "1":
            return "SD"
        return "eMMC"
    m = re.match(r"((?:sd|vd|xvd)[a-z]+)", block)
    if m:
        disk = m.group(1)
        rot = host_run(f"cat /sys/block/{disk}/queue/rotational 2>/dev/null")
        if rot.strip() == "1":
            return "HDD"
        return "SSD"
    return "Disk"

def disk_model(block):
    if not block:
        return None
    if block.startswith("nvme"):
        ctrl = re.match(r"(nvme\d+)", block)
        ctrl = ctrl.group(1) if ctrl else block
        out = host_run(
            f"tr -d ' \\n\\r\\t' </sys/class/nvme/{ctrl}/model 2>/dev/null || "
            f"tr -d ' \\n\\r\\t' </sys/block/{block}/device/model 2>/dev/null || "
            f"lsblk -d -n -o MODEL /dev/{block} 2>/dev/null"
        )
    else:
        out = host_run(
            f"tr -d ' \\n\\r\\t' </sys/block/{block}/device/model 2>/dev/null || "
            f"lsblk -d -n -o MODEL /dev/{block} 2>/dev/null"
        )
    out = (out or "").strip()
    return out or None

def cpu_model_from_proc():
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                low = line.lower()
                if low.startswith("model name") or low.startswith("model\t"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return host_run(
        "grep -m1 '^model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^[ \\t]*//'"
    ) or None

def short_cpu_model(name):
    if not name:
        return None
    n = " ".join(name.split())
    m = re.search(r"(Intel\s+\)?\s*Core\s+(?:i[3579]-[\d]+[A-Z0-9]*))", n, re.I)
    if m:
        return re.sub(r"\s+", " ", m.group(1).replace("(R)", "").replace("(TM)", "").strip())
    m = re.search(r"((?:Core\s+)?i[3579]-[\d]+[A-Z0-9]*)", n, re.I)
    if m:
        return m.group(1).strip()
    m = re.search(r"(AMD\s+Ryzen\s+\d+\s+\d+\w*)", n, re.I)
    if m:
        return m.group(1).strip()
    m = re.search(r"(AMD\s+EPYC\s+\d+\w*)", n, re.I)
    if m:
        return m.group(1).strip()
    m = re.search(r"(Xeon\s+[A-Z0-9-]+)", n, re.I)
    if m:
        return "Intel " + m.group(1).strip()
    if len(n) <= 52:
        return n
    return n[:49] + "..."

def mem_type_from_dmidecode():
    out = host_run("command -v dmidecode >/dev/null && dmidecode -t 17 2>/dev/null || true")
    types = []
    for line in out.splitlines():
        m = re.match(r"\s*Type:\s*(.+)", line, re.I)
        if not m:
            continue
        t = m.group(1).strip()
        low = t.lower()
        if low in ("unknown", "other", "<out of spec>", "dram"):
            continue
        if re.search(r"DDR[345]|LPDDR", t, re.I):
            types.append(t.upper().replace(" ", ""))
        elif "DDR" in t.upper():
            types.append(t.strip())
    if not types:
        return None
    return Counter(types).most_common(1)[0][0]

def mem_speed_mhz():
    out = host_run("command -v dmidecode >/dev/null && dmidecode -t 17 2>/dev/null || true")
    speeds = []
    for line in out.splitlines():
        m = re.match(r"\s*Speed:\s*(\d+)\s*MT/s", line, re.I)
        if m:
            speeds.append(int(m.group(1)))
        m = re.match(r"\s*Configured Memory Speed:\s*(\d+)\s*MT/s", line, re.I)
        if m:
            speeds.append(int(m.group(1)))
    return max(speeds) if speeds else None

mount_dev = mount_source(stack_root)
block = block_base(mount_dev)
full_cpu = cpu_model_from_proc()
mem_type = mem_type_from_dmidecode()
mem_speed = mem_speed_mhz()

# Infer DDR generation from speed if type missing
if not mem_type and mem_speed:
    if mem_speed >= 4800:
        mem_type = "DDR5"
    elif mem_speed >= 2400:
        mem_type = "DDR4"
    elif mem_speed >= 1333:
        mem_type = "DDR3"

print(json.dumps({
    "ok": True,
    "cpuModel": short_cpu_model(full_cpu),
    "cpuModelFull": full_cpu,
    "cpuThreads": os.cpu_count() or 0,
    "memType": mem_type,
    "memSpeedMhz": mem_speed,
    "diskKind": disk_kind(mount_dev, block),
    "diskModel": disk_model(block),
    "diskDevice": mount_dev,
    "probedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}))
PY
