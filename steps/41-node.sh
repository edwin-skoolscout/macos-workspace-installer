#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
# steps/41-node.sh — pinned Node via nvm (brew-installed) + global npm packages.
STEP_DESC="nvm: Node ${NODE_VERSION} + global npm packages"
STEP_OS="all"
STEP_SUDO="no"

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
export NVM_DIR

nvm_load() {
  load_brew || return 1
  local nvm_sh
  nvm_sh="$(brew --prefix nvm 2>/dev/null)/nvm.sh"
  [[ -s "$nvm_sh" ]] || return 1
  mkdir -p "$NVM_DIR"
  set +u
  # shellcheck source=/dev/null
  source "$nvm_sh"
  set -u
}

npm_globals() { grep -vE '^[[:space:]]*(#|$)' "$WI_ROOT/config/npm-globals.txt"; }

# npm_global_bin PKG → the executable the package installs
npm_global_bin() {
  case "$1" in
    dotenv-cli)         echo dotenv ;;
    npm-check-updates)  echo ncu ;;
    *)                  basename "$1" ;;
  esac
}

step_check() {
  nvm_load || return 1
  set +u
  if ! nvm use "$NODE_VERSION" >/dev/null 2>&1; then set -u; return 1; fi
  set -u
  [[ "$(node --version)" == "v$NODE_VERSION" ]] || return 1
  local pkg
  while IFS= read -r pkg; do
    command_exists "$(npm_global_bin "$pkg")" || return 1
  done < <(npm_globals)
}

step_run() {
  nvm_load || { [[ "$WI_DRY_RUN" == 1 ]] && return 0; die "nvm not installed (brew-bundle step)"; }
  set +u
  wi_run nvm install "$NODE_VERSION"
  wi_run nvm alias default "$NODE_VERSION"
  nvm use default >/dev/null 2>&1 || true
  set -u
  local pkg
  while IFS= read -r pkg; do
    command_exists "$(npm_global_bin "$pkg")" || wi_run npm install -g "$pkg"
  done < <(npm_globals)
}
