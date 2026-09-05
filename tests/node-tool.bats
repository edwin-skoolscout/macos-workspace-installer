#!/usr/bin/env bats
# The bash wrappers around tools/*: lib/node-tool.sh finds Node, installs deps once, runs the tool.

setup() {
  load test_helper
  # A stand-in checkout: the wrapper plus the file it execs, no node_modules.
  root="$BATS_TEST_TMPDIR/checkout"
  mkdir -p "$root/tools/clone-repos/src"
  mkdir -p "$root/lib"
  cp "$WI_ROOT/clone-repos.sh" "$WI_ROOT/create-database.sh" "$root/"
  cp "$WI_ROOT/lib/node-tool.sh" "$root/lib/"
  mkdir -p "$root/tools/create-database/src"
  : > "$root/tools/clone-repos/src/main.mts"
  : > "$root/tools/create-database/src/main.mts"
  : > "$root/package.json"
}

@test "clone-repos.sh execs node on the tool's main.mts with the arguments" {
  mkdir -p "$root/node_modules"
  run bash -c '
    node() { echo "node $*"; }; export -f node
    npm() { echo "npm $*"; }; export -f npm
    bash "$1" acme --all' _ "$root/clone-repos.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"node "*"/tools/clone-repos/src/main.mts acme --all"* ]]
  [[ "$output" != *"npm "* ]]
}

@test "clone-repos.sh installs dependencies first when node_modules is missing" {
  run bash -c '
    node() { echo "node $*"; }; export -f node
    npm() { echo "npm $*"; }; export -f npm
    bash "$1" acme' _ "$root/clone-repos.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"npm ci --omit=dev"*"node "*"main.mts acme"* ]]
}

@test "create-database.sh runs its own tool through the same wrapper logic" {
  mkdir -p "$root/node_modules"
  run bash -c '
    node() { echo "node $*"; }; export -f node
    bash "$1" create mydb --port 5440' _ "$root/create-database.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"node "*"/tools/create-database/src/main.mts create mydb --port 5440"* ]]
}
