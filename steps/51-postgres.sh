#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
# steps/51-postgres.sh — PostgreSQL 15 server + psql, installed but NOT started:
# skoolscout-com's docker compose runs its own Postgres on 5432.
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
  log_info "PostgreSQL 15 is installed and stopped (compose owns port 5432)."
  log_info "For a host Postgres instead: brew services start postgresql@15"
}
