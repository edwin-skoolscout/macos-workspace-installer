#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
# steps/45-claude-code.sh — Claude Code (native installer) + marketplaces/plugins.
STEP_DESC="Claude Code (native install) + plugins from config/claude-plugins.txt"
STEP_OS="all"
STEP_SUDO="no"

CLAUDE_PLUGINS_FILE="$WI_ROOT/config/claude-plugins.txt"
export PATH="$HOME/.local/bin:$PATH"

claude_plugin_lines() { grep -vE '^[[:space:]]*(#|$)' "$CLAUDE_PLUGINS_FILE"; }

claude_plugin_installed() { claude plugin list 2>/dev/null | grep -qF "$1"; }

step_check() {
  command_exists claude || return 1
  local kind value
  while read -r kind value; do
    [[ "$kind" == plugin ]] || continue
    claude_plugin_installed "$value" || return 1
  done < <(claude_plugin_lines)
}

step_run() {
  if ! command_exists claude; then
    if ! wi_dry "install Claude Code via https://claude.ai/install.sh"; then
      curl -fsSL https://claude.ai/install.sh | bash
      command_exists claude || die "claude not on PATH after install (expected ~/.local/bin/claude)"
    fi
  fi
  local kind value
  while read -r kind value; do
    case "$kind" in
      marketplace) wi_run claude plugin marketplace add "$value" ;;
      plugin)
        if claude_plugin_installed "$value"; then log_ok "plugin $value present"; else wi_run claude plugin install "$value"; fi ;;
      *) log_warn "unknown line in claude-plugins.txt: $kind $value" ;;
    esac
  done < <(claude_plugin_lines)
}
