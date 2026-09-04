#!/usr/bin/env bats

setup() {
  load test_helper
  load_lib managed-block
  f="$BATS_TEST_TMPDIR/rc"
}

@test "creates the file and block when the file is missing" {
  managed_block_write "$f" 'export A=1'
  run managed_block_read "$f"
  [ "$status" -eq 0 ]
  [ "$output" = 'export A=1' ]
}

@test "appends the block after existing content" {
  printf 'alias ll="ls -l"\n' > "$f"
  managed_block_write "$f" 'export A=1'
  [ "$(head -n1 "$f")" = 'alias ll="ls -l"' ]
  run managed_block_read "$f"
  [ "$output" = 'export A=1' ]
}

@test "replaces the block in place, leaving surroundings intact" {
  printf 'before\n%s\nold\n%s\nafter\n' "$WI_BLOCK_BEGIN" "$WI_BLOCK_END" > "$f"
  managed_block_write "$f" 'new'
  expected="$(printf 'before\n%s\nnew\n%s\nafter' "$WI_BLOCK_BEGIN" "$WI_BLOCK_END")"
  [ "$(cat "$f")" = "$expected" ]
}

@test "writing twice yields exactly one block" {
  managed_block_write "$f" 'x'
  managed_block_write "$f" 'x'
  [ "$(grep -cF "$WI_BLOCK_BEGIN" "$f")" -eq 1 ]
}

@test "matches reports equality and difference" {
  managed_block_write "$f" 'x'
  managed_block_matches "$f" 'x'
  ! managed_block_matches "$f" 'y'
}

@test "read fails when there is no block" {
  : > "$f"
  run managed_block_read "$f"
  [ "$status" -eq 1 ]
}

@test "a multi-line body with shell syntax round-trips unchanged" {
  body=$'line1\nexport P="$(brew --prefix)/bin:$PATH"\n[ -f x ] && source x'
  managed_block_write "$f" "$body"
  run managed_block_read "$f"
  [ "$output" = "$body" ]
}
