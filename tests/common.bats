#!/usr/bin/env bats

setup() {
  load test_helper
  load_lib common
}

@test "wi_run executes the command when not in dry-run" {
  WI_DRY_RUN=0
  wi_run touch "$BATS_TEST_TMPDIR/made"
  [ -f "$BATS_TEST_TMPDIR/made" ]
}

@test "wi_run prints but does not execute in dry-run" {
  WI_DRY_RUN=1
  run wi_run touch "$BATS_TEST_TMPDIR/not-made"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] touch"* ]]
  [ ! -f "$BATS_TEST_TMPDIR/not-made" ]
}

@test "wi_dry is true only in dry-run" {
  WI_DRY_RUN=1; wi_dry "would write"
  WI_DRY_RUN=0; ! wi_dry "would write"
}

@test "detect_os maps Darwin to macos" {
  uname() { echo Darwin; }
  [ "$(detect_os)" = macos ]
}

@test "detect_os maps unknown kernels to unsupported" {
  uname() { echo Plan9; }
  [ "$(detect_os)" = unsupported ]
}

@test "brew_prefix_for knows the three prefixes" {
  [ "$(brew_prefix_for macos arm64)" = /opt/homebrew ]
  [ "$(brew_prefix_for macos amd64)" = /usr/local ]
  [ "$(brew_prefix_for linux arm64)" = /home/linuxbrew/.linuxbrew ]
}

@test "rc_file_for_shell picks zprofile for zsh and bashrc for bash" {
  HOME=/h
  [ "$(rc_file_for_shell zsh)" = /h/.zprofile ]
  [ "$(rc_file_for_shell bash)" = /h/.bashrc ]
}

@test "in_csv matches whole items only" {
  in_csv b a,b,c
  ! in_csv d a,b,c
  ! in_csv a-b a,b
}

@test "confirm honours --yes with the default answer" {
  WI_YES=1
  confirm "go?" y
  ! confirm "go?" n
}

@test "load_secrets exports the file when present" {
  WI_SECRETS_FILE="$BATS_TEST_TMPDIR/secrets.env"
  printf 'GITHUB_TOKEN=abc\n' > "$WI_SECRETS_FILE"
  load_secrets
  [ "$GITHUB_TOKEN" = abc ]
}
