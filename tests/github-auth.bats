#!/usr/bin/env bats
# steps/60-github-auth.sh — one PAT in the secrets file drives gh, git-over-HTTPS and Maven.
# git is real (HOME is a temp dir, so --global config lands in the sandbox); gh is a stub that
# records its calls in $GH_LOG.

setup() {
  load test_helper
  load_lib common
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export WI_OS=macos WI_ARCH=arm64 WI_DRY_RUN=0 WI_YES=0
  export WI_SECRETS_FILE="$BATS_TEST_TMPDIR/secrets.env"
  export WORKSPACE_DIR="$BATS_TEST_TMPDIR/ws"
  export WI_REPOS_FILE="$BATS_TEST_TMPDIR/repos.txt"
  printf 'git@github.com:acme/app.git develop\n' > "$WI_REPOS_FILE"
  printf 'GITHUB_TOKEN=ghp_test\nFONTAWESOME_PACKAGE_TOKEN=fa\nLOCALSTACK_AUTH_TOKEN=ls\n' > "$WI_SECRETS_FILE"
  export GH_LOG="$BATS_TEST_TMPDIR/gh.log"
  : > "$GH_LOG"
  load_brew() { return 0; }
  # shellcheck source=/dev/null
  source "$WI_ROOT/steps/60-github-auth.sh"
}

# gh stub: logged in, `setup-git` installs the credential helper the way the real one does,
# `api repos/...` answers with the SAML refusal when GH_SAML is set.
gh() {
  echo "gh $*" >> "$GH_LOG"
  case "$1 $2" in
    "auth status") return 0 ;;
    "auth login") return 0 ;;
    "auth setup-git") git config --global --add credential.https://github.com.helper '!/usr/local/bin/gh auth git-credential' ;;
    "api user") echo edwin ;;
    "api repos/"*)
      if [[ -n "${GH_SAML:-}" ]]; then
        echo "gh: Resource protected by organization SAML enforcement. You must grant your Personal Access token access to this organization. (HTTP 403)" >&2
        return 1
      fi
      echo "${2#repos/}" ;;
    *) return 0 ;;
  esac
}

@test "step_check fails until gh is git's credential helper and git@github.com: URLs are rewritten" {
  mkdir -p "$HOME/.m2"; printf '<servers><server><id>github</id></server></servers>' > "$HOME/.m2/settings.xml"
  ! step_check
  git config --global --add credential.https://github.com.helper '!/usr/local/bin/gh auth git-credential'
  ! step_check
  git config --global url."https://github.com/".insteadOf "git@github.com:"
  step_check
}

@test "step_run wires git to clone over HTTPS with gh's credentials" {
  run step_run
  [ "$status" -eq 0 ]
  git config --global --get-all credential.https://github.com.helper | grep -q 'gh auth git-credential'
  [ "$(git config --global --get url.https://github.com/.insteadof)" = "git@github.com:" ]
}

@test "a token in the secrets file is the login: step_run never opens the web login" {
  run step_run
  [ "$status" -eq 0 ]
  ! grep -q 'gh auth login' "$GH_LOG"
  grep -q 'gh auth setup-git' "$GH_LOG"
}

@test "step_run stops with the Configure SSO hint when the org enforces SAML" {
  export GH_SAML=1
  run step_run
  [ "$status" -ne 0 ]
  [[ "$output" == *"SAML"* ]]
  [[ "$output" == *"Configure SSO"* ]]
  [[ "$output" == *"acme/app"* ]]
}

@test "step_run never mentions SSH keys" {
  run step_run
  [[ "$output" != *"ssh"* ]]
  [ ! -e "$HOME/.ssh" ]
}

@test "dry-run step_run prints the git wiring and writes nothing" {
  export WI_DRY_RUN=1
  run step_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh auth setup-git"* ]]
  [[ "$output" == *"insteadOf"* ]]
  [ ! -f "$HOME/.gitconfig" ]
  [ ! -f "$HOME/.m2/settings.xml" ]
}
