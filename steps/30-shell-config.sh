#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
# steps/30-shell-config.sh — managed block in the login shell's rc file.
STEP_DESC="Write the managed block to the login shell rc file"
STEP_OS="all"
STEP_SUDO="no"

# shellcheck source=lib/managed-block.sh
source "$WI_ROOT/lib/managed-block.sh"
# shellcheck source=lib/shell-block.sh
source "$WI_ROOT/lib/shell-block.sh"

shell_config_target() { rc_file_for_shell "$(login_shell_name)"; }
shell_config_body() {
  shell_block_render "$(login_shell_name)" "$(brew_prefix_for "$WI_OS" "$WI_ARCH")"
}

step_check() { managed_block_matches "$(shell_config_target)" "$(shell_config_body)"; }

step_run() {
  local target body
  target="$(shell_config_target)"
  body="$(shell_config_body)"
  if wi_dry "write managed block to $target"; then return 0; fi
  managed_block_write "$target" "$body"
  log_ok "managed block written to $target (open a new shell to pick it up)"
}
