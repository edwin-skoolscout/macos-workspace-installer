#!/usr/bin/env bats

setup() {
  load test_helper
  load_lib secrets
  example="$WI_ROOT/config/secrets.env.example"
  f="$BATS_TEST_TMPDIR/secrets.env"
}

@test "secrets_names lists the keys from the example file" {
  run secrets_names "$example"
  [ "$output" = $'GITHUB_TOKEN\nFONTAWESOME_PACKAGE_TOKEN\nLOCALSTACK_AUTH_TOKEN' ]
}

@test "secrets_write then secrets_get round-trips awkward values, mode 600" {
  secrets_write "$f" "GITHUB_TOKEN=ghp_abc" "FONTAWESOME_PACKAGE_TOKEN=a b'c\$d" "LOCALSTACK_AUTH_TOKEN="
  [ "$(secrets_get "$f" GITHUB_TOKEN)" = ghp_abc ]
  [ "$(secrets_get "$f" FONTAWESOME_PACKAGE_TOKEN)" = "a b'c\$d" ]
  [ -z "$(secrets_get "$f" LOCALSTACK_AUTH_TOKEN)" ]
  [ "$(stat -f %Lp "$f" 2>/dev/null || stat -c %a "$f")" = 600 ]
}

@test "secrets_get on a missing file is empty, not an error" {
  [ -z "$(secrets_get "$BATS_TEST_TMPDIR/nope" GITHUB_TOKEN)" ]
}

@test "secrets_missing names empty keys only" {
  secrets_write "$f" "GITHUB_TOKEN=x" "FONTAWESOME_PACKAGE_TOKEN=" "LOCALSTACK_AUTH_TOKEN="
  run secrets_missing "$f" "$example"
  [ "$output" = $'FONTAWESOME_PACKAGE_TOKEN\nLOCALSTACK_AUTH_TOKEN' ]
}

@test "maven_settings_render uses the env token, not a literal" {
  run maven_settings_render edwin
  [[ "$output" == *'<id>github</id>'* ]]
  [[ "$output" == *'<username>edwin</username>'* ]]
  [[ "$output" == *'<password>${env.GITHUB_TOKEN}</password>'* ]]
}
