#!/usr/bin/env bash
# clone-repos.sh — pick repos of a GitHub owner and clone them (tools/clone-repos, TypeScript).
#
#   ./clone-repos.sh skoolscout                       # type to search, tab to select, enter to clone
#   ./clone-repos.sh ecruz165 --filter agentx --all   # everything matching, no prompt
#   ./clone-repos.sh skoolscout --dry-run             # show what would happen
#
# Repos are recorded in config/repos.txt and cloned into WORKSPACE_DIR/<owner>/<repo>.
set -euo pipefail
# shellcheck source=lib/node-tool.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/node-tool.sh"
run_node_tool clone-repos "$@"
