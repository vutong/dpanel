#!/usr/bin/env bash
# Probe host hardware and save to data/panel/host-hardware.json (persistent).
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
export STACK_ROOT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_helpers.sh
source "${SCRIPT_DIR}/_helpers.sh"

ensure_python3 >/dev/null 2>&1 || die "python3 required"

PROBE="${SCRIPT_DIR}/host-hardware-probe.sh"
[[ -f "${PROBE}" ]] || die "host-hardware-probe.sh not found"

"${PYBIN}" <<'PY'
import json, os, subprocess, sys

stack = os.environ.get("STACK_ROOT", "/opt/stack")
probe = os.path.join(stack, "infra", "scripts", "host-hardware-probe.sh")
cache = os.path.join(stack, "data", "panel", "host-hardware.json")

try:
    out = subprocess.check_output(
        ["bash", probe],
        text=True,
        timeout=120,
        env={**os.environ, "STACK_ROOT": stack},
        stderr=subprocess.STDOUT,
    )
except subprocess.CalledProcessError as e:
    print(json.dumps({"ok": False, "error": (e.output or str(e))[:500]}))
    sys.exit(1)

lines = [l.strip() for l in out.splitlines() if l.strip().startswith("{")]
if not lines:
    print(json.dumps({"ok": False, "error": "Probe returned no JSON"}))
    sys.exit(1)

hw = json.loads(lines[-1])
os.makedirs(os.path.dirname(cache), exist_ok=True)
with open(cache, "w", encoding="utf-8") as f:
    json.dump(hw, f, indent=2)
    f.write("\n")

print(json.dumps({"ok": True, "hardware": hw}))
PY
