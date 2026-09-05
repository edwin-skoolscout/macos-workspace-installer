#!/usr/bin/env bats

setup() {
  load test_helper
  export WI_SECRETS_FILE="$BATS_TEST_TMPDIR/secrets.env"
}

@test "--help exits 0" {
  run "$WI_ROOT/doctor.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--skip"* ]]
}

@test "runs to completion and prints a result line" {
  run "$WI_ROOT/doctor.sh" --skip github-auth,clone-repos,local-dev-wiring
  [ "$status" -le 1 ]
  [[ "$output" == *"passed"*"warnings"*"failed"* ]]
}

@test "skipped sections do not appear" {
  run "$WI_ROOT/doctor.sh" --skip github-auth,clone-repos,local-dev-wiring
  [[ "$output" != *"━━━ GitHub"* ]]
  [[ "$output" != *"━━━ Repos"* ]]
}

@test "a missing repos file is a warning, not a failure" {
  export WI_REPOS_FILE="$BATS_TEST_TMPDIR/no-repos.txt"
  run "$WI_ROOT/doctor.sh" --skip github-auth,local-dev-wiring
  [[ "$output" == *"⚠ no repos file"* ]]
  [[ "$output" == *"repos.txt.example"* ]]
}

@test "reports a missing secrets file as a failure" {
  run "$WI_ROOT/doctor.sh" --skip clone-repos,local-dev-wiring
  [[ "$output" == *"secrets file missing"* ]]
}
