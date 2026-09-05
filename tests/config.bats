#!/usr/bin/env bats

setup() { load test_helper; }

@test "versions.env sets every pin under set -u" {
  run bash -euo pipefail -c "source '$WI_ROOT/config/versions.env'; printf '%s|%s|%s|%s|%s|%s|%s' \"\$JAVA_VERSIONS\" \"\$GRADLE_VERSION\" \"\$NODE_VERSION\" \"\$PYTHON_VERSION\" \"\$TERRAFORM_VERSION\" \"\$RUST_TARGET\" \"\$WORKSPACE_DIR\""
  [ "$status" -eq 0 ]
  [ "$output" = "25.0.3-amzn 21.0.9-amzn|9.6.1|24.18.0|3.10.11|1.15.8|x86_64-unknown-linux-musl|$HOME/Development/Workspaces/skoolscout" ]
}

@test "repos.txt.example lines are '<git url> <branch>' pairs" {
  f="$WI_ROOT/config/repos.txt.example"
  while read -r url branch extra; do
    [[ "$url" == git@*:*/*.git || "$url" == https://*/*.git ]]
    [ -n "$branch" ]
    [ -z "$extra" ]
  done < <(grep -vE '^[[:space:]]*(#|$)' "$f")
  [ "$(grep -cvE '^[[:space:]]*(#|$)' "$f")" -ge 1 ]
}

@test "repos.txt itself is git-ignored" {
  git -C "$WI_ROOT" check-ignore -q config/repos.txt
}

@test "claude-plugins.txt lines are 'marketplace REPO' or 'plugin NAME@MARKET'" {
  while read -r kind value; do
    case "$kind" in
      marketplace) [[ "$value" == */* ]] ;;
      plugin) [[ "$value" == *@* ]] ;;
      *) return 1 ;;
    esac
  done < <(grep -vE '^[[:space:]]*(#|$)' "$WI_ROOT/config/claude-plugins.txt")
  [ "$(grep -c '^plugin ' "$WI_ROOT/config/claude-plugins.txt")" -ge 2 ]
}

@test "secrets.env.example has names but no values" {
  # a value would be a non-blank, non-comment character right after '='
  run grep -E '^[A-Z_]+=[^[:space:]#]' "$WI_ROOT/config/secrets.env.example"
  [ "$status" -eq 1 ]
  grep -q '^GITHUB_TOKEN=' "$WI_ROOT/config/secrets.env.example"
  grep -q '^FONTAWESOME_PACKAGE_TOKEN=' "$WI_ROOT/config/secrets.env.example"
  grep -q '^LOCALSTACK_AUTH_TOKEN=' "$WI_ROOT/config/secrets.env.example"
}

@test "Brewfiles parse when brew is available" {
  command -v brew >/dev/null || skip "no brew"
  for f in Brewfile.common Brewfile.macos Brewfile.linux; do
    run brew bundle list --all --file="$WI_ROOT/$f"
    [ "$status" -eq 0 ]
  done
}
