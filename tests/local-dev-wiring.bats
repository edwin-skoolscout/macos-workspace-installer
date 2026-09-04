#!/usr/bin/env bats

setup() {
  load test_helper
  load_lib common
  export WI_OS=macos WI_ARCH=arm64 WI_DRY_RUN=1
  export WI_HOSTS_FILE="$BATS_TEST_TMPDIR/hosts"
  # shellcheck source=/dev/null
  source "$WI_ROOT/steps/80-local-dev-wiring.sh"
}

@test "dev_hosts lists the five hosts from config" {
  run dev_hosts
  [ "${#lines[@]}" -eq 5 ]
  [[ "$output" == *skoolscout.com.local* ]]
}

@test "host_present matches whole hostnames and ignores comments" {
  printf '127.0.0.1\tlocalhost\n127.0.0.1\tskoolscout.com.local\n# 127.0.0.1 demo-org.skoolscout.com.local\n' > "$WI_HOSTS_FILE"
  host_present skoolscout.com.local
  ! host_present demo-org.skoolscout.com.local
  ! host_present scout.com.local
}

@test "dry-run step_run prints what it would append without touching the file" {
  printf '127.0.0.1\tlocalhost\n' > "$WI_HOSTS_FILE"
  run step_run
  [[ "$output" == *"append 127.0.0.1 skoolscout.com.local"* ]]
  [ "$(wc -l < "$WI_HOSTS_FILE")" -eq 1 ]
}
