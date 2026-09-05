#!/usr/bin/env bash
# lib/shell-block.sh — render the managed rc block for a shell/brew prefix.

[[ -n "${_WI_SHELL_BLOCK_LOADED:-}" ]] && return 0
_WI_SHELL_BLOCK_LOADED=1

# shell_block_render SHELL BREW_PREFIX → block body on stdout
shell_block_render() {
  local shell="$1" brew_prefix="$2"
  cat <<EOT
eval "\$($brew_prefix/bin/brew shellenv)"
export SDKMAN_DIR="\$HOME/.sdkman"
[[ -s "\$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "\$SDKMAN_DIR/bin/sdkman-init.sh"
export NVM_DIR="\$HOME/.nvm"
[ -s "$brew_prefix/opt/nvm/nvm.sh" ] && source "$brew_prefix/opt/nvm/nvm.sh"
export PYENV_ROOT="\$HOME/.pyenv"
command -v pyenv >/dev/null 2>&1 && eval "\$(pyenv init -)"
command -v direnv >/dev/null 2>&1 && eval "\$(direnv hook $shell)"
export PATH="\$HOME/.cargo/bin:\$HOME/.local/bin:$brew_prefix/opt/rustup/bin:$brew_prefix/opt/libpq/bin:\$PATH"
[ -f "\$HOME/.config/skoolscout/secrets.env" ] && set -a && source "\$HOME/.config/skoolscout/secrets.env" && set +a
EOT
}
