#!/usr/bin/env bats

setup() {
  load test_helper
  load_lib common
  export WI_OS=macos WI_ARCH=arm64 WI_DRY_RUN=1
  export WORKSPACE_DIR="$BATS_TEST_TMPDIR/ws"
  export WI_REPOS_FILE="$BATS_TEST_TMPDIR/repos.txt"
  printf '# url branch\ngit@github.com:acme/app.git develop\ngit@github.com:acme/docs.git main\n' > "$WI_REPOS_FILE"
  # shellcheck source=/dev/null
  source "$WI_ROOT/steps/70-clone-repos.sh"
}

@test "repo_dir_for_url strips .git and joins with WORKSPACE_DIR" {
  [ "$(repo_dir_for_url git@github.com:acme/app.git)" = "$WORKSPACE_DIR/app" ]
}

@test "step_check fails when repos are absent" {
  ! step_check
}

@test "dry-run step_run prints clone commands for every repo and touches nothing" {
  run step_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"git clone --branch develop --recurse-submodules git@github.com:acme/app.git"* ]]
  [[ "$output" == *"git clone --branch main --recurse-submodules git@github.com:acme/docs.git"* ]]
  [ ! -d "$WORKSPACE_DIR/app" ]
}

@test "without a repos file under --yes the check fails and step_run explains how to create one" {
  rm "$WI_REPOS_FILE"
  export WI_YES=1
  ! step_check
  run step_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"repos.txt.example"* ]]
  [[ "$output" != *"git clone"* ]]
  [ ! -d "$WORKSPACE_DIR" ]
}

@test "an interactive run prompts for repos, writes the file and clones them" {
  rm "$WI_REPOS_FILE"
  export WI_YES=0 WI_DRY_RUN=0
  git() { echo "git $*"; }
  run step_run <<< $'git@github.com:acme/app.git\n\ngit@github.com:acme/docs.git\nrelease\n'
  [ "$status" -eq 0 ]
  [ -f "$WI_REPOS_FILE" ]
  grep -qx 'git@github.com:acme/app.git main' "$WI_REPOS_FILE"
  grep -qx 'git@github.com:acme/docs.git release' "$WI_REPOS_FILE"
  [[ "$output" == *"git clone --branch main --recurse-submodules git@github.com:acme/app.git"* ]]
  [[ "$output" == *"git clone --branch release --recurse-submodules git@github.com:acme/docs.git"* ]]
  [ -d "$WORKSPACE_DIR" ]
}

@test "an interactive dry run shows the repos it would write and writes nothing" {
  rm "$WI_REPOS_FILE"
  export WI_YES=0
  run step_run <<< $'git@github.com:acme/app.git\ndevelop\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] write $WI_REPOS_FILE"* ]]
  [[ "$output" == *"git@github.com:acme/app.git develop"* ]]
  [ ! -f "$WI_REPOS_FILE" ]
}

@test "entering no repos falls back to the hint" {
  rm "$WI_REPOS_FILE"
  export WI_YES=0
  run step_run < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"repos.txt.example"* ]]
  [ ! -f "$WI_REPOS_FILE" ]
}
