#!/usr/bin/env bats

setup() {
  load test_helper
  load_lib common
  export WI_OS=macos WI_ARCH=arm64 WI_DRY_RUN=1
  # shellcheck source=/dev/null
  source "$WI_ROOT/config/versions.env"
  # shellcheck source=/dev/null
  source "$WI_ROOT/steps/41-node.sh"
}

@test "npm_global_bin maps package names to their binaries" {
  [ "$(npm_global_bin task-master-ai)" = task-master ]
  [ "$(npm_global_bin dotenv-cli)" = dotenv ]
  [ "$(npm_global_bin npm-check-updates)" = ncu ]
  [ "$(npm_global_bin some-other-tool)" = some-other-tool ]
}

@test "npm_globals lists the configured packages without comments" {
  run npm_globals
  [[ "$output" == *task-master-ai* ]]
  [[ "$output" != *"#"* ]]
}
