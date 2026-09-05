#!/usr/bin/env bats

setup() {
  load test_helper
  load_lib shell-block
}

@test "zsh block loads brew, sdkman, nvm, pyenv, direnv, paths and secrets" {
  run shell_block_render zsh /opt/homebrew
  [ "$status" -eq 0 ]
  [[ "$output" == *'eval "$(/opt/homebrew/bin/brew shellenv)"'* ]]
  [[ "$output" == *'sdkman-init.sh'* ]]
  [[ "$output" == *'/opt/homebrew/opt/nvm/nvm.sh'* ]]
  [[ "$output" == *'pyenv init -'* ]]
  [[ "$output" == *'direnv hook zsh'* ]]
  [[ "$output" == *'/opt/homebrew/opt/rustup/bin'* ]]
  [[ "$output" == *'/opt/homebrew/opt/libpq/bin'* ]]
  [[ "$output" == *'.config/skoolscout/secrets.env'* ]]
  [[ "$output" != *'DOCKER_HOST'* ]]
}

@test "bash block uses the linuxbrew prefix and the bash direnv hook" {
  run shell_block_render bash /home/linuxbrew/.linuxbrew
  [[ "$output" == *'/home/linuxbrew/.linuxbrew/bin/brew shellenv'* ]]
  [[ "$output" == *'direnv hook bash'* ]]
}

@test "rendered block is syntactically valid bash" {
  shell_block_render zsh /opt/homebrew > "$BATS_TEST_TMPDIR/block.sh"
  bash -n "$BATS_TEST_TMPDIR/block.sh"
}
