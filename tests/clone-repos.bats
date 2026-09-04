#!/usr/bin/env bats

setup() {
  load test_helper
  load_lib common
  export WI_OS=macos WI_ARCH=arm64 WI_DRY_RUN=1
  export WORKSPACE_DIR="$BATS_TEST_TMPDIR/ws"
  # shellcheck source=/dev/null
  source "$WI_ROOT/steps/70-clone-repos.sh"
}

@test "repo_dir_for_url strips .git and joins with WORKSPACE_DIR" {
  [ "$(repo_dir_for_url git@github.com:skoolscout/skoolscout-com.git)" = "$WORKSPACE_DIR/skoolscout-com" ]
}

@test "step_check fails when repos are absent" {
  ! step_check
}

@test "dry-run step_run prints clone commands for every repo and touches nothing" {
  run step_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"git clone --branch develop --recurse-submodules git@github.com:skoolscout/skoolscout-com.git"* ]]
  [[ "$output" == *"jefelabs-docs.git"* ]]
  [ ! -d "$WORKSPACE_DIR/skoolscout-com" ]
}
