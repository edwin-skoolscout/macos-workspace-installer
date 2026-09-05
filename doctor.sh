#!/usr/bin/env bash
# doctor.sh — verify the machine against config/versions.env and the spec's checks.
# Exit 0 only when nothing FAILed. Warnings do not fail.
set -uo pipefail

WI_ROOT="${WI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export WI_ROOT
# shellcheck source=lib/common.sh
source "$WI_ROOT/lib/common.sh"
# shellcheck source=lib/versions.sh
source "$WI_ROOT/lib/versions.sh"
# shellcheck source=lib/verdict.sh
source "$WI_ROOT/lib/verdict.sh"
# shellcheck source=lib/secrets.sh
source "$WI_ROOT/lib/secrets.sh"
# shellcheck source=config/versions.env
source "$WI_ROOT/config/versions.env"

SKIP=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip)   SKIP="$2"; shift 2 ;;
    --skip=*) SKIP="${1#*=}"; shift ;;
    -h|--help) echo "Usage: doctor.sh [--skip github-auth,clone-repos,local-dev-wiring]"; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done
skipped() { in_csv "$1" "$SKIP"; }

WI_OS="$(detect_os)"

# Reproduce what the managed shell block gives a fresh shell.
load_brew || true
export SDKMAN_DIR="${SDKMAN_DIR:-$HOME/.sdkman}"
if [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]]; then
  set +u
  # shellcheck source=/dev/null
  source "$SDKMAN_DIR/bin/sdkman-init.sh"
  set -u
fi
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if command_exists brew && [[ -s "$(brew --prefix nvm 2>/dev/null)/nvm.sh" ]]; then
  set +u
  # shellcheck source=/dev/null
  source "$(brew --prefix nvm)/nvm.sh"
  set -u
fi
export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
if command_exists pyenv; then eval "$(pyenv init -)"; fi
PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
if command_exists brew; then
  PATH="$(brew --prefix rustup 2>/dev/null)/bin:$(brew --prefix libpq 2>/dev/null)/bin:$PATH"
fi
export PATH
load_secrets 2>/dev/null || true

PASS=0; WARN=0; FAIL=0
# report STATUS MESSAGE [DETAIL]
report() {
  local detail="${3:-}"
  case "$1" in
    PASS) PASS=$((PASS + 1)); printf '  %s✓%s %s\n' "$C_OK" "$C_RESET" "$2" ;;
    WARN) WARN=$((WARN + 1)); printf '  %s⚠%s %s%s\n' "$C_WARN" "$C_RESET" "$2" "${detail:+ — $detail}" ;;
    FAIL) FAIL=$((FAIL + 1)); printf '  %s✗%s %s%s\n' "$C_ERR" "$C_RESET" "$2" "${detail:+ — $detail}" ;;
  esac
}
check_cmd() {
  if command_exists "$1"; then report PASS "$1"; else report FAIL "$1 missing"; fi
}
# check_version NAME EXPECTED ACTUAL_TEXT
check_version() {
  local actual
  actual="$(version_extract "$3")"
  report "$(doctor_verdict "$2" "$actual")" "$1 $2" "found ${actual:-none}"
}

log_header "Tools"
for t in brew git gh jq direnv tmux nvim herdr mkcert aws awslocal tflocal localstack tfenv psql \
         node npm pnpm python3 pyenv java gradle terraform cargo rustup xmllint zip unzip \
         task-master dotenv ncu claude; do
  check_cmd "$t"
done
if [[ "$WI_OS" == macos ]]; then check_cmd stripe; fi

log_header "Versions"
for v in $JAVA_VERSIONS; do
  if [[ -x "$SDKMAN_DIR/candidates/java/$v/bin/java" ]]; then report PASS "java $v (sdkman)"; else report FAIL "java $v not installed via sdkman"; fi
done
if command_exists java; then check_version "java (default)" "$(version_extract "${JAVA_VERSIONS%% *}")" "$(java -version 2>&1)"; fi
if command_exists gradle; then check_version gradle "$GRADLE_VERSION" "$(gradle --version 2>/dev/null | grep -m1 '^Gradle')"; fi
if command_exists node; then check_version node "$NODE_VERSION" "$(node --version)"; fi
if command_exists python3; then check_version python "$PYTHON_VERSION" "$(python3 --version 2>&1)"; fi
if command_exists terraform; then check_version terraform "$TERRAFORM_VERSION" "$(terraform version 2>/dev/null | head -n1)"; fi
if command_exists rustup && rustup target list --installed 2>/dev/null | grep -qx "$RUST_TARGET"; then
  report PASS "rust target $RUST_TARGET"
else
  report FAIL "rust target $RUST_TARGET missing"
fi

log_header "Homebrew"
if command_exists brew; then
  if brew doctor >/dev/null 2>&1; then report PASS "brew doctor clean"; else report WARN "brew doctor reports issues" "run: brew doctor"; fi
fi

if ! skipped github-auth; then
  log_header "GitHub"
  if command_exists gh && gh auth status -h github.com >/dev/null 2>&1; then report PASS "gh logged in"; else report FAIL "gh not logged in" "gh auth login --git-protocol ssh"; fi
  if ssh -T -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new git@github.com 2>&1 | grep -q "successfully authenticated"; then
    report PASS "ssh to github.com"
  else
    report FAIL "ssh to github.com" "gh ssh-key add ~/.ssh/id_ed25519.pub"
  fi
  log_header "Secrets"
  if [[ -f "$WI_SECRETS_FILE" ]]; then
    missing="$(secrets_missing "$WI_SECRETS_FILE" "$WI_ROOT/config/secrets.env.example" | tr '\n' ' ')"
    if [[ -z "$missing" ]]; then report PASS "all secrets set"; else report FAIL "missing secrets" "$missing"; fi
  else
    report FAIL "secrets file missing" "$WI_SECRETS_FILE"
  fi
  if grep -q '<id>github</id>' "$HOME/.m2/settings.xml" 2>/dev/null; then report PASS "maven settings.xml has github server"; else report FAIL "maven settings.xml lacks <server><id>github</id>"; fi
fi

if ! skipped clone-repos; then
  log_header "Repos"
  REPOS_FILE="${WI_REPOS_FILE:-$WI_ROOT/config/repos.txt}"
  if [[ -f "$REPOS_FILE" ]]; then
    while read -r url _; do
      dir="$WORKSPACE_DIR/$(basename "${url%.git}")"
      if [[ ! -d "$dir/.git" ]]; then report FAIL "$dir missing"
      elif git -C "$dir" submodule status --recursive 2>/dev/null | grep -q '^-'; then report WARN "$dir" "submodules not initialised"
      else report PASS "$dir"; fi
    done < <(grep -vE '^[[:space:]]*(#|$)' "$REPOS_FILE")
  else
    report WARN "no repos file" "copy config/repos.txt.example to config/repos.txt, then ./install.sh --only clone-repos"
  fi
fi

if ! skipped local-dev-wiring; then
  log_header "Local dev"
  while read -r h; do
    if grep -qE "^[^#]*[[:space:]]$h([[:space:]]|\$)" /etc/hosts; then report PASS "$h in /etc/hosts"; else report FAIL "$h not in /etc/hosts"; fi
  done < <(grep -vE '^[[:space:]]*(#|$)' "$WI_ROOT/config/dev-hosts.txt")
  if command_exists mkcert && [[ -f "$(mkcert -CAROOT)/rootCA.pem" ]]; then report PASS "mkcert CA present"; else report FAIL "mkcert CA missing" "mkcert -install"; fi
fi

log_header "Result"
printf '  %d passed, %d warnings, %d failed\n' "$PASS" "$WARN" "$FAIL"
[[ "$FAIL" -eq 0 ]]
