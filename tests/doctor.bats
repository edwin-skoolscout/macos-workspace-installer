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
  run "$WI_ROOT/doctor.sh" --skip docker,github-auth,clone-repos,local-dev-wiring
  [ "$status" -le 1 ]
  [[ "$output" == *"passed"*"warnings"*"failed"* ]]
}

@test "skipped sections do not appear" {
  run "$WI_ROOT/doctor.sh" --skip docker,github-auth,clone-repos,local-dev-wiring
  [[ "$output" != *"━━━ Docker"* ]]
  [[ "$output" != *"━━━ GitHub"* ]]
  [[ "$output" != *"━━━ Repos"* ]]
}

@test "reports a missing secrets file as a failure" {
  run "$WI_ROOT/doctor.sh" --skip docker,clone-repos,local-dev-wiring
  [[ "$output" == *"secrets file missing"* ]]
}
