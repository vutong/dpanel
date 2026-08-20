#!/usr/bin/env bash
# Detect stack disk type + sequential read/write on the VPS host (VM-friendly).
# JSON on last line. Persistent cache: data/panel/disk-probe-cache.json
#   --force   delete cache and re-run benchmarks
#   --on-host internal: run probe on host (used when invoked via host chroot)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_helpers.sh
source "${SCRIPT_DIR}/_helpers.sh"

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
export STACK_ROOT

FORCE=0
ON_HOST=0
for arg in "$@"; do
  case "${arg}" in
    --force) FORCE=1 ;;
    --on-host) ON_HOST=1 ;;
  esac
done

if [[ -f /.dockerenv ]] && [[ "${ON_HOST}" != "1" ]]; then
  # shellcheck source=host-chroot.sh
  source "${SCRIPT_DIR}/host-chroot.sh"
  extra=()
  [[ "${FORCE}" -eq 1 ]] && extra+=(--force)
  host_exec_capture \
    "DPANEL_DISK_PROBE_ON_HOST=1 STACK_ROOT=${STACK_ROOT} bash ${STACK_ROOT}/infra/scripts/host-disk-probe.sh ${extra[*]} --on-host" \
    | { grep '^{' || true; } | tail -1
  exit 0
fi

ensure_python3 >/dev/null 2>&1 || die "python3 required"

export FORCE="${FORCE}"
"${PYBIN}" <<'PY'
import json, os, re, subprocess
from datetime import datetime, timezone

stack_root = os.environ.get("STACK_ROOT", "/opt/stack")
force = os.environ.get("FORCE", "0") == "1"
cache_path = os.path.join(stack_root, "data", "panel", "disk-probe-cache.json")
READ_THRESHOLD_NVME_MBPS = 350
READ_THRESHOLD_SSD_MBPS = 80


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_cache():
    try:
        with open(cache_path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return None


def save_cache(data):
    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
    with open(cache_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)


def mount_target():
    for path in (stack_root, "/"):
        if os.path.isdir(path):
            return path
    return "/"


def block_disk_name(devpath):
    devpath = (devpath or "").strip()
    if not devpath:
        return "", ""
    try:
        pk = subprocess.check_output(
            ["lsblk", "-no", "PKNAME", devpath], text=True, timeout=5, stderr=subprocess.DEVNULL
        ).strip()
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        pk = ""
    name = pk or os.path.basename(devpath)
    disk_path = f"/dev/{name}" if name else devpath
    return name, disk_path


def disk_for_mount(target):
    try:
        source = subprocess.check_output(
            ["findmnt", "-n", "-o", "SOURCE", "--target", target],
            text=True,
            timeout=5,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        return "", "", target
    if not source.startswith("/dev/"):
        return "", "", target
    disk_name, disk_path = block_disk_name(source)
    return disk_name, disk_path, target


def read_rotational(disk_name):
    path = f"/sys/block/{disk_name}/queue/rotational"
    try:
        with open(path, encoding="utf-8") as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return None


def parse_dd_mbps(text):
    m = re.search(r"([\d.]+)\s*MB/s", text or "")
    if m:
        return round(float(m.group(1)), 1)
    m = re.search(r"([\d.]+)\s*bytes.*copied,\s*([\d.]+)\s*s", text or "", re.I)
    if m:
        bytes_copied = float(m.group(1))
        seconds = float(m.group(2))
        if seconds > 0:
            return round((bytes_copied / seconds) / (1000 * 1000), 1)
    return None


def measure_read_mbps(disk_path):
    try:
        proc = subprocess.run(
            ["dd", f"if={disk_path}", "of=/dev/null", "bs=100M", "count=5", "status=none"],
            capture_output=True,
            text=True,
            timeout=120,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None
    return parse_dd_mbps((proc.stderr or "") + (proc.stdout or ""))


def measure_write_mbps(mount_path):
    test_file = os.path.join(mount_path, "data", "panel", ".disk-write-test.tmp")
    os.makedirs(os.path.dirname(test_file), exist_ok=True)
    try:
        proc = subprocess.run(
            [
                "dd",
                "if=/dev/zero",
                f"of={test_file}",
                "bs=100M",
                "count=5",
                "oflag=dsync",
                "status=none",
            ],
            capture_output=True,
            text=True,
            timeout=180,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None
    finally:
        try:
            os.remove(test_file)
        except OSError:
            pass
    return parse_dd_mbps((proc.stderr or "") + (proc.stdout or ""))


def classify(disk_name, rotational, read_mbps, write_mbps):
    peak = max(v for v in (read_mbps, write_mbps) if v is not None) if (read_mbps or write_mbps) else None
    if disk_name.startswith("nvme"):
        return "nvme"
    if rotational == 1:
        return "hdd"
    if peak is not None and peak >= READ_THRESHOLD_NVME_MBPS:
        return "nvme"
    if rotational == 0:
        return "ssd"
    if peak is not None and peak >= READ_THRESHOLD_SSD_MBPS:
        return "ssd"
    return "unknown"


if force and os.path.isfile(cache_path):
    try:
        os.remove(cache_path)
    except OSError:
        pass

disk_name, disk_path, mount = disk_for_mount(mount_target())
if not disk_name:
    print(json.dumps({"ok": False, "error": "could not resolve block device"}))
    raise SystemExit(0)

rotational = read_rotational(disk_name)
cache = load_cache()

if (
    not force
    and cache
    and cache.get("ok")
    and cache.get("device") == disk_name
    and cache.get("readMbps") is not None
    and cache.get("writeMbps") is not None
):
    print(json.dumps(cache))
    raise SystemExit(0)

read_mbps = None if force or not cache else cache.get("readMbps")
write_mbps = None if force or not cache else cache.get("writeMbps")

if read_mbps is None:
    read_mbps = measure_read_mbps(disk_path)
if write_mbps is None:
    write_mbps = measure_write_mbps(stack_root if os.path.isdir(stack_root) else mount)

kind = classify(disk_name, rotational, read_mbps, write_mbps)
result = {
    "ok": True,
    "device": disk_name,
    "devicePath": disk_path,
    "mount": mount,
    "rotational": rotational,
    "readMbps": read_mbps,
    "writeMbps": write_mbps,
    "kind": kind,
    "probedAt": now_iso(),
}
save_cache(result)
print(json.dumps(result))
PY
