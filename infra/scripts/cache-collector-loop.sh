#!/usr/bin/env bash
# Background cache collector — writes data/panel/cache/*.json (panel reads only).
set -euo pipefail

STACK_ROOT="${STACK_ROOT:-/opt/stack}"
export STACK_ROOT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_helpers.sh
source "${SCRIPT_DIR}/_helpers.sh"

CACHE_DIR="${STACK_ROOT}/data/panel/cache"
META_FILE="${CACHE_DIR}/meta.json"
COLLECTOR_STATE_FILE="${CACHE_DIR}/collector-state.json"
LOCK_DIR="${CACHE_DIR}/.collector.lock"
OP_RUNNING_GRACE_MS="${DPANEL_OP_RUNNING_GRACE_MS:-120000}"
OP_RUNNING_MAX_MS="${DPANEL_OP_RUNNING_MAX_MS:-1800000}"

PRESENCE_TTL_MS="${DPANEL_PRESENCE_TTL_MS:-45000}"
STATS_INTERVAL_ACTIVE="${DPANEL_CACHE_STATS_INTERVAL_ACTIVE_MS:-8000}"
STATS_INTERVAL_IDLE="${DPANEL_CACHE_STATS_INTERVAL_IDLE_MS:-60000}"
SECURITY_INTERVAL_ACTIVE="${DPANEL_CACHE_SECURITY_INTERVAL_ACTIVE_MS:-60000}"
SECURITY_INTERVAL_IDLE="${DPANEL_CACHE_SECURITY_INTERVAL_IDLE_MS:-120000}"
SECURITY_DETAIL_INTERVAL="${DPANEL_CACHE_SECURITY_DETAIL_INTERVAL_MS:-60000}"
DATABASES_LIST_INTERVAL="${DPANEL_CACHE_DATABASES_LIST_INTERVAL_MS:-120000}"
SITE_RESOURCES_INTERVAL="${DPANEL_CACHE_SITE_RESOURCES_INTERVAL_MS:-300000}"
SITE_RESOURCES_IDLE_INTERVAL="${DPANEL_CACHE_SITE_RESOURCES_IDLE_INTERVAL_MS:-300000}"
HOST_IP_INTERVAL="${DPANEL_CACHE_HOST_IP_INTERVAL_MS:-300000}"
SITE_PURGE_INTERVAL_ACTIVE="${DPANEL_CACHE_SITE_PURGE_INTERVAL_ACTIVE_MS:-900000}"
SITE_PURGE_INTERVAL_IDLE="${DPANEL_CACHE_SITE_PURGE_INTERVAL_IDLE_MS:-86400000}"
TICK_MS="${DPANEL_COLLECTOR_TICK_MS:-2000}"

mkdir -p "${CACHE_DIR}"

ensure_python3 >/dev/null 2>&1 || die "python3 required for cache collector"

log() {
  echo "[cache-collector] $(date -Iseconds) $*" >&2
}

write_cache_json() {
  local name="$1"
  local payload="$2"
  local stale="${3:-15}"
  local path="${CACHE_DIR}/${name}"
  mkdir -p "$(dirname "$path")"
  local tmp="${path}.$$.$RANDOM.tmp"
  "${PYBIN}" -c "
import json, sys
from datetime import datetime, timezone
data = json.loads(sys.argv[1])
env = {
  'ok': True,
  'updatedAt': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + 'Z',
  'staleAfterSec': int(sys.argv[2]),
  'warming': False,
  'data': data,
}
print(json.dumps(env, indent=2))
" "$payload" "$stale" >"$tmp"
  mv -f "$tmp" "$path"
}

read_meta_bool() {
  local key="$1"
  [[ -f "$META_FILE" ]] || return 1
  "${PYBIN}" - "$key" "$META_FILE" <<'PY' || return 1
import json, sys
key = sys.argv[1]
path = sys.argv[2]
try:
    with open(path, encoding="utf-8") as f:
        meta = json.load(f)
except (OSError, json.JSONDecodeError):
    sys.exit(1)
if key == "opRunning":
    sys.exit(0 if meta.get("opRunning") else 1)
if key == "diskTestActive":
    sys.exit(0 if meta.get("diskTestActive") else 1)
if key == "paused":
    until = meta.get("pausedUntil")
    if not until:
        sys.exit(1)
    from datetime import datetime, timezone
    try:
        t = datetime.fromisoformat(until.replace("Z", "+00:00"))
        sys.exit(0 if datetime.now(timezone.utc) < t else 1)
    except ValueError:
        sys.exit(1)
sys.exit(1)
PY
}

section_active() {
  local section="$1"
  [[ -f "$META_FILE" ]] || return 1
  "${PYBIN}" - "$section" "$PRESENCE_TTL_MS" "$META_FILE" <<'PY'
import json, sys
from datetime import datetime, timezone
section = sys.argv[1]
ttl_ms = int(sys.argv[2])
path = sys.argv[3]
try:
    with open(path, encoding="utf-8") as f:
        meta = json.load(f)
    state = (meta.get("sections") or {}).get(section)
    if not state or not state.get("lastSeenAt"):
        raise SystemExit(1)
    t = datetime.fromisoformat(state["lastSeenAt"].replace("Z", "+00:00"))
    age_ms = (datetime.now(timezone.utc) - t).total_seconds() * 1000
    raise SystemExit(0 if age_ms < ttl_ms else 1)
except (OSError, json.JSONDecodeError, ValueError, KeyError):
    raise SystemExit(1)
PY
}

collector_paused() {
  read_meta_bool opRunning && return 0
  read_meta_bool diskTestActive && return 0
  read_meta_bool paused && return 0
  return 1
}

any_section_active() {
  section_active dashboard && return 0
  section_active settings && return 0
  section_active databases && return 0
  section_active websites && return 0
  return 1
}

# Exit 0 when job is due (no recent run within interval_ms).
job_due() {
  local job="$1"
  local interval_ms="$2"
  [[ -f "$COLLECTOR_STATE_FILE" ]] || return 0
  "${PYBIN}" - "$job" "$interval_ms" "$COLLECTOR_STATE_FILE" <<'PY'
import json, sys
from datetime import datetime, timezone
job, interval_ms, path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
try:
    with open(path, encoding="utf-8") as f:
        state = json.load(f)
    last = (state.get("collectorLastRun") or {}).get(job)
    if not last:
        raise SystemExit(0)
    t = datetime.fromisoformat(last.replace("Z", "+00:00"))
    age_ms = (datetime.now(timezone.utc) - t).total_seconds() * 1000
    raise SystemExit(0 if age_ms >= interval_ms else 1)
except (OSError, json.JSONDecodeError, ValueError, KeyError):
    raise SystemExit(0)
PY
}

last_json_line() {
  echo "$1" | awk '/^\{/{print}' | tail -n 1
}

last_json_array_line() {
  echo "$1" | awk '/^\[/{print}' | tail -n 1
}

try_pop_pending_force() {
  local job="$1"
  [[ -f "$META_FILE" ]] || return 1
  "${PYBIN}" - "$job" "$META_FILE" <<'PY'
import json, sys, os
job, path = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as f:
        meta = json.load(f)
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
pending = list(meta.get("pendingForce") or [])
if job not in pending:
    raise SystemExit(1)
meta["pendingForce"] = [x for x in pending if x != job]
tmp = f"{path}.{os.getpid()}.tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(meta, f, indent=2)
os.replace(tmp, path)
raise SystemExit(0)
PY
}

acquire_job_lock() {
  local job="$1"
  mkdir "${LOCK_DIR}/${job}" 2>/dev/null || return 1
  return 0
}

release_job_lock() {
  local job="$1"
  rmdir "${LOCK_DIR}/${job}" 2>/dev/null || true
}

touch_collector_run() {
  local job="$1"
  [[ -f "$COLLECTOR_STATE_FILE" ]] || init_collector_state_if_missing
  "${PYBIN}" - "$job" "$COLLECTOR_STATE_FILE" <<'PY' || true
import json, sys, os
from datetime import datetime, timezone
job, path = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as f:
        state = json.load(f)
except (OSError, json.JSONDecodeError):
    state = {}
runs = state.get("collectorLastRun") or {}
runs[job] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
state["collectorLastRun"] = runs
tmp = f"{path}.{os.getpid()}.tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
PY
}

run_stats_job() {
  local require_dashboard="${1:-1}"
  if collector_paused; then
    return 0
  fi
  if [[ "$require_dashboard" == "1" ]] && ! section_active dashboard; then
    return 0
  fi
  if ! acquire_job_lock stats; then
    return 0
  fi
  log "stats job start"
  local out
  if out="$(bash "${SCRIPT_DIR}/docker-stats.sh" 2>&1)"; then
    local json_line
    json_line="$(echo "$out" | awk '/^\{/{print}' | tail -n 1)"
    if [[ -n "$json_line" ]]; then
      write_cache_json stats.json "$json_line" 15
      touch_collector_run stats
      log "stats job ok"
    else
      log "stats job: no JSON line in output"
    fi
  else
    log "stats job failed: ${out:0:200}"
  fi
  release_job_lock stats
}

run_security_job() {
  local require_active="${1:-1}"
  if collector_paused; then
    return 0
  fi
  if [[ "$require_active" == "1" ]] && ! any_section_active; then
    return 0
  fi
  if ! acquire_job_lock security; then
    return 0
  fi
  log "security job start"
  local status_out f2b_out clam_out status_line f2b_line clam_line combined banned_json
  status_line=""
  f2b_line=""
  clam_line=""
  if status_out="$(bash "${SCRIPT_DIR}/host-security-status.sh" 2>&1)"; then
    status_line="$(last_json_line "$status_out")"
  else
    log "security status script failed: ${status_out:0:160}"
  fi
  if f2b_out="$(bash "${SCRIPT_DIR}/host-fail2ban-query.sh" summary 2>&1)"; then
    f2b_line="$(last_json_line "$f2b_out")"
  else
    log "fail2ban summary failed: ${f2b_out:0:160}"
  fi
  if clam_out="$(bash "${SCRIPT_DIR}/host-clamav-query.sh" summary 2>&1)"; then
    clam_line="$(last_json_line "$clam_out")"
  else
    log "clamav summary failed: ${clam_out:0:160}"
  fi
  if [[ -n "$status_line" || -n "$f2b_line" || -n "$clam_line" ]]; then
    combined="$("${PYBIN}" - "$status_line" "$f2b_line" "$clam_line" <<'PY'
import json, sys
def parse(s):
    s = (s or "").strip()
    if not s:
        return None
    try:
        return json.loads(s)
    except json.JSONDecodeError:
        return None
out = {}
st, f2b, clam = parse(sys.argv[1]), parse(sys.argv[2]), parse(sys.argv[3])
if st is not None:
    out["status"] = st
if f2b is not None:
    out["fail2banSummary"] = f2b
if clam is not None:
    out["clamavSummary"] = clam
print(json.dumps(out))
PY
)"
    write_cache_json security.json "$combined" 90
    touch_collector_run security
    log "security job ok"
    banned_json="$("${PYBIN}" - "$f2b_line" <<'PY' || echo '[]'
import json, sys
s = (sys.argv[1] or "").strip()
if not s:
    print("[]")
    raise SystemExit(0)
try:
    data = json.loads(s)
except json.JSONDecodeError:
    print("[]")
    raise SystemExit(0)
ips = list(data.get("bannedIps") or [])
for jail in data.get("jails") or []:
    for entry in jail.get("bannedIps") or []:
        if isinstance(entry, str):
            ips.append(entry)
        elif isinstance(entry, dict) and entry.get("ip"):
            ips.append(entry["ip"])
print(json.dumps(sorted(set(str(x).strip() for x in ips if x))))
PY
)"
    bash "${SCRIPT_DIR}/security-sync-ban-events.sh" "$banned_json" 2>/dev/null || true
    bash "${SCRIPT_DIR}/security-sync-install-events.sh" 2>/dev/null || true
  else
    log "security job: no JSON payloads"
  fi
  release_job_lock security
}

run_security_detail_job() {
  if collector_paused; then
    return 0
  fi
  if ! section_active settings; then
    return 0
  fi
  if ! acquire_job_lock security-detail; then
    return 0
  fi
  log "security-detail job start"
  local jails_out banned_out clam_out jails_line banned_line clam_line combined
  jails_line=""
  banned_line=""
  clam_line=""
  if jails_out="$(bash "${SCRIPT_DIR}/host-fail2ban-query.sh" jails 2>&1)"; then
    jails_line="$(last_json_line "$jails_out")"
  fi
  if banned_out="$(bash "${SCRIPT_DIR}/host-fail2ban-query.sh" banned 2>&1)"; then
    banned_line="$(last_json_line "$banned_out")"
  fi
  if clam_out="$(bash "${SCRIPT_DIR}/host-clamav-query.sh" detail 2>&1)"; then
    clam_line="$(last_json_line "$clam_out")"
  fi
  if [[ -n "$jails_line" || -n "$banned_line" || -n "$clam_line" ]]; then
    combined="$("${PYBIN}" - "$jails_line" "$banned_line" "$clam_line" <<'PY'
import json, sys
def parse(s):
    s = (s or "").strip()
    if not s:
        return None
    try:
        return json.loads(s)
    except json.JSONDecodeError:
        return None
out = {}
j, b, c = parse(sys.argv[1]), parse(sys.argv[2]), parse(sys.argv[3])
if j is not None:
    out["fail2banJails"] = j
if b is not None:
    out["fail2banBanned"] = b
if c is not None:
    out["clamavDetail"] = c
print(json.dumps(out))
PY
)"
    write_cache_json security-detail.json "$combined" 120
    touch_collector_run security-detail
    log "security-detail job ok"
    banned_json="$("${PYBIN}" - "$banned_line" <<'PY' || echo '[]'
import json, sys
s = (sys.argv[1] or "").strip()
if not s:
    print("[]")
    raise SystemExit(0)
try:
    data = json.loads(s)
except json.JSONDecodeError:
    print("[]")
    raise SystemExit(0)
ips = list(data.get("bannedIps") or [])
for jail in data.get("jails") or []:
    for entry in jail.get("bannedIps") or []:
        if isinstance(entry, str):
            ips.append(entry)
        elif isinstance(entry, dict) and entry.get("ip"):
            ips.append(entry["ip"])
print(json.dumps(sorted(set(str(x).strip() for x in ips if x))))
PY
)"
    bash "${SCRIPT_DIR}/security-sync-ban-events.sh" "$banned_json" 2>/dev/null || true
  else
    log "security-detail job: no JSON payloads"
  fi
  release_job_lock security-detail
}

run_databases_list_job() {
  local force="${1:-0}"
  if collector_paused; then
    return 0
  fi
  if [[ "$force" != "1" ]] && ! section_active databases; then
    return 0
  fi
  if [[ "$force" != "1" ]] && ! job_due databases-list "$DATABASES_LIST_INTERVAL"; then
    return 0
  fi
  if ! acquire_job_lock databases-list; then
    return 0
  fi
  log "databases-list job start"
  local out json_line
  if out="$(bash "${SCRIPT_DIR}/db-list.sh" 2>&1)"; then
    json_line="$(last_json_array_line "$out")"
    if [[ -z "$json_line" ]]; then
      json_line="$(echo "$out" | tr -d '\n' | sed -n 's/.*\(\[.*\]\).*/\1/p' | tail -n 1)"
    fi
    if [[ -n "$json_line" ]]; then
      write_cache_json databases-list.json "$json_line" 120
      touch_collector_run databases-list
      log "databases-list job ok"
    else
      log "databases-list job: no JSON array in output"
    fi
  else
    log "databases-list job failed: ${out:0:200}"
  fi
  release_job_lock databases-list
}

websites_domain() {
  [[ -f "$META_FILE" ]] || return 1
  "${PYBIN}" - "$META_FILE" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as f:
        meta = json.load(f)
    state = (meta.get("sections") or {}).get("websites") or {}
    domain = (state.get("domain") or "").strip().lower()
    if domain:
        print(domain)
        raise SystemExit(0)
except (OSError, json.JSONDecodeError, KeyError):
    pass
raise SystemExit(1)
PY
}

run_host_ip_job() {
  local force="${1:-0}"
  if collector_paused; then
    return 0
  fi
  if [[ "$force" != "1" ]] && ! section_active websites; then
    return 0
  fi
  if [[ "$force" != "1" ]] && ! job_due host-ip "$HOST_IP_INTERVAL"; then
    return 0
  fi
  if ! acquire_job_lock host-ip; then
    return 0
  fi
  log "host-ip job start"
  local ip payload
  ip="$(bash "${SCRIPT_DIR}/host-ip.sh" 2>/dev/null | tr -d '\r\n' | awk '{print $1; exit}')"
  payload="$("${PYBIN}" - "$ip" <<'PY'
import json, sys
ip = (sys.argv[1] or "").strip()
print(json.dumps({"ip": ip}))
PY
)"
  write_cache_json host-ip.json "$payload" 300
  touch_collector_run host-ip
  log "host-ip job ok (${ip:-none})"
  release_job_lock host-ip
}

run_site_resources_job() {
  local force="${1:-0}"
  local domain slug out json_line
  domain="$(websites_domain 2>/dev/null || true)"
  [[ -n "$domain" ]] || return 0
  if collector_paused; then
    return 0
  fi
  if [[ "$force" != "1" ]] && ! section_active websites; then
    return 0
  fi
  if [[ "$force" != "1" ]] && ! job_due site-resources "$SITE_RESOURCES_INTERVAL"; then
    return 0
  fi
  if ! acquire_job_lock site-resources; then
    return 0
  fi
  slug="$(site_slug "$domain")"
  log "site-resources job start (${domain})"
  if out="$(bash "${SCRIPT_DIR}/site-resources-cache.sh" "$domain" 2>&1)"; then
    json_line="$(last_json_line "$out")"
    if [[ -n "$json_line" ]]; then
      write_cache_json "site-resources/${slug}.json" "$json_line" 300
      touch_collector_run site-resources
      log "site-resources job ok (${slug})"
    else
      log "site-resources job: no JSON in output"
    fi
  else
    log "site-resources job failed: ${out:0:200}"
  fi
  release_job_lock site-resources
}

pick_next_node_site_domain() {
  [[ -f "${STACK_ROOT}/data/panel/sites.json" ]] || return 1
  "${PYBIN}" - "$STACK_ROOT" "$COLLECTOR_STATE_FILE" <<'PY'
import json, os, sys
stack, state_path = sys.argv[1], sys.argv[2]
sites_path = os.path.join(stack, "data", "panel", "sites.json")
try:
    with open(sites_path, encoding="utf-8") as f:
        sites = json.load(f)
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
domains = sorted(
    str(s.get("domain", "")).strip().lower()
    for s in (sites if isinstance(sites, list) else [])
    if s.get("runtime") == "node" and s.get("domain") and not s.get("pendingDeleteAt")
)
if not domains:
    raise SystemExit(1)
try:
    with open(state_path, encoding="utf-8") as f:
        state = json.load(f)
except (OSError, json.JSONDecodeError):
    state = {}
cursor = int(state.get("siteResourcesCursor") or 0)
domain = domains[cursor % len(domains)]
state["siteResourcesCursor"] = (cursor + 1) % len(domains)
if "collectorLastRun" not in state:
    state["collectorLastRun"] = {}
tmp = f"{state_path}.{os.getpid()}.tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
os.replace(tmp, state_path)
print(domain)
PY
}

run_site_resources_for_domain() {
  local domain="$1"
  local slug out json_line
  [[ -n "$domain" ]] || return 0
  slug="$(site_slug "$domain")"
  if out="$(bash "${SCRIPT_DIR}/site-resources-cache.sh" "$domain" 2>&1)"; then
    json_line="$(last_json_line "$out")"
    if [[ -n "$json_line" ]]; then
      write_cache_json "site-resources/${slug}.json" "$json_line" 300
      return 0
    fi
  fi
  return 1
}

run_site_resources_idle_job() {
  local domain
  if collector_paused; then
    return 0
  fi
  if section_active websites; then
    return 0
  fi
  if ! job_due site-resources-idle "$SITE_RESOURCES_IDLE_INTERVAL"; then
    return 0
  fi
  if ! acquire_job_lock site-resources-idle; then
    return 0
  fi
  domain="$(pick_next_node_site_domain 2>/dev/null || true)"
  if [[ -n "$domain" ]]; then
    log "site-resources idle scan (${domain})"
    if run_site_resources_for_domain "$domain"; then
      touch_collector_run site-resources-idle
      log "site-resources idle ok (${domain})"
    else
      log "site-resources idle failed (${domain})"
    fi
  fi
  release_job_lock site-resources-idle
}

run_site_purge_job() {
  if collector_paused; then
    return 0
  fi
  if ! acquire_job_lock site-purge; then
    return 0
  fi
  log "site-purge job start"
  bash "${SCRIPT_DIR}/site-purge-expired.sh" >/dev/null 2>&1 || log "site-purge job: script reported issues"
  touch_collector_run site-purge
  log "site-purge job done"
  release_job_lock site-purge
}

init_collector_state_if_missing() {
  if [[ -f "$COLLECTOR_STATE_FILE" ]]; then
    return 0
  fi
  local tmp="${COLLECTOR_STATE_FILE}.$$.$RANDOM.tmp"
  cat >"$tmp" <<'EOF'
{
  "collectorLastRun": {}
}
EOF
  mv -f "$tmp" "$COLLECTOR_STATE_FILE"
}

migrate_collector_state_from_meta() {
  [[ -f "$META_FILE" ]] || return 0
  "${PYBIN}" - "$META_FILE" "$COLLECTOR_STATE_FILE" <<'PY' || true
import json, sys, os
meta_path, state_path = sys.argv[1], sys.argv[2]
try:
    with open(meta_path, encoding="utf-8") as f:
        meta = json.load(f)
except (OSError, json.JSONDecodeError):
    raise SystemExit(0)
legacy = meta.get("collectorLastRun") or {}
if not legacy:
    raise SystemExit(0)
try:
    with open(state_path, encoding="utf-8") as f:
        state = json.load(f)
except (OSError, json.JSONDecodeError):
    state = {}
runs = state.get("collectorLastRun") or {}
runs.update(legacy)
state["collectorLastRun"] = runs
tmp = f"{state_path}.{os.getpid()}.tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
os.replace(tmp, state_path)
# Strip legacy field from panel meta (atomic)
meta.pop("collectorLastRun", None)
tmp_meta = f"{meta_path}.{os.getpid()}.meta.tmp"
with open(tmp_meta, "w", encoding="utf-8") as f:
    json.dump(meta, f, indent=2)
    f.write("\n")
os.replace(tmp_meta, meta_path)
PY
}

reconcile_op_running() {
  [[ -f "$META_FILE" ]] || return 0
  bash "${SCRIPT_DIR}/host-op-running-reconcile.sh" \
    "$META_FILE" "$OP_RUNNING_GRACE_MS" "$OP_RUNNING_MAX_MS" 2>/dev/null || true
}

init_meta_if_missing() {
  if [[ -f "$META_FILE" ]]; then
    return 0
  fi
  local tmp="${META_FILE}.$$.$RANDOM.tmp"
  cat >"$tmp" <<'EOF'
{
  "sections": {},
  "opRunning": false,
  "opRunningSince": null,
  "pausedUntil": null,
  "pendingForce": []
}
EOF
  mv -f "$tmp" "$META_FILE"
}

sleep_ms() {
  local ms="$1"
  local sec=$((ms / 1000))
  local rem=$((ms % 1000))
  sleep "$sec"
  if [[ "$rem" -gt 0 ]]; then
    usleep $((rem * 1000)) 2>/dev/null || sleep 1
  fi
}

main_loop() {
  init_meta_if_missing
  init_collector_state_if_missing
  migrate_collector_state_from_meta
  log "warm stats on start"
  run_stats_job 0
  log "warm security on start"
  run_security_job 0

  local stats_due_at=0
  while true; do
    local now_ms
    now_ms="$("${PYBIN}" - <<'PY'
import time
print(int(time.time() * 1000))
PY
)"

    reconcile_op_running

    if section_active dashboard; then
      if (( now_ms - stats_due_at >= STATS_INTERVAL_ACTIVE )); then
        run_stats_job 1
        stats_due_at=$now_ms
      fi
    fi

    if section_active dashboard; then
      if job_due security "$SECURITY_INTERVAL_ACTIVE"; then
        run_security_job 1
      fi
    elif job_due security "$SECURITY_INTERVAL_IDLE"; then
      run_security_job 0
    fi

    if any_section_active; then
      if job_due site-purge "$SITE_PURGE_INTERVAL_ACTIVE"; then
        run_site_purge_job
      fi
    elif job_due site-purge "$SITE_PURGE_INTERVAL_IDLE"; then
      run_site_purge_job
    fi

    sleep_ms "$TICK_MS"
  done
}

trap 'log "shutdown"; exit 0' TERM INT
main_loop
