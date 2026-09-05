#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
# steps/51-postgres.sh — PostgreSQL 15 server + psql, installed but NOT started:
# the app runs Postgres in-process in these VMs, so the service is opt-in.
STEP_DESC="PostgreSQL 15 + psql (installed; service left stopped)"
STEP_OS="all"
STEP_SUDO="no"

step_check() {
  load_brew || return 1
  [[ -x "$(brew --prefix postgresql@15 2>/dev/null)/bin/postgres" ]] || return 1
  [[ -x "$(brew --prefix libpq 2>/dev/null)/bin/psql" ]]
}

step_run() {
  load_brew || { [[ "$WI_DRY_RUN" == 1 ]] && return 0; die "Homebrew missing"; }
  if ! step_check; then wi_run brew install postgresql@15 libpq; fi
  log_info "PostgreSQL 15 is installed and stopped (the app runs Postgres in-process)."
  log_info "For a host Postgres instead: brew services start postgresql@15"
}
