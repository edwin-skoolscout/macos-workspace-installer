#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
# steps/90-project-deps.sh — npm/pnpm installs in the cloned repos + Playwright chromium.
# Needs the private-registry tokens from the secrets file; skips (with a warning) without them.
STEP_DESC="npm/pnpm install in cloned repos + Playwright chromium"
STEP_OS="all"
STEP_SUDO="linux"

SS="$WORKSPACE_DIR/skoolscout/skoolscout-com"
TENANTS="$WORKSPACE_DIR/skoolscout/skoolscout-com-tenants"
JL="$WORKSPACE_DIR/skoolscout/jefelabs-com"

playwright_cache() {
  if [[ "$WI_OS" == macos ]]; then echo "$HOME/Library/Caches/ms-playwright"; else echo "$HOME/.cache/ms-playwright"; fi
}

node_loaded() {
  load_brew || return 1
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  local nvm_sh
  nvm_sh="$(brew --prefix nvm 2>/dev/null)/nvm.sh"
  [[ -s "$nvm_sh" ]] || return 1
  set +u
  # shellcheck source=/dev/null
  source "$nvm_sh"
  nvm use "$NODE_VERSION" >/dev/null 2>&1
  set -u
  command_exists node
}

secrets_ok() {
  load_secrets 2>/dev/null || true
  [[ -n "${GITHUB_TOKEN:-}" && -n "${FONTAWESOME_PACKAGE_TOKEN:-}" ]]
}

step_check() {
  [[ -d "$SS/node_modules" && -d "$SS/app-ui/node_modules" && -d "$SS/app-test-e2e-runner/node_modules" ]] || return 1
  [[ -d "$TENANTS/node_modules" && -d "$JL/node_modules" ]] || return 1
  ls -d "$(playwright_cache)"/chromium-* >/dev/null 2>&1
}

step_run() {
  if ! secrets_ok; then
    log_warn "GITHUB_TOKEN / FONTAWESOME_PACKAGE_TOKEN not set; skipping project-deps. Re-run after: ./install.sh --only github-auth"
    return 0
  fi
  local d
  for d in "$SS" "$TENANTS" "$JL"; do
    if [[ ! -d "$d" ]]; then log_warn "$d missing; run the clone-repos step first"; return 0; fi
  done
  node_loaded || { [[ "$WI_DRY_RUN" == 1 ]] && return 0; die "Node $NODE_VERSION not available (node step)"; }
  if command_exists direnv; then wi_run direnv allow "$SS"; fi
  ( cd "$SS" && wi_run npm install --no-workspaces )
  ( cd "$SS/app-ui" && wi_run npm install )
  ( cd "$SS/app-test-e2e-runner" && wi_run npm install && wi_run npx playwright install --with-deps chromium )
  ( cd "$TENANTS" && wi_run npm install )
  ( cd "$JL" && wi_run pnpm install )
}
