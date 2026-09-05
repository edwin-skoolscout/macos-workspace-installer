#!/usr/bin/env bash
# bootstrap.sh — the only file a fresh VM needs.
#
#   curl -fsSL https://raw.githubusercontent.com/edwin-skoolscout/macos-workspace-installer/main/bootstrap.sh | bash
#   curl -fsSL .../bootstrap.sh | bash -s -- --skip rust,postgres     # forward install.sh flags
#   ./bootstrap.sh                                                     # from a local checkout
#
# Installs OS prerequisites and Homebrew, fetches this repo, then execs install.sh.
# Deliberately self-contained: it cannot source lib/ because lib/ is not here yet.
# Env: INSTALLER_REPO, INSTALLER_REF, INSTALLER_DIR; BOOTSTRAP_SKIP_BREW=1 and BOOTSTRAP_BREW_PREFIXES (tests only).
set -euo pipefail

INSTALLER_REPO="${INSTALLER_REPO:-https://github.com/edwin-skoolscout/macos-workspace-installer.git}"
INSTALLER_REF="${INSTALLER_REF:-main}"
INSTALLER_DIR="${INSTALLER_DIR:-$HOME/Development/Workspaces/ecruz165/macos-workspace-installer}"

say()  { printf '\033[1;36m→\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# flush_tty_input — discard keystrokes queued on the terminal, if there is one. Anything typed
# while bootstrap was busy (the Xcode dialog wait, say) would otherwise answer install.sh's first
# prompt. bash 3.2's `read -t` cannot poll (0 blocks, fractions are rejected), so use tcflush
# via perl, which both macOS and Ubuntu ship.
flush_tty_input() {
  ( exec < /dev/tty ) 2>/dev/null || return 0
  perl -e 'use POSIX qw(tcflush TCIFLUSH); tcflush(0, TCIFLUSH)' < /dev/tty 2>/dev/null || true
}

os=""
case "$(uname -s)" in
  Darwin) os=macos ;;
  Linux)  if grep -qiE '^(ID|ID_LIKE)=.*(ubuntu|debian)' /etc/os-release 2>/dev/null; then os=linux; fi ;;
esac
[[ -n "$os" ]] || fail "Unsupported OS. This installer supports macOS and Ubuntu."

# 1. Base prerequisites: enough to clone the repo.
if [[ "$os" == macos ]]; then
  if ! xcode-select -p >/dev/null 2>&1; then
    say "Installing Xcode Command Line Tools (accept the dialog; this waits for it)"
    xcode-select --install 2>/dev/null || true
    until xcode-select -p >/dev/null 2>&1; do sleep 15; done
  fi
else
  say "Installing git/curl via apt"
  sudo -v
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git curl ca-certificates
fi

# 2. Get the installer: local checkout wins, otherwise clone (HTTPS: no SSH key exists yet).
script_dir=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "$(dirname "${BASH_SOURCE[0]}")/install.sh" ]]; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [[ -n "$script_dir" ]]; then
  INSTALLER_DIR="$script_dir"
  say "Using local checkout $INSTALLER_DIR"
elif [[ -d "$INSTALLER_DIR/.git" ]]; then
  say "Updating $INSTALLER_DIR"
  git -C "$INSTALLER_DIR" fetch --quiet origin "$INSTALLER_REF"
  git -C "$INSTALLER_DIR" checkout --quiet "$INSTALLER_REF"
  git -C "$INSTALLER_DIR" pull --quiet --ff-only origin "$INSTALLER_REF" || true
else
  say "Cloning $INSTALLER_REPO ($INSTALLER_REF) into $INSTALLER_DIR"
  mkdir -p "$(dirname "$INSTALLER_DIR")"
  git clone --quiet --branch "$INSTALLER_REF" "$INSTALLER_REPO" "$INSTALLER_DIR"
fi

# 3. Linux: the full apt prerequisite list now that the repo is present.
if [[ "$os" == linux ]]; then
  say "Installing apt prerequisites from config/apt-packages.txt"
  # shellcheck disable=SC2046
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    $(grep -vE '^[[:space:]]*(#|$)' "$INSTALLER_DIR/config/apt-packages.txt" | tr '\n' ' ')
  # postgresql@15's initdb wants en_US.UTF-8; minimal images ship without any generated locale.
  if ! locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then
    say "Generating en_US.UTF-8 locale"
    sudo locale-gen en_US.UTF-8
  fi
fi

# 4. Homebrew.
if [[ "${BOOTSTRAP_SKIP_BREW:-0}" != 1 ]]; then
  read -ra brew_prefixes <<< "${BOOTSTRAP_BREW_PREFIXES:-/opt/homebrew /usr/local /home/linuxbrew/.linuxbrew}"
  brew_found=0
  for p in "${brew_prefixes[@]}"; do
    if [[ -x "$p/bin/brew" ]]; then eval "$("$p/bin/brew" shellenv)"; brew_found=1; break; fi
  done
  if [[ "$brew_found" == 0 ]]; then
    # The Homebrew installer needs sudo on macOS too (it creates and chowns /opt/homebrew) and,
    # under NONINTERACTIVE=1, checks with `sudo -n`, which never prompts: with no cached ticket it
    # aborts with "Need sudo access on macOS". Prime the ticket first; sudo prompts on /dev/tty, so
    # this works even when stdin is the curl pipe.
    say "Installing Homebrew (its installer needs sudo; enter your password if asked)"
    sudo -v || fail "sudo is required to install Homebrew; $(id -un) must be an Administrator"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    for p in "${brew_prefixes[@]}"; do
      if [[ -x "$p/bin/brew" ]]; then eval "$("$p/bin/brew" shellenv)"; break; fi
    done
  fi
fi

# 5. Hand off. When piped through curl, stdin is the script itself, so reattach the terminal
#    for the interactive prompts (gh login, secrets) if one exists, after dropping any
#    keystrokes typed while waiting.
say "Running install.sh $*"
flush_tty_input
if [[ ! -t 0 ]] && ( exec < /dev/tty ) 2>/dev/null; then
  exec "$INSTALLER_DIR/install.sh" "$@" < /dev/tty
else
  exec "$INSTALLER_DIR/install.sh" "$@"
fi
