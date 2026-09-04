#!/usr/bin/env bats

setup() {
  load test_helper
  load_lib shell-block
}

@test "macOS/zsh block loads brew, sdkman, nvm, pyenv, direnv, secrets and colima socket" {
  run shell_block_render macos zsh /opt/homebrew
  [ "$status" -eq 0 ]
  [[ "$output" == *'eval "$(/opt/homebrew/bin/brew shellenv)"'* ]]
  [[ "$output" == *'sdkman-init.sh'* ]]
  [[ "$output" == *'/opt/homebrew/opt/nvm/nvm.sh'* ]]
  [[ "$output" == *'pyenv init -'* ]]
  [[ "$output" == *'direnv hook zsh'* ]]
  [[ "$output" == *'/opt/homebrew/opt/rustup/bin'* ]]
  [[ "$output" == *'/opt/homebrew/opt/libpq/bin'* ]]
  [[ "$output" == *'.config/skoolscout/secrets.env'* ]]
  [[ "$output" == *'DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"'* ]]
  [[ "$output" == *'TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock'* ]]
}

@test "linux/bash block uses the linuxbrew prefix, bash hook and no colima socket" {
  run shell_block_render linux bash /home/linuxbrew/.linuxbrew
  [[ "$output" == *'/home/linuxbrew/.linuxbrew/bin/brew shellenv'* ]]
  [[ "$output" == *'direnv hook bash'* ]]
  [[ "$output" != *'DOCKER_HOST'* ]]
}

@test "rendered block is syntactically valid bash" {
  shell_block_render macos zsh /opt/homebrew > "$BATS_TEST_TMPDIR/block.sh"
  bash -n "$BATS_TEST_TMPDIR/block.sh"
}
