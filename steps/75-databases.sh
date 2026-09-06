#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
# steps/75-databases.sh — local Postgres instances for the cloned repos, from config/databases.txt
# (<repo> <database> <port> <user> <password> [init-sql-dir]). Delegates to create-database.sh
# sync: create the instance and run the repo's init scripts once, keep it running on reruns.
STEP_DESC="Local Postgres instances the cloned repos need (config/databases.txt)"
STEP_OS="all"
STEP_SUDO="no"

DATABASES_FILE="${WI_DATABASES_FILE:-$WI_ROOT/config/databases.txt}"

databases() { grep -vE '^[[:space:]]*(#|$)' "$DATABASES_FILE" 2>/dev/null; }

# applicable_databases — database names whose repo is cloned
applicable_databases() {
  local repo db _
  while read -r repo db _; do
    cloned_repo_dir "$repo" >/dev/null && printf '%s\n' "$db"
  done < <(databases)
}

step_check() {
  local db
  while read -r db; do
    [[ -f "$DATABASES_DIR/$db/PG_VERSION" ]] || return 1
  done < <(applicable_databases)
}

step_run() {
  local cmd="${WI_CREATE_DATABASE_CMD:-$WI_ROOT/create-database.sh}"   # tests point this at a stub
  if [[ -z "$(applicable_databases)" ]]; then
    log_info "no cloned repo needs a database ($DATABASES_FILE)"
    return 0
  fi
  wi_run "$cmd" sync
}
