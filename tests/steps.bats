#!/usr/bin/env bats
# Every real step must load cleanly and honour the step contract.

setup() {
  load test_helper
  export WI_OS=macos WI_ARCH=arm64 WI_DRY_RUN=1 WI_YES=1
  export WI_SECRETS_FILE="$BATS_TEST_TMPDIR/secrets.env"
  export WI_HOSTS_FILE="$BATS_TEST_TMPDIR/hosts"
  # shellcheck source=/dev/null
  source "$WI_ROOT/config/versions.env"
  export JAVA_VERSIONS GRADLE_VERSION NODE_VERSION PYTHON_VERSION TERRAFORM_VERSION RUST_TARGET WORKSPACE_DIR
}

@test "there is at least one real step" {
  ls "$WI_ROOT"/steps/[0-9][0-9]-*.sh
}

@test "every step defines the contract" {
  for step in "$WI_ROOT"/steps/[0-9][0-9]-*.sh; do
    run bash -euo pipefail -c "
      source '$WI_ROOT/lib/common.sh'
      source '$step'
      [[ \"\$STEP_OS\" =~ ^(all|macos|linux)$ ]] || { echo 'bad STEP_OS'; exit 1; }
      [[ \"\$STEP_SUDO\" =~ ^(yes|no|linux)$ ]] || { echo 'bad STEP_SUDO'; exit 1; }
      [[ -n \"\$STEP_DESC\" ]] || { echo 'empty STEP_DESC'; exit 1; }
      declare -F step_check >/dev/null || { echo 'no step_check'; exit 1; }
      declare -F step_run   >/dev/null || { echo 'no step_run'; exit 1; }
    "
    [ "$status" -eq 0 ] || { echo "$step: $output"; return 1; }
  done
}

@test "install.sh --list loads every real step" {
  run "$WI_ROOT/install.sh" --list
  [ "$status" -eq 0 ]
  for step in "$WI_ROOT"/steps/[0-9][0-9]-*.sh; do
    name="$(basename "$step" .sh)"; name="${name#[0-9][0-9]-}"
    [[ "$output" == *"$name"* ]]
  done
}

@test "brew-bundle extracts tap names from a Brewfile" {
  # shellcheck source=/dev/null
  source "$WI_ROOT/lib/common.sh"
  # shellcheck source=/dev/null
  source "$WI_ROOT/steps/20-brew-bundle.sh"
  run brewfile_taps "$WI_ROOT/Brewfile.macos"
  [ "$output" = "stripe/stripe-cli" ]
  run brewfile_taps "$WI_ROOT/Brewfile.common"
  [ -z "$output" ]
}

@test "the homebrew step declares sudo on every OS" {
  # Its installer needs sudo on macOS as well (it creates /opt/homebrew), so install.sh must
  # prime the ticket before the step runs `NONINTERACTIVE=1` install.sh, which uses `sudo -n`.
  run "$WI_ROOT/install.sh" --list
  [ "$status" -eq 0 ]
  grep -qE '^homebrew +os=all +sudo=yes ' <<< "$output"
}
