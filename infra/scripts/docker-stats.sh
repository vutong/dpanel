#!/usr/bin/env bash
# Host + container resource usage (JSON on last line).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_helpers.sh
source "${SCRIPT_DIR}/_helpers.sh"

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
export STACK_ROOT

ensure_python3 >/dev/null 2>&1 || die "python3 required"

disk_cache="${STACK_ROOT}/data/panel/disk-probe-cache.json"
if [[ ! -f "${disk_cache}" ]] && [[ -f "${SCRIPT_DIR}/host-disk-probe.sh" ]]; then
  # shellcheck source=host-chroot.sh
  source "${SCRIPT_DIR}/host-chroot.sh"
  host_exec_capture "STACK_ROOT=${STACK_ROOT} bash ${STACK_ROOT}/infra/scripts/host-disk-probe.sh" \
    >/dev/null 2>&1 || true
fi

"${PYBIN}" <<'PY'
import json, os, re, shutil, subprocess, time

stack_root = os.environ.get("STACK_ROOT", "/opt/stack")

def load_disk_storage():
    path = os.path.join(stack_root, "data", "panel", "disk-probe-cache.json")
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        if not data.get("ok"):
            return None
        return {
            "kind": data.get("kind") or "unknown",
            "device": data.get("device") or "",
            "readMbps": data.get("readMbps"),
            "writeMbps": data.get("writeMbps"),
            "rotational": data.get("rotational"),
            "probedAt": data.get("probedAt"),
        }
    except (OSError, json.JSONDecodeError, TypeError):
        return None

def parse_docker_size(s):
    s = (s or "").strip().split("/")[0].strip()
    m = re.match(r"^([\d.]+)\s*([KMGTP]?i?B)$", s, re.I)
    if not m:
        return 0
    val = float(m.group(1))
    unit = m.group(2).upper().replace("IB", "B")
    mult = {"B": 1, "KB": 1000, "KIB": 1024, "MB": 1000**2, "MIB": 1024**2,
            "GB": 1000**3, "GIB": 1024**3, "TB": 1000**4, "TIB": 1024**4}
    return int(val * mult.get(unit, 1))

def parse_cpu_pct(s):
    s = (s or "").replace("%", "").strip()
    try:
        return round(float(s), 2)
    except ValueError:
        return 0.0

def mount_source(path):
    try:
        real = os.path.realpath(path)
    except OSError:
        return None
    best = None
    best_len = 0
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

def disk_kind_for_device(dev):
    if not dev:
        return "Disk"
    name = dev.replace("/dev/", "").split("/")[-1]
    m = re.match(r"(nvme\d+n\d+)", name)
    if m:
        return "NVMe"
    m = re.match(r"((?:sd|vd|xvd)[a-z]+)", name)
    if m:
        disk = m.group(1)
        rot = f"/sys/block/{disk}/queue/rotational"
        try:
            with open(rot) as f:
                return "HDD" if f.read().strip() == "1" else "SSD"
        except OSError:
            return "SSD"
    if name.startswith("mmcblk"):
        return "SD"
    return "Disk"

def storage_kind_label(storage):
    if not storage:
        return None
    kind = storage.get("kind") or ""
    labels = {"hdd": "HDD", "ssd": "SSD", "nvme": "NVMe"}
    return labels.get(kind) if kind in labels else (kind.upper() if kind and kind != "unknown" else None)

def parse_cpu_stat():
    cores = {}
    try:
        with open("/proc/stat") as f:
            for line in f:
                if not line.startswith("cpu") or line.startswith("cpu "):
                    continue
                parts = line.split()
                idx = int(parts[0][3:])
                idle = int(parts[4]) + int(parts[5])
                total = sum(int(x) for x in parts[1:8])
                cores[str(idx)] = {"idle": idle, "total": total}
    except (OSError, ValueError, IndexError):
        pass
    return cores

def cpu_cores_usage(host_cpu_pct):
    cache_path = os.path.join(stack_root, "data", "panel", ".cpu-stat-cache.json")
    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
    now = time.time()
    cur = parse_cpu_stat()
    prev = None
    try:
        with open(cache_path) as f:
            prev = json.load(f)
    except (OSError, json.JSONDecodeError):
        prev = None
    try:
        with open(cache_path, "w") as f:
            json.dump({"t": now, "cores": cur}, f)
    except OSError:
        pass

    result = []
    if prev and now - prev.get("t", 0) < 45:
        for key in sorted(cur.keys(), key=lambda x: int(x)):
            c = cur[key]
            p = (prev.get("cores") or {}).get(key)
            if not p:
                continue
            dt = c["total"] - p["total"]
            di = c["idle"] - p["idle"]
            if dt <= 0:
                pct = 0.0
            else:
                pct = round(max(0.0, min(100.0, (1 - di / dt) * 100)), 1)
            result.append({"index": int(key), "percent": pct})
    if not result and cur:
        n = len(cur)
        share = round(host_cpu_pct / max(n, 1), 1)
        for key in sorted(cur.keys(), key=lambda x: int(x)):
            result.append({"index": int(key), "percent": share})
    return result

host_mem_total = host_mem_used = 0
try:
    with open("/proc/meminfo") as f:
        info = {}
        for line in f:
            k, v = line.split(":", 1)
            info[k.strip()] = int(v.strip().split()[0]) * 1024
        host_mem_total = info.get("MemTotal", 0)
        avail = info.get("MemAvailable", info.get("MemFree", 0))
        host_mem_used = max(0, host_mem_total - avail)
except OSError:
    pass

host_cpu_pct = 0.0
try:
    nproc = os.cpu_count() or 1
    with open("/proc/loadavg") as f:
        load1 = float(f.read().split()[0])
    host_cpu_pct = min(100.0, round(load1 / nproc * 100, 1))
except (OSError, ValueError):
    pass

containers = []
try:
    out = subprocess.check_output(
        ["docker", "stats", "--no-stream", "--format", "{{json .}}"],
        text=True,
        timeout=30,
        stderr=subprocess.DEVNULL,
    )
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        row = json.loads(line)
        mem_parts = (row.get("MemUsage") or "").split("/")
        mem_used = parse_docker_size(mem_parts[0] if mem_parts else "")
        mem_limit = parse_docker_size(mem_parts[1]) if len(mem_parts) > 1 else 0
        containers.append({
            "name": (row.get("Name") or row.get("Container") or "").strip(),
            "cpuPercent": parse_cpu_pct(row.get("CPUPerc")),
            "memUsedBytes": mem_used,
            "memLimitBytes": mem_limit if mem_limit > 0 else None,
            "memPercent": parse_cpu_pct(row.get("MemPerc")),
        })
except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError):
    pass

containers.sort(key=lambda c: c["memUsedBytes"], reverse=True)

stack_disk_used = stack_disk_total = 0
try:
    du = shutil.disk_usage(stack_root)
    stack_disk_used = du.used
    stack_disk_total = du.total
except OSError:
    pass

disk_breakdown = []
for label, sub in [
    ("Applications", "apps"),
    ("Data", "data"),
    ("Logs", "logs"),
    ("Infra", "infra"),
    ("Panel", "panel"),
]:
    path = os.path.join(stack_root, sub)
    if not os.path.isdir(path):
        disk_breakdown.append({"label": label, "path": sub, "bytes": 0})
        continue
    try:
        out = subprocess.check_output(["du", "-sb", path], text=True, timeout=120, stderr=subprocess.DEVNULL)
        nbytes = int(out.split()[0])
        disk_breakdown.append({"label": label, "path": sub, "bytes": nbytes})
    except (subprocess.CalledProcessError, ValueError, subprocess.TimeoutExpired):
        disk_breakdown.append({"label": label, "path": sub, "bytes": 0})

disk_breakdown.sort(key=lambda x: x["bytes"], reverse=True)

storage = load_disk_storage()
system_disk_used = system_disk_total = 0
disk_kind = "Disk"
try:
    du = shutil.disk_usage(stack_root)
    system_disk_used = du.used
    system_disk_total = du.total
    disk_kind = storage_kind_label(storage) or disk_kind_for_device(mount_source(stack_root))
except OSError:
    pass

disk_payload = {
    "stackUsedBytes": stack_disk_used,
    "stackTotalBytes": stack_disk_total,
    "breakdown": disk_breakdown,
}
if storage:
    disk_payload["storage"] = storage

print(json.dumps({
    "ok": True,
    "host": {
        "cpuPercent": host_cpu_pct,
        "memUsedBytes": host_mem_used,
        "memTotalBytes": host_mem_total,
        "cpuCores": cpu_cores_usage(host_cpu_pct),
        "diskUsedBytes": system_disk_used,
        "diskTotalBytes": system_disk_total,
        "diskKind": disk_kind,
    },
    "disk": disk_payload,
    "containers": containers,
}))
PY
