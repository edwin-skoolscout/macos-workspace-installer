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

# run_bootstrap_darwin_without_brew — bootstrap from a local checkout on a stubbed Darwin
# whose Homebrew prefix list points nowhere, so the install-Homebrew branch runs. sudo and
# curl are stubbed: the "installer" curl returns is a one-line echo.
run_bootstrap_darwin_without_brew() {
  tmp="$BATS_TEST_TMPDIR/checkout"
  mkdir -p "$tmp"
  cp "$WI_ROOT/bootstrap.sh" "$tmp/"
  printf '#!/usr/bin/env bash\necho "install.sh called"\n' > "$tmp/install.sh"
  chmod +x "$tmp/install.sh"
  run bash -c '
    uname() { echo Darwin; }; export -f uname
    xcode-select() { return 0; }; export -f xcode-select
    sudo() { echo "sudo $*"; }; export -f sudo
    curl() { echo "echo homebrew installer ran"; }; export -f curl
    export BOOTSTRAP_BREW_PREFIXES=/nonexistent-brew-prefix
    bash "$1"' _ "$tmp/bootstrap.sh"
}

@test "bootstrap.sh runs the Homebrew installer when no prefix has brew" {
  run_bootstrap_darwin_without_brew
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installing Homebrew"*"homebrew installer ran"*"install.sh called"* ]]
}

@test "bootstrap.sh primes sudo before the NONINTERACTIVE Homebrew installer" {
  run_bootstrap_darwin_without_brew
  [ "$status" -eq 0 ]
  # Under NONINTERACTIVE=1 Homebrew's installer runs `sudo -n`, which never prompts and
  # aborts on macOS without a cached ticket, so `sudo -v` must come first.
  [[ "$output" == *"sudo -v"*"homebrew installer ran"* ]]
}
