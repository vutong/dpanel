#!/usr/bin/env bash
# GitHub clone/pull helpers (source from site-create.sh, site-update.sh — do not execute).

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
  [[ -n "${GITHUB_TOKEN:-}" ]] || return 0
  github_owner_repo "${GITHUB_URL:-}" || return 0
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' \
    -H "Authorization: bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}" 2>/dev/null || echo 000)"
  case "$code" in
    200) return 0 ;;
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
  if grep -qiE 'authentication failed|invalid username|403|401|denied|expired|bad credentials|repository not found' "$log" 2>/dev/null; then
    echo "Git authentication failed — token may be expired or missing repo access. Use a new GitHub PAT and try again." >&2
    return 0
  fi
  return 1
}

# Clone into empty dir (uses ${APP_DIR}/_repo_tmp then moves contents).
github_clone_into() {
  local app_dir="$1"
  local url="$2"
  local base_url="${url%.git}.git"
  local clone_err git_user

  rm -rf "${app_dir:?}"/*
  export GIT_TERMINAL_PROMPT=0
  clone_err="$(mktemp)"
  git_user="${GITHUB_USER:-x-access-token}"

  _try_clone() {
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      if git -c "credential.helper=!f() { echo username=${git_user}; echo password=\${GITHUB_TOKEN}; }; f" \
        clone --depth 1 "$base_url" "${app_dir}/_repo_tmp" 2>>"${clone_err}" \
        || git -c "credential.helper=!f() { echo username=${git_user}; echo password=\${GITHUB_TOKEN}; }; f" \
        clone "$base_url" "${app_dir}/_repo_tmp" 2>>"${clone_err}"; then
        return 0
      fi
      if [[ "$base_url" =~ ^https://github\.com/(.+)$ ]]; then
        local gh_path="${BASH_REMATCH[1]}"
        if git clone --depth 1 "https://x-access-token:${GITHUB_TOKEN}@github.com/${gh_path}" "${app_dir}/_repo_tmp" 2>>"${clone_err}" \
          || git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/${gh_path}" "${app_dir}/_repo_tmp" 2>>"${clone_err}"; then
          return 0
        fi
      fi
      if git -c "http.https://github.com/.extraheader=AUTHORIZATION: bearer ${GITHUB_TOKEN}" \
        clone --depth 1 "$base_url" "${app_dir}/_repo_tmp" 2>>"${clone_err}" \
        || git -c "http.https://github.com/.extraheader=AUTHORIZATION: bearer ${GITHUB_TOKEN}" \
        clone "$base_url" "${app_dir}/_repo_tmp" 2>>"${clone_err}"; then
        return 0
      fi
      return 1
    fi
    git clone --depth 1 "$base_url" "${app_dir}/_repo_tmp" 2>>"${clone_err}" \
      || git clone "$base_url" "${app_dir}/_repo_tmp" 2>>"${clone_err}"
  }

  if ! _try_clone; then
    github_auth_failed_message "${clone_err}" || true
    github_redact_log "${clone_err}"
    rm -f "${clone_err}"
    return 1
  fi
  rm -f "${clone_err}"
  shopt -s dotglob
  mv "${app_dir}/_repo_tmp"/* "${app_dir}/" 2>/dev/null || true
  rm -rf "${app_dir}/_repo_tmp"
  shopt -u dotglob
  return 0
}

# git pull in existing repo (configure auth when GITHUB_TOKEN is set).
github_pull_into() {
  local app_dir="$1"
  local pull_err git_user

  [[ -d "${app_dir}/.git" ]] || return 1
  export GIT_TERMINAL_PROMPT=0
  pull_err="$(mktemp)"
  git_user="${GITHUB_USER:-x-access-token}"

  (
    cd "${app_dir}"
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      git config --local credential.helper "!f() { echo username=${git_user}; echo password=${GITHUB_TOKEN}; }; f" 2>/dev/null || true
    fi
    # Always update origin when GITHUB_URL is set (URL change from panel; token optional for public repos).
    if [[ "${GITHUB_URL:-}" =~ ^https://github\.com/(.+)$ ]]; then
      gh_path="${BASH_REMATCH[1]%.git}"
      if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${gh_path}.git" 2>/dev/null || true
      else
        git remote set-url origin "https://github.com/${gh_path}.git" 2>/dev/null || true
      fi
    fi
    git fetch origin 2>>"${pull_err}" || true
    if ! git pull --ff-only 2>>"${pull_err}" && ! git pull 2>>"${pull_err}"; then
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
  return 0
}
