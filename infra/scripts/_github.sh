#!/usr/bin/env bash
# GitHub clone/pull helpers (source from site-create.sh, site-update.sh — do not execute).

# Timestamped line for site-create/update logs (stdout → log file after exec redirect).
github_log() {
  echo "[dpanel] $(date '+%Y-%m-%d %H:%M:%S') $*"
}

# Redact tokens from git/curl lines streamed into the panel log viewer.
github_stream_redact() {
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      line="${line//${GITHUB_TOKEN}/***REDACTED***}"
    fi
    line="$(printf '%s' "$line" | sed -E \
      's/x-access-token:[^@[:space:]]+/x-access-token:***REDACTED***/g; s/(Authorization: bearer )[^[:space:]]+/\1***REDACTED***/Ig')"
    printf '%s\n' "$line"
  done
}

github_repo_label() {
  local url="${1:-${GITHUB_URL:-}}"
  if github_owner_repo "${url}"; then
    printf '%s/%s' "${GITHUB_OWNER}" "${GITHUB_REPO}"
  else
    printf '%s' "${url}"
  fi
}

github_owner_repo() {
  local url="${1:-${GITHUB_URL:-}}"
  if [[ "$url" =~ github\.com[:/]([^/]+)/([^/#?]+) ]]; then
    GITHUB_OWNER="${BASH_REMATCH[1]}"
    GITHUB_REPO="${BASH_REMATCH[2]%.git}"
    return 0
  fi
  return 1
}

github_preflight() {
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    github_log "GitHub API check skipped (public repo — no token)"
    return 0
  fi
  if ! github_owner_repo "${GITHUB_URL:-}"; then
    github_log "GitHub API check skipped (could not parse repository URL)"
    return 0
  fi
  github_log "GitHub API: checking access to ${GITHUB_OWNER}/${GITHUB_REPO}…"
  local code
  code="$(curl -sS --connect-timeout 10 --max-time 30 -o /dev/null -w '%{http_code}' \
    -H "Authorization: bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}" 2>/dev/null || echo 000)"
  case "$code" in
    200)
      github_log "GitHub API: OK (HTTP ${code})"
      return 0
      ;;
    404)
      echo "GitHub: repository ${GITHUB_OWNER}/${GITHUB_REPO} not found or token has no access" >&2
      return 1
      ;;
    401|403)
      echo "GitHub token rejected or expired for ${GITHUB_OWNER}/${GITHUB_REPO}. Create a new classic PAT (ghp_, scope repo) or fine-grained PAT with Contents: Read — then try again." >&2
      return 1
      ;;
    *)
      echo "GitHub API check failed (HTTP ${code})" >&2
      return 1
      ;;
  esac
}

github_redact_log() {
  local f="$1"
  [[ -n "${GITHUB_TOKEN:-}" ]] && sed "s/${GITHUB_TOKEN}/***REDACTED***/g" "$f" >&2 || cat "$f" >&2
}

github_auth_failed_message() {
  local log="$1"
  if grep -qiE 'authentication failed|invalid username|bad credentials|repository not found|Authentication failed for|terminal prompts disabled' "$log" 2>/dev/null \
    && ! grep -qiE 'unable to write new index file|checkout failed|no space left on device|file too large|already exists and is not an empty directory' "$log" 2>/dev/null; then
    echo "Git authentication failed — token may be expired or missing repo access. Use a new GitHub PAT and try again." >&2
    return 0
  fi
  return 1
}

# Human-readable summary after a failed clone (printed to the panel log).
github_clone_failure_summary() {
  local log="$1"
  if grep -qiE 'no space left on device|unable to write new index file|file too large|write error|disk quota exceeded' "$log" 2>/dev/null; then
    echo "Git checkout failed — server disk may be full or apps/ is not writable. Check: df -h ${STACK_ROOT:-/opt/stack}/apps (Dashboard → disk usage). Free space, then retry Create." >&2
    return 0
  fi
  if grep -qiE 'checkout failed' "$log" 2>/dev/null; then
    echo "Git clone downloaded objects but checkout failed — often disk space or permissions under apps/. Free disk space and retry Create." >&2
    return 0
  fi
  if grep -qiE 'already exists and is not an empty directory' "$log" 2>/dev/null; then
    echo "Stale partial clone directory blocked retry — cleaned automatically on next run; retry Create once more." >&2
    return 0
  fi
  if github_auth_failed_message "$log"; then
    return 0
  fi
  echo "git clone failed — see log above for details." >&2
  return 0
}

github_clean_clone_staging() {
  local app_dir="$1"
  rm -rf "${app_dir}/_repo_tmp"
}

# True when _repo_tmp looks like a complete checkout (not a partial failed clone).
github_clone_staging_ok() {
  local app_dir="$1"
  [[ -d "${app_dir}/_repo_tmp/.git" ]] || return 1
  git -c "safe.directory=${app_dir}/_repo_tmp" -C "${app_dir}/_repo_tmp" rev-parse HEAD >/dev/null 2>&1
}

# Git 2.35+ blocks pull when repo dir owner != current user (panel root vs PHP www-data).
github_git_in() {
  local app_dir="$1"
  shift
  git -c "safe.directory=${app_dir}" "$@"
}

# Run one git clone attempt; stream progress into the panel log (tokens redacted).
_github_run_clone() {
  local app_dir="$1"
  local label="$2"
  local err_file="$3"
  shift 3
  github_clean_clone_staging "${app_dir}"
  github_log "git clone: ${label}"
  if "$@" 2>&1 | tee -a "${err_file}" | github_stream_redact \
    && github_clone_staging_ok "${app_dir}"; then
    github_log "git clone: ${label} — OK"
    return 0
  fi
  github_log "git clone: ${label} — failed (cleaning staging dir)"
  github_clean_clone_staging "${app_dir}"
  return 1
}

# Clone into empty dir (uses ${APP_DIR}/_repo_tmp then moves contents).
github_clone_into() {
  local app_dir="$1"
  local url="$2"
  local base_url="${url%.git}.git"
  local clone_err git_user repo_label waited

  repo_label="$(github_repo_label "${url}")"
  github_log "Preparing ${app_dir} (removing leftovers from any prior attempt)…"
  rm -rf "${app_dir:?}"
  mkdir -p "${app_dir}"
  if command -v df >/dev/null 2>&1; then
    github_log "Disk free: $(df -h "${app_dir}" 2>/dev/null | awk 'NR==2 {print $4 " on " $1}')"
  fi
  export GIT_TERMINAL_PROMPT=0
  # Abort hung clones (stalled network) instead of blocking the panel console forever.
  export GIT_HTTP_LOW_SPEED_LIMIT="${GIT_HTTP_LOW_SPEED_LIMIT:-1000}"
  export GIT_HTTP_LOW_SPEED_TIME="${GIT_HTTP_LOW_SPEED_TIME:-60}"
  clone_err="$(mktemp)"
  : >"${clone_err}"
  git_user="${GITHUB_USER:-x-access-token}"

  github_log "Cloning ${repo_label} into ${app_dir} (large repos may take several minutes)…"

  _try_clone() {
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      if _github_run_clone "${app_dir}" "shallow (credential helper)" "${clone_err}" \
        git -c "credential.helper=!f() { echo username=${git_user}; echo password=\${GITHUB_TOKEN}; }; f" \
        clone --progress --depth 1 "$base_url" "${app_dir}/_repo_tmp"; then
        return 0
      fi
      if _github_run_clone "${app_dir}" "full (credential helper)" "${clone_err}" \
        git -c "credential.helper=!f() { echo username=${git_user}; echo password=\${GITHUB_TOKEN}; }; f" \
        clone --progress "$base_url" "${app_dir}/_repo_tmp"; then
        return 0
      fi
      if [[ "$base_url" =~ ^https://github\.com/(.+)$ ]]; then
        local gh_path="${BASH_REMATCH[1]}"
        if _github_run_clone "${app_dir}" "shallow (token URL)" "${clone_err}" \
          git clone --progress --depth 1 "https://x-access-token:${GITHUB_TOKEN}@github.com/${gh_path}" "${app_dir}/_repo_tmp"; then
          return 0
        fi
        if _github_run_clone "${app_dir}" "full (token URL)" "${clone_err}" \
          git clone --progress "https://x-access-token:${GITHUB_TOKEN}@github.com/${gh_path}" "${app_dir}/_repo_tmp"; then
          return 0
        fi
      fi
      if _github_run_clone "${app_dir}" "shallow (extraheader)" "${clone_err}" \
        git -c "http.https://github.com/.extraheader=AUTHORIZATION: bearer ${GITHUB_TOKEN}" \
        clone --progress --depth 1 "$base_url" "${app_dir}/_repo_tmp"; then
        return 0
      fi
      if _github_run_clone "${app_dir}" "full (extraheader)" "${clone_err}" \
        git -c "http.https://github.com/.extraheader=AUTHORIZATION: bearer ${GITHUB_TOKEN}" \
        clone --progress "$base_url" "${app_dir}/_repo_tmp"; then
        return 0
      fi
      return 1
    fi
    if _github_run_clone "${app_dir}" "shallow (public)" "${clone_err}" \
      git clone --progress --depth 1 "$base_url" "${app_dir}/_repo_tmp"; then
      return 0
    fi
    _github_run_clone "${app_dir}" "full (public)" "${clone_err}" \
      git clone --progress "$base_url" "${app_dir}/_repo_tmp"
  }

  _try_clone &
  local clone_pid=$!
  waited=0
  while kill -0 "${clone_pid}" 2>/dev/null; do
    sleep 15
    waited=$((waited + 15))
    github_log "still cloning ${repo_label}… ${waited}s elapsed"
  done
  wait "${clone_pid}"
  local clone_rc=$?

  if [[ "${clone_rc}" -ne 0 ]]; then
    github_log "git clone failed — summary:"
    github_clone_failure_summary "${clone_err}"
    github_log "git clone failed — details:"
    github_redact_log "${clone_err}"
    github_clean_clone_staging "${app_dir}"
    rm -f "${clone_err}"
    return 1
  fi
  rm -f "${clone_err}"
  github_log "Clone complete — moving files into ${app_dir}"
  shopt -s dotglob
  mv "${app_dir}/_repo_tmp"/* "${app_dir}/" 2>/dev/null || true
  rm -rf "${app_dir}/_repo_tmp"
  shopt -u dotglob
  github_log "Repository ready"
  return 0
}

# git pull in existing repo (configure auth when GITHUB_TOKEN is set).
github_pull_into() {
  local app_dir="$1"
  local pull_err git_user

  [[ -d "${app_dir}/.git" ]] || return 1
  export GIT_TERMINAL_PROMPT=0
  export GIT_HTTP_LOW_SPEED_LIMIT="${GIT_HTTP_LOW_SPEED_LIMIT:-1000}"
  export GIT_HTTP_LOW_SPEED_TIME="${GIT_HTTP_LOW_SPEED_TIME:-60}"
  pull_err="$(mktemp)"
  : >"${pull_err}"
  git_user="${GITHUB_USER:-x-access-token}"

  github_log "git pull: $(github_repo_label "${GITHUB_URL:-}")"
  (
    cd "${app_dir}"
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      github_git_in "${app_dir}" config --local credential.helper "!f() { echo username=${git_user}; echo password=${GITHUB_TOKEN}; }; f" 2>/dev/null || true
    fi
    # Always update origin when GITHUB_URL is set (URL change from panel; token optional for public repos).
    if [[ "${GITHUB_URL:-}" =~ ^https://github\.com/(.+)$ ]]; then
      gh_path="${BASH_REMATCH[1]%.git}"
      if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        github_git_in "${app_dir}" remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${gh_path}.git" 2>/dev/null || true
      else
        github_git_in "${app_dir}" remote set-url origin "https://github.com/${gh_path}.git" 2>/dev/null || true
      fi
    fi
    # Fetch failure must fail the update. Previously "|| true" hid it, so pull reused stale refs
    # and reported "Already up to date" even when GitHub had newer commits.
    if ! github_git_in "${app_dir}" fetch origin 2>&1 | tee -a "${pull_err}" | github_stream_redact; then
      echo "git fetch failed — could not read latest commits from GitHub" >&2
      exit 1
    fi
    local_before="$(github_git_in "${app_dir}" rev-parse --short HEAD 2>/dev/null || echo '?')"
    if ! github_git_in "${app_dir}" pull --ff-only 2>&1 | tee -a "${pull_err}" | github_stream_redact \
      && ! github_git_in "${app_dir}" pull 2>&1 | tee -a "${pull_err}" | github_stream_redact; then
      exit 1
    fi
    # Verify the working tree actually matches the upstream branch after pull.
    local_after="$(github_git_in "${app_dir}" rev-parse --short HEAD 2>/dev/null || echo '?')"
    upstream="$(github_git_in "${app_dir}" rev-parse --short '@{u}' 2>/dev/null || echo '?')"
    echo "[dpanel] git HEAD: ${local_before} -> ${local_after} (upstream ${upstream})"
    if [[ "${upstream}" != '?' && "${local_after}" != "${upstream}" ]]; then
      echo "git pull did not reach upstream (HEAD ${local_after} != ${upstream}) — check branch tracking: git -C ${app_dir} status" >&2
      exit 1
    fi
  )
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    github_auth_failed_message "${pull_err}" || true
    github_redact_log "${pull_err}"
    rm -f "${pull_err}"
    return 1
  fi
  rm -f "${pull_err}"
  github_log "git pull complete"
  return 0
}
