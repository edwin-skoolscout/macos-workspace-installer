#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
# steps/70-clone-repos.sh — clone config/repos.txt (with submodules) into WORKSPACE_DIR.
STEP_DESC="Clone skoolscout/jefelabs repos (with submodules) into ${WORKSPACE_DIR}"
STEP_OS="all"
STEP_SUDO="no"

REPOS_FILE="$WI_ROOT/config/repos.txt"

repos() { grep -vE '^[[:space:]]*(#|$)' "$REPOS_FILE"; }

# repo_dir_for_url URL → WORKSPACE_DIR/<name without .git>
repo_dir_for_url() {
  local n
  n="$(basename "$1")"
  printf '%s/%s\n' "$WORKSPACE_DIR" "${n%.git}"
}

# a leading "-" in `git submodule status` marks an uninitialised submodule
submodules_ready() { ! git -C "$1" submodule status --recursive 2>/dev/null | grep -q '^-'; }

step_check() {
  local url branch dir
  while read -r url branch; do
    dir="$(repo_dir_for_url "$url")"
    [[ -d "$dir/.git" ]] || return 1
    submodules_ready "$dir" || return 1
  done < <(repos)
}

step_run() {
  local url branch dir
  if ! wi_dry "mkdir -p $WORKSPACE_DIR"; then mkdir -p "$WORKSPACE_DIR"; fi
  while read -r url branch; do
    dir="$(repo_dir_for_url "$url")"
    if [[ ! -d "$dir/.git" ]]; then
      wi_run git clone --branch "$branch" --recurse-submodules "$url" "$dir"
    else
      log_info "$dir exists; updating submodules"
      wi_run git -C "$dir" submodule update --init --recursive
    fi
  done < <(repos)
}
