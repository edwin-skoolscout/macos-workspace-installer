#!/usr/bin/env bash
# lib/node-tool.sh — shared by the top-level wrappers around tools/* (clone-repos.sh, ...):
# find Node (PATH, else nvm's default as set up by the node step), install the workspaces'
# dependencies once, then run tools/<name>/src/main.mts, which Node 24 executes directly.
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/node-tool.sh"
#   run_node_tool clone-repos "$@"

# run_node_tool NAME ARGS... — run tools/NAME with ARGS. Not exec: a plain call keeps test stubs
# (exported functions) reachable.
run_node_tool() {
  local tool="$1"; shift
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

  if ! command -v node >/dev/null 2>&1; then
    local p
    for p in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew; do
      if [[ -s "$p/opt/nvm/nvm.sh" ]]; then
        export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
        set +u
        # shellcheck source=/dev/null
        source "$p/opt/nvm/nvm.sh"
        nvm use default >/dev/null 2>&1 || true
        set -u
        break
      fi
    done
  fi
  command -v node >/dev/null 2>&1 || { echo "node not found; run ./install.sh --only brew-bundle,node first" >&2; return 1; }

  if [[ ! -d "$root/node_modules" ]]; then
    echo "→ installing tool dependencies (first run only)"
    (cd "$root" && npm ci --omit=dev --no-fund --no-audit)
  fi

  node "$root/tools/$tool/src/main.mts" "$@"
}
