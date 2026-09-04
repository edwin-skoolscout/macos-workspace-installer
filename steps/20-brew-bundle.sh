#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
# steps/20-brew-bundle.sh — install Brewfile.common then Brewfile.<os>.
STEP_DESC="brew bundle: Brewfile.common + Brewfile.<os>"
STEP_OS="all"
STEP_SUDO="no"

brew_bundle_files() { printf '%s\n' "$WI_ROOT/Brewfile.common" "$WI_ROOT/Brewfile.$WI_OS"; }

step_check() {
  load_brew || return 1
  local f
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    brew bundle check --no-upgrade --file="$f" >/dev/null 2>&1 || return 1
  done < <(brew_bundle_files)
}

step_run() {
  load_brew || die "Homebrew missing — run the homebrew step first"
  local f
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    if ! grep -qE '^(tap|brew|cask) ' "$f"; then log_info "$(basename "$f") lists nothing, skipping"; continue; fi
    HOMEBREW_NO_AUTO_UPDATE=1 wi_run brew bundle install --no-upgrade --file="$f"
  done < <(brew_bundle_files)
}
