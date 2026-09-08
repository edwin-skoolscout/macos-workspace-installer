#!/usr/bin/env bats

setup() {
  load test_helper
  load_lib shell-block
}

@test "zsh block loads brew, sdkman, nvm, pyenv, direnv, paths and secrets" {
  run shell_block_render zsh /opt/homebrew "$HOME/Development/Workspaces"
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
  run shell_block_render bash /home/linuxbrew/.linuxbrew "$HOME/Development/Workspaces"
  [[ "$output" == *'/home/linuxbrew/.linuxbrew/bin/brew shellenv'* ]]
  [[ "$output" == *'direnv hook bash'* ]]
}

@test "rendered block is syntactically valid bash" {
  shell_block_render zsh /opt/homebrew "$HOME/Development/Workspaces" > "$BATS_TEST_TMPDIR/block.sh"
  bash -n "$BATS_TEST_TMPDIR/block.sh"
}

# Sourcing the block runs brew/sdkman/etc; a scratch HOME and stderr to /dev/null keep those inert.
# Aliases only expand in text parsed after they are defined, hence the eval.
source_block_and_run() {   # WORKSPACE COMMAND
  shell_block_render bash /opt/homebrew "$1" > "$BATS_TEST_TMPDIR/block.sh"
  HOME="$BATS_TEST_TMPDIR/home" bash -c 'shopt -s expand_aliases; source "$1" 2>/dev/null; eval "$2"' _ "$BATS_TEST_TMPDIR/block.sh" "$2"
}

@test "block defines a cd alias named after every <owner>/<repo> in the workspace" {
  ws="$BATS_TEST_TMPDIR/ws"
  mkdir -p "$ws/skoolscout/skoolscout-com" "$ws/ecruz165/agentx" "$BATS_TEST_TMPDIR/home"
  run source_block_and_run "$ws" 'skoolscout-com && pwd && agentx && pwd'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$ws/skoolscout/skoolscout-com"* ]]
  [[ "$output" == *"$ws/ecruz165/agentx"* ]]
}

@test "block sources cleanly before the workspace exists and defines no repo aliases" {
  mkdir -p "$BATS_TEST_TMPDIR/home"
  run source_block_and_run "$BATS_TEST_TMPDIR/missing" 'alias | grep -c "cd " || true'
  [ "$status" -eq 0 ]
  [[ "$output" == *"0"* ]]
}

@test "block defines an agent alias that launches claude with permission checks bypassed" {
  mkdir -p "$BATS_TEST_TMPDIR/home"
  run source_block_and_run "$BATS_TEST_TMPDIR/missing" 'alias agent'
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude --dangerously-skip-permissions"* ]]
}
