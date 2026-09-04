#!/usr/bin/env bash
# lib/managed-block.sh — keep exactly one marked block in an rc file, idempotently.
# The body is passed to awk through the environment so backslashes survive.

[[ -n "${_WI_MANAGED_BLOCK_LOADED:-}" ]] && return 0
_WI_MANAGED_BLOCK_LOADED=1

WI_BLOCK_BEGIN='# >>> workspace-installer >>>'
WI_BLOCK_END='# <<< workspace-installer <<<'

# managed_block_read FILE — print the block body (without markers); 1 if none
managed_block_read() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  awk -v begin="$WI_BLOCK_BEGIN" -v end="$WI_BLOCK_END" '
    $0 == begin { inside = 1; found = 1; next }
    $0 == end   { inside = 0; next }
    inside      { print }
    END         { exit found ? 0 : 1 }
  ' "$file"
}

# managed_block_write FILE BODY — replace the block in place, or append one
managed_block_write() {
  local file="$1" body="$2" tmp
  mkdir -p "$(dirname "$file")"
  [[ -f "$file" ]] || : > "$file"
  tmp="$(mktemp)"
  WI_BLOCK_BODY="$body" awk -v begin="$WI_BLOCK_BEGIN" -v end="$WI_BLOCK_END" '
    function emit() { print begin; print ENVIRON["WI_BLOCK_BODY"]; print end }
    $0 == begin           { emit(); skipping = 1; found = 1; next }
    $0 == end && skipping { skipping = 0; next }
    !skipping             { print }
    END                   { if (!found) emit() }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"   # cat, not mv: keeps the rc file's owner and mode
  rm -f "$tmp"
}

# managed_block_matches FILE BODY — 0 if the block exists and equals BODY
managed_block_matches() {
  local current
  current="$(managed_block_read "$1")" || return 1
  [[ "$current" == "$2" ]]
}
