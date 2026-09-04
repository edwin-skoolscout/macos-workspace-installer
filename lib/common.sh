#!/usr/bin/env bash
# lib/common.sh — shared helpers for install.sh, doctor.sh and every step.
# Source it; never execute it. Must stay bash-3.2 compatible.

[[ -n "${_WI_COMMON_LOADED:-}" ]] && return 0
_WI_COMMON_LOADED=1

: "${WI_DRY_RUN:=0}"
: "${WI_YES:=0}"
WI_STATE_DIR="${WI_STATE_DIR:-$HOME/.local/state/workspace-installer}"
WI_SECRETS_FILE="${WI_SECRETS_FILE:-$HOME/.config/skoolscout/secrets.env}"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_INFO=$'\033[1;36m'; C_OK=$'\033[1;32m'
  C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; C_HDR=$'\033[1;35m'
else
  C_RESET=''; C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''; C_HDR=''
fi

log_header() { printf '\n%s━━━ %s ━━━%s\n' "$C_HDR" "$*" "$C_RESET"; }
log_info()   { printf '%s→%s %s\n' "$C_INFO" "$C_RESET" "$*"; }
log_ok()     { printf '%s✓%s %s\n' "$C_OK" "$C_RESET" "$*"; }
log_warn()   { printf '%s⚠%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2; }
log_error()  { printf '%s✗%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2; }
die()        { log_error "$@"; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# detect_os → macos | linux | unsupported   (linux = Ubuntu/Debian family only)
detect_os() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux)
      if [[ -r /etc/os-release ]] && grep -qiE '^(ID|ID_LIKE)=.*(ubuntu|debian)' /etc/os-release; then
        echo linux
      else
        echo unsupported
      fi ;;
    *) echo unsupported ;;
  esac
}

# detect_arch → arm64 | amd64 | <raw uname -m>
detect_arch() {
  case "$(uname -m)" in
    arm64|aarch64) echo arm64 ;;
    x86_64|amd64)  echo amd64 ;;
    *) uname -m ;;
  esac
}

# brew_prefix_for OS ARCH → where Homebrew lives on that platform
brew_prefix_for() {
  case "$1" in
    macos) if [[ "$2" == arm64 ]]; then echo /opt/homebrew; else echo /usr/local; fi ;;
    linux) echo /home/linuxbrew/.linuxbrew ;;
    *) return 1 ;;
  esac
}

# load_brew — put brew on PATH for this process; returns 1 if not installed
load_brew() {
  command_exists brew && return 0
  local p
  for p in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew; do
    if [[ -x "$p/bin/brew" ]]; then
      eval "$("$p/bin/brew" shellenv)"
      return 0
    fi
  done
  return 1
}

# brew_trust_tap TAP — tap it, then mark it trusted. Newer Homebrew refuses to load
# formulae from untrusted third-party taps ("Run `brew trust <tap>`"); older brews
# have no `trust` subcommand, so it is only called when supported.
brew_trust_tap() {
  wi_run brew tap "$1"
  if brew trust --help >/dev/null 2>&1; then wi_run brew trust "$1"; fi
}

# wi_run CMD ARGS... — run a mutating command, or print it under --dry-run
wi_run() {
  if [[ "$WI_DRY_RUN" == 1 ]]; then
    printf '%s[dry-run]%s %s\n' "$C_WARN" "$C_RESET" "$*"
    return 0
  fi
  log_info "\$ $*"
  "$@"
}

# wi_dry MESSAGE — true (after logging MESSAGE) when in dry-run.
# Usage: if wi_dry "write $file"; then return 0; fi
wi_dry() {
  [[ "$WI_DRY_RUN" == 1 ]] || return 1
  printf '%s[dry-run]%s %s\n' "$C_WARN" "$C_RESET" "$*"
}

# confirm PROMPT [y|n] — ask the user; under --yes return the default
confirm() {
  local prompt="$1" default="${2:-y}" reply hint
  if [[ "$WI_YES" == 1 ]]; then [[ "$default" == y ]]; return; fi
  if [[ "$default" == y ]]; then hint='Y/n'; else hint='y/N'; fi
  read -r -p "$prompt [$hint] " reply
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy] ]]
}

# in_csv NEEDLE CSV — true if NEEDLE is one of the comma-separated items
in_csv() { [[ ",$2," == *",$1,"* ]]; }

# sudo_keepalive — validate sudo once and refresh it until this process exits
sudo_keepalive() {
  [[ "$WI_DRY_RUN" == 1 ]] && return 0
  sudo -v || die "sudo is required for the selected steps"
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
}

login_shell_name() { basename "${SHELL:-/bin/bash}"; }

# rc_file_for_shell SHELL → the file the managed block belongs in
rc_file_for_shell() {
  case "$1" in
    zsh)  echo "$HOME/.zprofile" ;;
    bash) echo "$HOME/.bashrc" ;;
    *)    echo "$HOME/.profile" ;;
  esac
}

# load_secrets — export the secrets file into this process; 1 if absent
load_secrets() {
  [[ -f "$WI_SECRETS_FILE" ]] || return 1
  set -a
  # shellcheck source=/dev/null
  source "$WI_SECRETS_FILE"
  set +a
}
