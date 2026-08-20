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
import json, os, re, shutil, subprocess

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

containers.sort(key=lambda c: c["cpuPercent"])

stack_disk_used = stack_disk_total = 0
try:
    du = shutil.disk_usage(stack_root)
    stack_disk_used = du.used
    stack_disk_total = du.total
except OSError:
    pass

disk_breakdown = []
for label, sub in [("Applications", "apps"), ("Data", "data"), ("Logs", "logs")]:
    path = os.path.join(stack_root, sub)
    if not os.path.isdir(path):
        continue
    try:
        out = subprocess.check_output(["du", "-sb", path], text=True, timeout=120, stderr=subprocess.DEVNULL)
        nbytes = int(out.split()[0])
        disk_breakdown.append({"label": label, "path": sub, "bytes": nbytes})
    except (subprocess.CalledProcessError, ValueError, subprocess.TimeoutExpired):
        disk_breakdown.append({"label": label, "path": sub, "bytes": 0})

disk_breakdown.sort(key=lambda x: x["bytes"], reverse=True)

disk_payload = {
    "stackUsedBytes": stack_disk_used,
    "stackTotalBytes": stack_disk_total,
    "breakdown": disk_breakdown,
}
storage = load_disk_storage()
if storage:
    disk_payload["storage"] = storage

print(json.dumps({
    "ok": True,
    "host": {
        "cpuPercent": host_cpu_pct,
        "memUsedBytes": host_mem_used,
        "memTotalBytes": host_mem_total,
    },
    "disk": disk_payload,
    "containers": containers,
}))
PY
