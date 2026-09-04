#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
# steps/44-rust.sh — stable Rust + the musl target the Lambda scrapers build for.
# brew's rustup formula is keg-only, so it is addressed by full path.
STEP_DESC="rustup: stable toolchain + ${RUST_TARGET} (macOS also musl-cross)"
STEP_OS="all"
STEP_SUDO="no"

rustup_bin() {
  if command_exists rustup; then command -v rustup; return 0; fi
  load_brew || return 1
  local p
  p="$(brew --prefix rustup 2>/dev/null)/bin/rustup"
  [[ -x "$p" ]] || return 1
  echo "$p"
}

step_check() {
  local r
  r="$(rustup_bin)" || return 1
  [[ -x "$HOME/.cargo/bin/cargo" ]] || return 1
  "$r" target list --installed 2>/dev/null | grep -qx "$RUST_TARGET" || return 1
  if [[ "$WI_OS" == macos ]]; then command_exists x86_64-linux-musl-gcc || return 1; fi
  return 0
}

step_run() {
  local r
  r="$(rustup_bin)" || { [[ "$WI_DRY_RUN" == 1 ]] && return 0; die "rustup not installed (brew-bundle step)"; }
  export RUSTUP_INIT_SKIP_PATH_CHECK=yes
  wi_run "$r" default stable
  wi_run "$r" target add "$RUST_TARGET"
  if [[ "$WI_OS" == macos ]] && ! command_exists x86_64-linux-musl-gcc; then
    log_warn "Installing musl-cross (compiles a cross toolchain; this can take a long time)"
    brew_trust_tap filosottile/musl-cross
    wi_run brew install filosottile/musl-cross/musl-cross
  fi
}
