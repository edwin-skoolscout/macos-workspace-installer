#!/usr/bin/env bats

setup() {
  load test_helper
  export WI_STEPS_DIR="$WI_ROOT/tests/fixtures/steps"
  export WI_FIXTURE_DIR="$BATS_TEST_TMPDIR"
  export WI_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

@test "--list prints every step with metadata and runs nothing" {
  run "$WI_ROOT/install.sh" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"*"os=all"*"sudo=no"* ]]
  [[ "$output" == *"gamma"*"os=plan9"* ]]
  [ ! -f "$WI_FIXTURE_DIR/alpha.done" ]
}

@test "unknown step names are rejected" {
  run "$WI_ROOT/install.sh" --only nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown step 'nope'"* ]]
}

@test "runs steps in order, continues past a failure, exits 1" {
  run "$WI_ROOT/install.sh"
  [ "$status" -eq 1 ]
  [ -f "$WI_FIXTURE_DIR/alpha.done" ]
  [ -f "$WI_FIXTURE_DIR/delta.done" ]
  [ ! -f "$WI_FIXTURE_DIR/gamma.done" ]
  [[ "$output" == *"alpha PASS"* ]]
  [[ "$output" == *"beta-fails FAIL"* ]]
  [[ "$output" == *"gamma SKIP (os)"* ]]
  [[ "$output" == *"delta PASS"* ]]
}

@test "--fail-fast stops after the first failure" {
  run "$WI_ROOT/install.sh" --fail-fast
  [ "$status" -eq 1 ]
  [ -f "$WI_FIXTURE_DIR/alpha.done" ]
  [ ! -f "$WI_FIXTURE_DIR/delta.done" ]
}

@test "--only runs just the named steps" {
  run "$WI_ROOT/install.sh" --only alpha,delta
  [ "$status" -eq 0 ]
  [[ "$output" == *"beta-fails SKIP (deselected)"* ]]
  [ -f "$WI_FIXTURE_DIR/delta.done" ]
}

@test "--skip removes steps" {
  run "$WI_ROOT/install.sh" --skip beta-fails,echo-env
  [ "$status" -eq 0 ]
}

@test "a satisfied step_check yields SKIP (done)" {
  touch "$WI_FIXTURE_DIR/alpha.done"
  run "$WI_ROOT/install.sh" --only alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha SKIP (done)"* ]]
}

@test "steps receive the exported environment and --dry-run/--yes flags" {
  run "$WI_ROOT/install.sh" --only echo-env --dry-run --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"WI_DRY_RUN=1 WI_YES=1 WI_OS="*" NODE_VERSION=24.18.0"* ]]
}

@test "every run writes a log file" {
  run "$WI_ROOT/install.sh" --only alpha
  ls "$WI_STATE_DIR"/install-*.log
}
