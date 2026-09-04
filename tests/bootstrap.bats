#!/usr/bin/env bats

setup() { load test_helper; }

@test "bootstrap.sh is self-contained (sources nothing from lib/)" {
  # only uncommented source/dot lines count
  ! grep -E '^[^#]*(source|\.) .*lib/' "$WI_ROOT/bootstrap.sh"
}

@test "bootstrap.sh refuses unsupported kernels" {
  run bash -c 'uname() { echo Plan9; }; export -f uname; bash "$1"' _ "$WI_ROOT/bootstrap.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported OS"* ]]
}

@test "bootstrap.sh uses a local checkout when run next to install.sh" {
  tmp="$BATS_TEST_TMPDIR/checkout"
  mkdir -p "$tmp"
  cp "$WI_ROOT/bootstrap.sh" "$tmp/"
  printf '#!/usr/bin/env bash\necho "install.sh called with: $*"\n' > "$tmp/install.sh"
  chmod +x "$tmp/install.sh"
  run bash -c '
    uname() { echo Darwin; }; export -f uname
    xcode-select() { return 0; }; export -f xcode-select
    export BOOTSTRAP_SKIP_BREW=1
    bash "$1" --list' _ "$tmp/bootstrap.sh"
  [[ "$output" == *"Using local checkout"* ]]
  [[ "$output" == *"install.sh called with: --list"* ]]
}
