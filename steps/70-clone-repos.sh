#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
# steps/70-clone-repos.sh — clone config/repos.txt (with submodules) into WORKSPACE_DIR.
# repos.txt is git-ignored (each machine keeps its own list); config/repos.txt.example
# shows the format. Without the file, an interactive run asks for the repos and writes
# it; under --yes the step explains what to do and moves on.
STEP_DESC="Clone the repos in config/repos.txt (with submodules) into ${WORKSPACE_DIR}"
STEP_OS="all"
STEP_SUDO="no"

REPOS_FILE="${WI_REPOS_FILE:-$WI_ROOT/config/repos.txt}"

repos() { grep -vE '^[[:space:]]*(#|$)' "$REPOS_FILE"; }

repos_hint() {
  log_warn "$REPOS_FILE not found; nothing to clone."
  log_warn "Copy config/repos.txt.example to config/repos.txt, list your repos, then run:"
  log_warn "  ./install.sh --only clone-repos,project-deps"
}

# repos_prompt — ask for repos one by one and write REPOS_FILE; 1 if none were given.
# Under --dry-run the entries are shown instead of written.
repos_prompt() {
  local url branch entries=""
  log_info "No $REPOS_FILE yet. Enter the repos to clone; a blank URL finishes."
  log_info "(Or enter nothing and copy config/repos.txt.example into place later.)"
  while true; do
    read -r -p "  Git URL: " url || break
    [[ -n "$url" ]] || break
    read -r -p "  Branch [main]: " branch || branch=""
    entries+="$url ${branch:-main}"$'\n'
  done
  [[ -n "$entries" ]] || return 1
  if wi_dry "write $REPOS_FILE with:"; then printf '%s' "$entries"; return 0; fi
  {
    printf '# <git url> <branch> — cloned with --recurse-submodules into WORKSPACE_DIR\n'
    printf '%s' "$entries"
  } > "$REPOS_FILE"
  log_ok "wrote $REPOS_FILE"
}

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
  [[ -f "$REPOS_FILE" ]] || return 1
  while read -r url branch; do
    dir="$(repo_dir_for_url "$url")"
    [[ -d "$dir/.git" ]] || return 1
    submodules_ready "$dir" || return 1
  done < <(repos)
}

step_run() {
  local url branch dir
  if [[ ! -f "$REPOS_FILE" ]]; then
    if [[ "$WI_YES" == 1 ]] || ! repos_prompt; then repos_hint; return 0; fi
    [[ "$WI_DRY_RUN" != 1 ]] || return 0
  fi
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
