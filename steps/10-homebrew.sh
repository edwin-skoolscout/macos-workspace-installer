#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
# steps/10-homebrew.sh — Homebrew present (bootstrap.sh normally did this) and updated.
STEP_DESC="Install Homebrew (macOS or Linuxbrew) and brew update"
STEP_OS="all"
# The installer needs sudo on both OSes (macOS: it creates /opt/homebrew) and checks with `sudo -n`
# under NONINTERACTIVE=1, so install.sh must prime the ticket before this step runs.
STEP_SUDO="yes"

step_check() { load_brew; }

step_run() {
  if ! load_brew; then
    log_info "Installing Homebrew"
    if wi_dry "run the official Homebrew installer (NONINTERACTIVE=1)"; then return 0; fi
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    load_brew || die "Homebrew installed but not found in any known prefix"
  fi
  wi_run brew update
}
