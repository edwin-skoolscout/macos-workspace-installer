# VM Workspace Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A curl-pipeable, re-runnable installer that turns a fresh macOS or Ubuntu VM into a machine that can build, run and test skoolscout-com, jefelabs-com and their sibling repos.

**Architecture:** `bootstrap.sh` installs prerequisites + Homebrew and hands off to `install.sh`, which runs `steps/NN-name.sh` in order. Every step declares metadata plus `step_check` (already satisfied?) and `step_run` (do it), which makes re-runs cheap and safe. Small `lib/*.sh` files hold the logic worth unit-testing with bats; `doctor.sh` verifies the result.

**Tech Stack:** bash (must run on macOS's stock bash 3.2), Homebrew + Brewfiles, sdkman / nvm / pyenv / tfenv / rustup, bats-core + shellcheck for tests, Docker for the Ubuntu smoke test.

**Spec:** `docs/superpowers/specs/2026-09-04-vm-workspace-installer-design.md`

## Global Constraints

- All scripts run under **bash 3.2** (macOS `/bin/bash`): no `mapfile`, no associative arrays, no `${var,,}`, and guard empty-array expansion as `${arr[@]+"${arr[@]}"}`.
- `shellcheck -x` must report zero findings (`make lint`). Split `local x="$(cmd)"` into two lines (SC2155); use `if/else` rather than `a && b || c` (SC2015).
- Every step file defines `STEP_DESC`, `STEP_OS` (`all|macos|linux`), `STEP_SUDO` (`yes|no|linux`), `step_check()` and `step_run()`, and is safe to run twice. Its second line is `# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing` (the orchestrator reads those variables, so shellcheck would otherwise flag them unused).
- Mutating commands go through `wi_run` (honours `--dry-run`); non-command mutations (file writes) are guarded with `if wi_dry "message"; then return 0; fi`. (The spec calls this helper `run`; it is named `wi_run` here because bats defines its own `run`.)
- Version pins, copied verbatim from the spec: `JAVA_VERSIONS="25.0.3-amzn 21.0.9-amzn"`, `GRADLE_VERSION="9.6.1"`, `NODE_VERSION="24.18.0"`, `PYTHON_VERSION="3.10.11"`, `TERRAFORM_VERSION="1.15.8"`, `RUST_TARGET="x86_64-unknown-linux-musl"`, `WORKSPACE_DIR="$HOME/Development/Workspaces/skoolscout"`.
- No secret values anywhere in the repo. Secrets file: `~/.config/skoolscout/secrets.env`, mode 600.
- Postgres is installed but its service is never started by the installer (port 5432 belongs to the project's docker compose).
- Commit after every task. Commit messages end with:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01WLDvEJgJ9m1Ns7NqWnJ9uG
  ```
  Commit only the files the task names (`git commit -- <paths>`): the repo has unrelated `.idea/` files staged that must stay out of these commits.
- **Learning-mode checkpoint:** Task 3 creates `lib/verdict.sh` with a stubbed `doctor_verdict`. After Task 3 is committed, the orchestrator stops and hands that function to the user to implement before continuing. Later tasks work with the stub, so nothing blocks on it.

## File structure

| File | Responsibility |
|---|---|
| `bootstrap.sh` | Zero-dependency entry point: prerequisites, Homebrew, fetch repo, exec `install.sh` |
| `install.sh` | Parse flags, discover steps, run them in a subshell each, summarise |
| `doctor.sh` | Verify tools, versions, docker, GitHub, repos, secrets, hosts, mkcert |
| `lib/common.sh` | Logging, OS/arch detection, `wi_run`/`wi_dry`, `confirm`, `in_csv`, sudo keep-alive, rc-file lookup, `load_brew`, `load_secrets` |
| `lib/managed-block.sh` | Read/write/compare the marked block in an rc file |
| `lib/versions.sh` | `version_extract`, `version_compare`, `version_ge`, `version_major` |
| `lib/verdict.sh` | `doctor_verdict` (user-implemented policy) |
| `lib/shell-block.sh` | `shell_block_render OS SHELL BREW_PREFIX` |
| `lib/secrets.sh` | Secret names from the example file, read/write the secrets file, Maven settings.xml template |
| `config/*` | Version pins, repos, npm globals, apt packages, dev hosts, secrets example |
| `Brewfile.common`, `Brewfile.macos`, `Brewfile.linux` | Package manifests |
| `steps/NN-*.sh` | One concern per step (see spec §6) |
| `tests/*.bats`, `tests/test_helper.bash`, `tests/fixtures/steps/*` | Unit tests |
| `tests/Dockerfile.ubuntu`, `tests/smoke-linux.sh`, `.dockerignore` | Ubuntu smoke test |
| `Makefile` | `lint`, `test`, `smoke-linux`, `list`, `dry-run` |
| `README.md` | Usage |

---

### Task 1: Scaffold, test tooling and `lib/common.sh`

**Files:**
- Create: `Makefile`, `.gitignore`, `lib/common.sh`, `tests/test_helper.bash`, `tests/common.bats`

**Interfaces:**
- Produces: every function in `lib/common.sh` listed below; `tests/test_helper.bash` exporting `WI_ROOT` and `load_lib NAME`.

- [ ] **Step 1: Install test tooling on this Mac**

Run: `brew install bats-core` (shellcheck is already installed). Expected: `bats --version` prints `Bats 1.x`.

- [ ] **Step 2: Create `.gitignore` and `Makefile`**

`.gitignore`:
```
.DS_Store
tests/tmp/
```

`Makefile`:
```make
SHELL := /bin/bash
SH_FILES := $(shell find . -type f -name '*.sh' -not -path './.git/*' -not -path './tests/tmp/*' | sort)

.PHONY: lint test list dry-run smoke-linux

lint:
	shellcheck -x $(SH_FILES)

test:
	bats --recursive tests

## Run the real step list / dry-run with macOS's stock bash 3.2 to catch bashisms
list:
	/bin/bash ./install.sh --list

dry-run:
	/bin/bash ./install.sh --dry-run --yes

smoke-linux:
	./tests/smoke-linux.sh
```

- [ ] **Step 3: Write `tests/test_helper.bash`**

```bash
# tests/test_helper.bash — shared setup for every .bats file
WI_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
export WI_ROOT

# load_lib NAME — source lib/NAME.sh into the test shell
load_lib() {
  # shellcheck source=/dev/null
  source "$WI_ROOT/lib/$1.sh"
}
```

- [ ] **Step 4: Write the failing tests `tests/common.bats`**

```bash
#!/usr/bin/env bats

setup() {
  load test_helper
  load_lib common
}

@test "wi_run executes the command when not in dry-run" {
  WI_DRY_RUN=0
  wi_run touch "$BATS_TEST_TMPDIR/made"
  [ -f "$BATS_TEST_TMPDIR/made" ]
}

@test "wi_run prints but does not execute in dry-run" {
  WI_DRY_RUN=1
  run wi_run touch "$BATS_TEST_TMPDIR/not-made"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] touch"* ]]
  [ ! -f "$BATS_TEST_TMPDIR/not-made" ]
}

@test "wi_dry is true only in dry-run" {
  WI_DRY_RUN=1; wi_dry "would write"
  WI_DRY_RUN=0; ! wi_dry "would write"
}

@test "detect_os maps Darwin to macos" {
  uname() { echo Darwin; }
  [ "$(detect_os)" = macos ]
}

@test "detect_os maps unknown kernels to unsupported" {
  uname() { echo Plan9; }
  [ "$(detect_os)" = unsupported ]
}

@test "brew_prefix_for knows the three prefixes" {
  [ "$(brew_prefix_for macos arm64)" = /opt/homebrew ]
  [ "$(brew_prefix_for macos amd64)" = /usr/local ]
  [ "$(brew_prefix_for linux arm64)" = /home/linuxbrew/.linuxbrew ]
}

@test "rc_file_for_shell picks zprofile for zsh and bashrc for bash" {
  HOME=/h
  [ "$(rc_file_for_shell zsh)" = /h/.zprofile ]
  [ "$(rc_file_for_shell bash)" = /h/.bashrc ]
}

@test "in_csv matches whole items only" {
  in_csv b a,b,c
  ! in_csv d a,b,c
  ! in_csv a-b a,b
}

@test "confirm honours --yes with the default answer" {
  WI_YES=1
  confirm "go?" y
  ! confirm "go?" n
}

@test "load_secrets exports the file when present" {
  WI_SECRETS_FILE="$BATS_TEST_TMPDIR/secrets.env"
  printf 'GITHUB_TOKEN=abc\n' > "$WI_SECRETS_FILE"
  load_secrets
  [ "$GITHUB_TOKEN" = abc ]
}
```

- [ ] **Step 5: Run the tests to verify they fail**

Run: `bats tests/common.bats`
Expected: every test fails with `lib/common.sh: No such file or directory`.

- [ ] **Step 6: Write `lib/common.sh`**

```bash
#!/usr/bin/env bash
# lib/common.sh — shared helpers for install.sh, doctor.sh and every step.
# Source it; never execute it. Must stay bash-3.2 compatible.

[[ -n "${_WI_COMMON_LOADED:-}" ]] && return 0
_WI_COMMON_LOADED=1

: "${WI_DRY_RUN:=0}"
: "${WI_YES:=0}"
WI_STATE_DIR="${WI_STATE_DIR:-$HOME/.local/state/workspace-installer}"
WI_SECRETS_FILE="${WI_SECRETS_FILE:-$HOME/.config/skoolscout/secrets.env}"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_INFO=$'\033[1;36m'; C_OK=$'\033[1;32m'
  C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; C_HDR=$'\033[1;35m'
else
  C_RESET=''; C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''; C_HDR=''
fi

log_header() { printf '\n%s━━━ %s ━━━%s\n' "$C_HDR" "$*" "$C_RESET"; }
log_info()   { printf '%s→%s %s\n' "$C_INFO" "$C_RESET" "$*"; }
log_ok()     { printf '%s✓%s %s\n' "$C_OK" "$C_RESET" "$*"; }
log_warn()   { printf '%s⚠%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2; }
log_error()  { printf '%s✗%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2; }
die()        { log_error "$@"; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# detect_os → macos | linux | unsupported   (linux = Ubuntu/Debian family only)
detect_os() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux)
      if [[ -r /etc/os-release ]] && grep -qiE '^(ID|ID_LIKE)=.*(ubuntu|debian)' /etc/os-release; then
        echo linux
      else
        echo unsupported
      fi ;;
    *) echo unsupported ;;
  esac
}

# detect_arch → arm64 | amd64 | <raw uname -m>
detect_arch() {
  case "$(uname -m)" in
    arm64|aarch64) echo arm64 ;;
    x86_64|amd64)  echo amd64 ;;
    *) uname -m ;;
  esac
}

# brew_prefix_for OS ARCH → where Homebrew lives on that platform
brew_prefix_for() {
  case "$1" in
    macos) if [[ "$2" == arm64 ]]; then echo /opt/homebrew; else echo /usr/local; fi ;;
    linux) echo /home/linuxbrew/.linuxbrew ;;
    *) return 1 ;;
  esac
}

# load_brew — put brew on PATH for this process; returns 1 if not installed
load_brew() {
  command_exists brew && return 0
  local p
  for p in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew; do
    if [[ -x "$p/bin/brew" ]]; then
      eval "$("$p/bin/brew" shellenv)"
      return 0
    fi
  done
  return 1
}

# wi_run CMD ARGS... — run a mutating command, or print it under --dry-run
wi_run() {
  if [[ "$WI_DRY_RUN" == 1 ]]; then
    printf '%s[dry-run]%s %s\n' "$C_WARN" "$C_RESET" "$*"
    return 0
  fi
  log_info "\$ $*"
  "$@"
}

# wi_dry MESSAGE — true (after logging MESSAGE) when in dry-run.
# Usage: if wi_dry "write $file"; then return 0; fi
wi_dry() {
  [[ "$WI_DRY_RUN" == 1 ]] || return 1
  printf '%s[dry-run]%s %s\n' "$C_WARN" "$C_RESET" "$*"
}

# confirm PROMPT [y|n] — ask the user; under --yes return the default
confirm() {
  local prompt="$1" default="${2:-y}" reply hint
  if [[ "$WI_YES" == 1 ]]; then [[ "$default" == y ]]; return; fi
  if [[ "$default" == y ]]; then hint='Y/n'; else hint='y/N'; fi
  read -r -p "$prompt [$hint] " reply
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy] ]]
}

# in_csv NEEDLE CSV — true if NEEDLE is one of the comma-separated items
in_csv() { [[ ",$2," == *",$1,"* ]]; }

# sudo_keepalive — validate sudo once and refresh it until this process exits
sudo_keepalive() {
  [[ "$WI_DRY_RUN" == 1 ]] && return 0
  sudo -v || die "sudo is required for the selected steps"
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
}

login_shell_name() { basename "${SHELL:-/bin/bash}"; }

# rc_file_for_shell SHELL → the file the managed block belongs in
rc_file_for_shell() {
  case "$1" in
    zsh)  echo "$HOME/.zprofile" ;;
    bash) echo "$HOME/.bashrc" ;;
    *)    echo "$HOME/.profile" ;;
  esac
}

# load_secrets — export the secrets file into this process; 1 if absent
load_secrets() {
  [[ -f "$WI_SECRETS_FILE" ]] || return 1
  set -a
  # shellcheck source=/dev/null
  source "$WI_SECRETS_FILE"
  set +a
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bats tests/common.bats` — Expected: `10 tests, 0 failures`.
Run: `make lint` — Expected: no output, exit 0.

- [ ] **Step 8: Commit**

```bash
git add .gitignore Makefile lib/common.sh tests/test_helper.bash tests/common.bats
git commit -m "feat: scaffold installer repo with common helpers and bats tooling" -- .gitignore Makefile lib/common.sh tests/test_helper.bash tests/common.bats
```
(append the trailer lines from Global Constraints to the message.)

### Task 2: `lib/managed-block.sh`

**Files:**
- Create: `lib/managed-block.sh`, `tests/managed-block.bats`

**Interfaces:**
- Produces: `WI_BLOCK_BEGIN`, `WI_BLOCK_END`, `managed_block_read FILE` (prints body, exit 1 if none), `managed_block_write FILE BODY`, `managed_block_matches FILE BODY`.

- [ ] **Step 1: Write the failing tests `tests/managed-block.bats`**

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/managed-block.bats` — Expected: all 7 fail (`lib/managed-block.sh: No such file`).

- [ ] **Step 3: Write `lib/managed-block.sh`**

```bash
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/managed-block.bats` — Expected: `7 tests, 0 failures`. Run `make lint` — clean.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: add idempotent managed-block writer for rc files" -- lib/managed-block.sh tests/managed-block.bats
```
(add the trailer lines; `git add` the two files first.)

---

### Task 3: `lib/versions.sh` and the `doctor_verdict` stub (learning checkpoint)

**Files:**
- Create: `lib/versions.sh`, `lib/verdict.sh`, `tests/versions.bats`, `tests/verdict.bats`

**Interfaces:**
- Produces: `version_extract TEXT`, `version_major V`, `version_compare A B` (prints `-1|0|1`), `version_ge A B`, `doctor_verdict EXPECTED ACTUAL` (prints `PASS|WARN|FAIL`).

- [ ] **Step 1: Write the failing tests `tests/versions.bats`**

```bash
#!/usr/bin/env bats

setup() {
  load test_helper
  load_lib versions
}

@test "version_extract pulls the first dotted number from tool output" {
  [ "$(version_extract 'openjdk version "25.0.3" 2026-01-20 LTS')" = 25.0.3 ]
  [ "$(version_extract 'v24.18.0')" = 24.18.0 ]
  [ "$(version_extract 'Terraform v1.15.8')" = 1.15.8 ]
  [ "$(version_extract 'Python 3.10.11')" = 3.10.11 ]
  [ "$(version_extract 'Gradle 9.6.1')" = 9.6.1 ]
  [ "$(version_extract '25.0.3-amzn')" = 25.0.3 ]
  [ -z "$(version_extract 'no version here')" ]
}

@test "version_major" {
  [ "$(version_major 25.0.3)" = 25 ]
  [ "$(version_major 9)" = 9 ]
}

@test "version_compare orders numerically, not lexically" {
  [ "$(version_compare 1.15.8 1.7.5)" = 1 ]
  [ "$(version_compare 1.7.5 1.15.8)" = -1 ]
  [ "$(version_compare 24.18.0 24.18.0)" = 0 ]
  [ "$(version_compare 24.18 24.18.0)" = 0 ]
  [ "$(version_compare 3.10.11 3.9)" = 1 ]
}

@test "version_ge" {
  version_ge 25.0.4 25.0.3
  version_ge 25.0.3 25.0.3
  ! version_ge 21.0.9 25.0.3
}
```

- [ ] **Step 2: Write the failing test `tests/verdict.bats`**

Only the cases that hold under any policy; the user adds the rest when implementing the function.

```bash
#!/usr/bin/env bats

setup() {
  load test_helper
  load_lib verdict
}

@test "exact match is PASS" {
  [ "$(doctor_verdict 25.0.3 25.0.3)" = PASS ]
}

@test "missing actual version is FAIL" {
  [ "$(doctor_verdict 25.0.3 '')" = FAIL ]
}

@test "verdict is always one of PASS WARN FAIL" {
  for actual in 25.0.4 26.0.0 21.0.9 25.0.3; do
    v="$(doctor_verdict 25.0.3 "$actual")"
    [[ "$v" == PASS || "$v" == WARN || "$v" == FAIL ]]
  done
}
```

- [ ] **Step 3: Run both files to verify they fail**

Run: `bats tests/versions.bats tests/verdict.bats` — Expected: all fail (files missing).

- [ ] **Step 4: Write `lib/versions.sh`**

```bash
#!/usr/bin/env bash
# lib/versions.sh — parse and compare dotted version strings.

[[ -n "${_WI_VERSIONS_LOADED:-}" ]] && return 0
_WI_VERSIONS_LOADED=1

# version_extract TEXT — first "x.y[.z...]" in TEXT (empty if none)
version_extract() {
  printf '%s\n' "$1" | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1
}

# version_major V — leading component
version_major() { printf '%s\n' "${1%%.*}"; }

# version_compare A B — prints -1, 0 or 1; missing components count as 0
version_compare() {
  local -a a b
  IFS=. read -r -a a <<< "$1"
  IFS=. read -r -a b <<< "$2"
  local i n=${#a[@]}
  (( ${#b[@]} > n )) && n=${#b[@]}
  for (( i = 0; i < n; i++ )); do
    local x="${a[i]:-0}" y="${b[i]:-0}"
    if (( 10#$x > 10#$y )); then echo 1; return; fi
    if (( 10#$x < 10#$y )); then echo -1; return; fi
  done
  echo 0
}

# version_ge A B — true if A >= B
version_ge() { [[ "$(version_compare "$1" "$2")" != "-1" ]]; }
```

- [ ] **Step 5: Write the stub `lib/verdict.sh`**

```bash
#!/usr/bin/env bash
# lib/verdict.sh — how doctor.sh grades an installed version against the pin.

[[ -n "${_WI_VERDICT_LOADED:-}" ]] && return 0
_WI_VERDICT_LOADED=1

# shellcheck source=lib/versions.sh
source "$(dirname "${BASH_SOURCE[0]}")/versions.sh"

# doctor_verdict EXPECTED ACTUAL → prints PASS | WARN | FAIL
#
# doctor.sh calls this for Java, Gradle, Node, Python and Terraform. After a
# `brew upgrade`, `sdk upgrade` or `nvm install`, ACTUAL drifts from the pin;
# this function decides how loudly the doctor complains.
#
# Helpers: version_compare A B (prints -1|0|1), version_major V.
#
# TODO(user): implement the policy. Questions to settle:
#   - newer patch (25.0.4 vs 25.0.3): fine? probably PASS
#   - newer major (26 vs 25): builds may break — WARN or FAIL?
#   - older than the pin: FAIL?
# Until then: exact match PASS, missing FAIL, anything else WARN.
doctor_verdict() {
  local expected="$1" actual="$2"
  [[ -n "$actual" ]] || { echo FAIL; return; }
  if [[ "$expected" == "$actual" ]]; then echo PASS; else echo WARN; fi
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bats tests/versions.bats tests/verdict.bats` — Expected: `7 tests, 0 failures`. `make lint` clean.

- [ ] **Step 7: Commit**

```bash
git commit -m "feat: add version parsing helpers and doctor_verdict stub" -- lib/versions.sh lib/verdict.sh tests/versions.bats tests/verdict.bats
```

- [ ] **Step 8: LEARNING CHECKPOINT — hand `doctor_verdict` to the user**

Stop here. Tell the user: `lib/verdict.sh` has the signature, helpers and TODO; implement the policy in 5–10 lines and add the cases you decide on to `tests/verdict.bats`. Continue with Task 4 while they think; nothing later depends on the final policy.

---

### Task 4: Config files and Brewfiles

**Files:**
- Create: `config/versions.env`, `config/repos.txt`, `config/npm-globals.txt`, `config/claude-plugins.txt`, `config/apt-packages.txt`, `config/dev-hosts.txt`, `config/secrets.env.example`, `Brewfile.common`, `Brewfile.macos`, `Brewfile.linux`, `tests/config.bats`

**Interfaces:**
- Produces: the variables `JAVA_VERSIONS GRADLE_VERSION NODE_VERSION PYTHON_VERSION TERRAFORM_VERSION RUST_TARGET WORKSPACE_DIR` (sourced from `config/versions.env`); the file formats below, which steps parse with `grep -vE '^[[:space:]]*(#|$)'`.

- [ ] **Step 1: Write the failing test `tests/config.bats`**

```bash
#!/usr/bin/env bats

setup() { load test_helper; }

@test "versions.env sets every pin under set -u" {
  run bash -euo pipefail -c "source '$WI_ROOT/config/versions.env'; printf '%s|%s|%s|%s|%s|%s|%s' \"\$JAVA_VERSIONS\" \"\$GRADLE_VERSION\" \"\$NODE_VERSION\" \"\$PYTHON_VERSION\" \"\$TERRAFORM_VERSION\" \"\$RUST_TARGET\" \"\$WORKSPACE_DIR\""
  [ "$status" -eq 0 ]
  [ "$output" = "25.0.3-amzn 21.0.9-amzn|9.6.1|24.18.0|3.10.11|1.15.8|x86_64-unknown-linux-musl|$HOME/Development/Workspaces/skoolscout" ]
}

@test "repos.txt lines are 'url branch' pairs" {
  while read -r url branch extra; do
    [[ "$url" == git@github.com:skoolscout/*.git ]]
    [ -n "$branch" ]
    [ -z "$extra" ]
  done < <(grep -vE '^[[:space:]]*(#|$)' "$WI_ROOT/config/repos.txt")
  [ "$(grep -cvE '^[[:space:]]*(#|$)' "$WI_ROOT/config/repos.txt")" -eq 5 ]
}

@test "claude-plugins.txt lines are 'marketplace REPO' or 'plugin NAME@MARKET'" {
  while read -r kind value; do
    case "$kind" in
      marketplace) [[ "$value" == */* ]] ;;
      plugin) [[ "$value" == *@* ]] ;;
      *) return 1 ;;
    esac
  done < <(grep -vE '^[[:space:]]*(#|$)' "$WI_ROOT/config/claude-plugins.txt")
}

@test "secrets.env.example has names but no values" {
  run grep -E '^[A-Z_]+=.+' "$WI_ROOT/config/secrets.env.example"
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
```

- [ ] **Step 2: Run it to verify it fails** — `bats tests/config.bats` → all fail (files missing).

- [ ] **Step 3: Create the config files**

`config/versions.env`:
```bash
# Tool version pins. Sourced by install.sh and doctor.sh.
# Sources of truth in skoolscout-com are noted per line.
JAVA_VERSIONS="25.0.3-amzn 21.0.9-amzn"   # .sdkmanrc (25) and app-service/.sdkmanrc (21); first is default
GRADLE_VERSION="9.6.1"                     # .sdkmanrc + gradle/wrapper/gradle-wrapper.properties
NODE_VERSION="24.18.0"                     # .nvmrc
PYTHON_VERSION="3.10.11"                   # .python-version
TERRAFORM_VERSION="1.15.8"                 # .github/workflows (README's 1.7.5 is stale)
RUST_TARGET="x86_64-unknown-linux-musl"    # app-functions/schoolScraper
WORKSPACE_DIR="$HOME/Development/Workspaces/skoolscout"
```

`config/repos.txt`:
```
# <ssh url> <branch>   — cloned with --recurse-submodules into WORKSPACE_DIR
git@github.com:skoolscout/skoolscout-com.git develop
git@github.com:skoolscout/skoolscout-com-tenants.git develop
git@github.com:skoolscout/jefelabs-com.git develop
git@github.com:skoolscout/jefelabs-scripts.git develop
git@github.com:skoolscout/jefelabs-docs.git develop
```

`config/npm-globals.txt`:
```
# one package per line; installed with npm i -g under the pinned Node
task-master-ai
dotenv-cli
npm-check-updates
```

`config/claude-plugins.txt`:
```
# marketplace <owner/repo>        → claude plugin marketplace add
# plugin <name>@<marketplace>     → claude plugin install
marketplace obra/superpowers-marketplace
plugin superpowers@superpowers-marketplace
plugin mattpocock-skills@claude-plugins-official
```

`config/apt-packages.txt` (Ubuntu only; installed by bootstrap.sh):
```
# base toolchain + what Homebrew, pyenv builds, mkcert and the musl target need
build-essential
procps
curl
file
git
ca-certificates
gnupg
unzip
zip
libnss3-tools
musl-tools
libssl-dev
zlib1g-dev
libbz2-dev
libreadline-dev
libsqlite3-dev
libffi-dev
liblzma-dev
libncursesw5-dev
tk-dev
xz-utils
```

`config/dev-hosts.txt` (mirrors `DEV_HOSTS` in skoolscout-com/Makefile):
```
skoolscout.com.local
iym.skoolscout.com.local
demo-org.skoolscout.com.local
demo-com.skoolscout.com.local
demo-school.skoolscout.com.local
```

`config/secrets.env.example`:
```
# Names only. Values are collected by the github-auth step and written to
# ~/.config/skoolscout/secrets.env (mode 600). Never commit values.
GITHUB_TOKEN=               # PAT with read:packages — npm + Maven GitHub Packages
FONTAWESOME_PACKAGE_TOKEN=  # Font Awesome Pro npm registry
LOCALSTACK_AUTH_TOKEN=      # LocalStack Pro
```

- [ ] **Step 4: Create the Brewfiles**

`Brewfile.common`:
```ruby
# CLI tools for both macOS and Ubuntu (Homebrew / Linuxbrew)
tap "stripe/stripe-cli"

brew "git"
brew "gh"
brew "jq"
brew "direnv"
brew "tmux"
brew "neovim"
brew "herdr"
brew "mkcert"
brew "awscli"
brew "awscli-local"
brew "terraform-local"
brew "localstack"
brew "tfenv"
brew "libpq"
brew "postgresql@15"
brew "nvm"
brew "pnpm"
brew "pyenv"
brew "xz"
brew "rustup"
brew "libxml2"
brew "zip"
brew "unzip"
brew "coreutils"
brew "stripe/stripe-cli/stripe"
```

`Brewfile.macos`:
```ruby
# macOS only: Colima runtime, Docker CLI plugins, GUI apps
brew "colima"
brew "docker"
brew "docker-compose"
brew "docker-buildx"

cask "ghostty"
cask "visual-studio-code"
cask "google-chrome"
cask "postman"
cask "figma"
```

`Brewfile.linux`:
```ruby
# Linux only. Docker comes from Docker's apt repo (steps/50-docker.sh); no casks.
```

- [ ] **Step 5: Run the tests** — `bats tests/config.bats` → `5 tests, 0 failures` (the Brewfile test runs on this Mac).

- [ ] **Step 6: Commit**

```bash
git add config Brewfile.common Brewfile.macos Brewfile.linux tests/config.bats
git commit -m "feat: add version pins, repo/package manifests and Brewfiles" -- config Brewfile.common Brewfile.macos Brewfile.linux tests/config.bats
```

---

### Task 5: `install.sh` orchestrator

**Files:**
- Create: `install.sh`, `tests/install.bats`, `tests/fixtures/steps/10-alpha.sh`, `tests/fixtures/steps/20-beta-fails.sh`, `tests/fixtures/steps/30-gamma.sh`, `tests/fixtures/steps/40-delta.sh`, `tests/fixtures/steps/50-echo-env.sh`

**Interfaces:**
- Consumes: everything in `lib/common.sh`; `config/versions.env`.
- Produces: the step contract every `steps/*.sh` must satisfy (variables `STEP_DESC STEP_OS STEP_SUDO`, functions `step_check step_run`), the environment steps can rely on (`WI_ROOT WI_OS WI_ARCH WI_DRY_RUN WI_YES` exported; `lib/common.sh` and `config/versions.env` already sourced), and the exit codes `100` (skipped: OS) / `101` (skipped: already satisfied).
- `WI_STEPS_DIR` overrides the steps directory (tests point it at fixtures).

- [ ] **Step 1: Create the fixture steps**

`tests/fixtures/steps/10-alpha.sh`:
```bash
#!/usr/bin/env bash
STEP_DESC="alpha: creates a marker file"
STEP_OS="all"
STEP_SUDO="no"
step_check() { [[ -f "$WI_FIXTURE_DIR/alpha.done" ]]; }
step_run()   { touch "$WI_FIXTURE_DIR/alpha.done"; }
```
`tests/fixtures/steps/20-beta-fails.sh`:
```bash
#!/usr/bin/env bash
STEP_DESC="beta: always fails"
STEP_OS="all"
STEP_SUDO="no"
step_check() { return 1; }
step_run()   { echo "beta exploding"; return 3; }
```
`tests/fixtures/steps/30-gamma.sh`:
```bash
#!/usr/bin/env bash
STEP_DESC="gamma: only for plan9"
STEP_OS="plan9"
STEP_SUDO="no"
step_check() { return 1; }
step_run()   { touch "$WI_FIXTURE_DIR/gamma.done"; }
```
`tests/fixtures/steps/40-delta.sh`:
```bash
#!/usr/bin/env bash
STEP_DESC="delta: creates a marker file"
STEP_OS="all"
STEP_SUDO="no"
step_check() { [[ -f "$WI_FIXTURE_DIR/delta.done" ]]; }
step_run()   { touch "$WI_FIXTURE_DIR/delta.done"; }
```
`tests/fixtures/steps/50-echo-env.sh`:
```bash
#!/usr/bin/env bash
STEP_DESC="echo-env: prints the environment steps receive"
STEP_OS="all"
STEP_SUDO="no"
step_check() { return 1; }
step_run()   { echo "WI_DRY_RUN=$WI_DRY_RUN WI_YES=$WI_YES WI_OS=$WI_OS NODE_VERSION=$NODE_VERSION"; }
```

- [ ] **Step 2: Write the failing tests `tests/install.bats`**

```bash
#!/usr/bin/env bats

setup() {
  load test_helper
  export WI_STEPS_DIR="$WI_ROOT/tests/fixtures/steps"
  export WI_FIXTURE_DIR="$BATS_TEST_TMPDIR"
  export WI_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

@test "--list prints every step with metadata and runs nothing" {
  run "$WI_ROOT/install.sh" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"*"os=all"*"sudo=no"* ]]
  [[ "$output" == *"gamma"*"os=plan9"* ]]
  [ ! -f "$WI_FIXTURE_DIR/alpha.done" ]
}

@test "unknown step names are rejected" {
  run "$WI_ROOT/install.sh" --only nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown step 'nope'"* ]]
}

@test "runs steps in order, continues past a failure, exits 1" {
  run "$WI_ROOT/install.sh"
  [ "$status" -eq 1 ]
  [ -f "$WI_FIXTURE_DIR/alpha.done" ]
  [ -f "$WI_FIXTURE_DIR/delta.done" ]
  [ ! -f "$WI_FIXTURE_DIR/gamma.done" ]
  [[ "$output" == *"alpha PASS"* ]]
  [[ "$output" == *"beta-fails FAIL"* ]]
  [[ "$output" == *"gamma SKIP (os)"* ]]
  [[ "$output" == *"delta PASS"* ]]
}

@test "--fail-fast stops after the first failure" {
  run "$WI_ROOT/install.sh" --fail-fast
  [ "$status" -eq 1 ]
  [ -f "$WI_FIXTURE_DIR/alpha.done" ]
  [ ! -f "$WI_FIXTURE_DIR/delta.done" ]
}

@test "--only runs just the named steps" {
  run "$WI_ROOT/install.sh" --only alpha,delta
  [ "$status" -eq 0 ]
  [[ "$output" == *"beta-fails SKIP (deselected)"* ]]
  [ -f "$WI_FIXTURE_DIR/delta.done" ]
}

@test "--skip removes steps" {
  run "$WI_ROOT/install.sh" --skip beta-fails,echo-env
  [ "$status" -eq 0 ]
}

@test "a satisfied step_check yields SKIP (done)" {
  touch "$WI_FIXTURE_DIR/alpha.done"
  run "$WI_ROOT/install.sh" --only alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha SKIP (done)"* ]]
}

@test "steps receive the exported environment and --dry-run/--yes flags" {
  run "$WI_ROOT/install.sh" --only echo-env --dry-run --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"WI_DRY_RUN=1 WI_YES=1 WI_OS="*" NODE_VERSION=24.18.0"* ]]
}

@test "every run writes a log file" {
  run "$WI_ROOT/install.sh" --only alpha
  ls "$WI_STATE_DIR"/install-*.log
}
```

- [ ] **Step 3: Run to verify failure** — `bats tests/install.bats` → all fail (`install.sh: No such file`).

- [ ] **Step 4: Write `install.sh`**

```bash
#!/usr/bin/env bash
# install.sh — run steps/NN-name.sh in order. Every step is idempotent, so
# re-running is safe. See --help. Must stay bash-3.2 compatible.
set -euo pipefail

WI_ROOT="${WI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export WI_ROOT
WI_STEPS_DIR="${WI_STEPS_DIR:-$WI_ROOT/steps}"

# shellcheck source=lib/common.sh
source "$WI_ROOT/lib/common.sh"
# shellcheck source=config/versions.env
source "$WI_ROOT/config/versions.env"
export JAVA_VERSIONS GRADLE_VERSION NODE_VERSION PYTHON_VERSION TERRAFORM_VERSION RUST_TARGET WORKSPACE_DIR

WI_RC_SKIP_OS=100
WI_RC_SKIP_DONE=101

usage() {
  cat <<'EOF'
Usage: install.sh [OPTIONS]

  --only STEP[,STEP...]   run only these steps
  --skip STEP[,STEP...]   run everything except these steps
  --list                  list steps and exit
  --dry-run               print mutating commands instead of running them
  --yes, -y               never prompt; use defaults, skip missing secrets
  --fail-fast             stop at the first failed step
  --help, -h              this text

Steps are addressed by name (file name without number and .sh), e.g. sdkman.
EOF
}

ONLY="" SKIP="" LIST=0 FAIL_FAST=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)      ONLY="$2"; shift 2 ;;
    --only=*)    ONLY="${1#*=}"; shift ;;
    --skip)      SKIP="$2"; shift 2 ;;
    --skip=*)    SKIP="${1#*=}"; shift ;;
    --list)      LIST=1; shift ;;
    --dry-run)   WI_DRY_RUN=1; shift ;;
    --yes|-y)    WI_YES=1; shift ;;
    --fail-fast) FAIL_FAST=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) log_error "Unknown option: $1"; usage; exit 2 ;;
  esac
done
export WI_DRY_RUN WI_YES

WI_OS="$(detect_os)"
WI_ARCH="$(detect_arch)"
export WI_OS WI_ARCH
[[ "$WI_OS" != unsupported ]] || die "Unsupported OS: only macOS and Ubuntu/Debian are supported"

# step_name_of FILE → "sdkman" for steps/40-sdkman.sh
step_name_of() {
  local f
  f="$(basename "$1" .sh)"
  printf '%s\n' "${f#[0-9][0-9]-}"
}

# step_meta FILE → "DESC|OS|SUDO" without running anything
step_meta() {
  ( set -e
    STEP_DESC="" STEP_OS=all STEP_SUDO=no
    # shellcheck source=/dev/null
    source "$1"
    printf '%s|%s|%s\n' "$STEP_DESC" "$STEP_OS" "$STEP_SUDO" )
}

step_selected() {
  if [[ -n "$ONLY" ]]; then in_csv "$1" "$ONLY"; else ! in_csv "$1" "$SKIP"; fi
}

# run_step FILE → 0 ran, 100 skipped (OS), 101 skipped (already satisfied), else failed
run_step() {
  ( set -euo pipefail
    STEP_DESC="" STEP_OS=all STEP_SUDO=no
    # shellcheck source=/dev/null
    source "$1"
    [[ "$STEP_OS" == all || "$STEP_OS" == "$WI_OS" ]] || exit "$WI_RC_SKIP_OS"
    if step_check >/dev/null 2>&1; then exit "$WI_RC_SKIP_DONE"; fi
    step_run )
}

STEP_FILES=()
while IFS= read -r f; do STEP_FILES+=("$f"); done < <(find "$WI_STEPS_DIR" -maxdepth 1 -name '[0-9][0-9]-*.sh' | sort)
[[ ${#STEP_FILES[@]} -gt 0 ]] || die "No steps found in $WI_STEPS_DIR"

ALL_NAMES=""
for f in "${STEP_FILES[@]}"; do ALL_NAMES="${ALL_NAMES:+$ALL_NAMES,}$(step_name_of "$f")"; done
for n in ${ONLY//,/ } ${SKIP//,/ }; do
  in_csv "$n" "$ALL_NAMES" || die "Unknown step '$n'. Known: $ALL_NAMES"
done

if [[ "$LIST" == 1 ]]; then
  for f in "${STEP_FILES[@]}"; do
    IFS='|' read -r desc os sudo_ <<< "$(step_meta "$f")"
    printf '%-18s os=%-6s sudo=%-6s %s\n' "$(step_name_of "$f")" "$os" "$sudo_" "$desc"
  done
  exit 0
fi

mkdir -p "$WI_STATE_DIR"
WI_LOG="$WI_STATE_DIR/install-$(date +%Y%m%d-%H%M%S).log"
# Terminal gets everything; the log file gets a copy with token values redacted.
exec > >(tee >(sed -E 's/([A-Za-z_]*TOKEN=)[^[:space:]]+/\1<redacted>/g' >> "$WI_LOG")) 2>&1
log_info "OS=$WI_OS ARCH=$WI_ARCH dry-run=$WI_DRY_RUN yes=$WI_YES log=$WI_LOG"

NEEDS_SUDO=0
for f in "${STEP_FILES[@]}"; do
  name="$(step_name_of "$f")"
  step_selected "$name" || continue
  IFS='|' read -r _ os sudo_ <<< "$(step_meta "$f")"
  [[ "$os" == all || "$os" == "$WI_OS" ]] || continue
  if [[ "$sudo_" == yes || ( "$sudo_" == linux && "$WI_OS" == linux ) ]]; then NEEDS_SUDO=1; fi
done
if [[ "$NEEDS_SUDO" == 1 ]]; then sudo_keepalive; fi

RESULTS=()
FAILED=0
for f in "${STEP_FILES[@]}"; do
  name="$(step_name_of "$f")"
  if ! step_selected "$name"; then RESULTS+=("$name SKIP (deselected)"); continue; fi
  IFS='|' read -r desc _ _ <<< "$(step_meta "$f")"
  log_header "$name — $desc"
  rc=0
  run_step "$f" || rc=$?
  case "$rc" in
    0)   log_ok "$name done";               RESULTS+=("$name PASS") ;;
    100) log_info "$name not for $WI_OS";    RESULTS+=("$name SKIP (os)") ;;
    101) log_ok "$name already satisfied";   RESULTS+=("$name SKIP (done)") ;;
    *)   log_error "$name failed (rc=$rc)";  RESULTS+=("$name FAIL"); FAILED=1
         if [[ "$FAIL_FAST" == 1 ]]; then break; fi ;;
  esac
done

log_header "Summary"
printf '  %s\n' ${RESULTS[@]+"${RESULTS[@]}"}
if [[ "$FAILED" == 1 ]]; then
  log_error "Some steps failed. Log: $WI_LOG"
  exit 1
fi
log_ok "All selected steps passed. Open a new shell, then run ./doctor.sh"
```

- [ ] **Step 5: Make it executable and run the tests**

Run: `chmod +x install.sh tests/fixtures/steps/*.sh && bats tests/install.bats` — Expected: `9 tests, 0 failures`.
Run: `make lint` — clean.
Run: `/bin/bash ./install.sh --list` from the repo root with `WI_STEPS_DIR=tests/fixtures/steps` — Expected: the five fixture steps listed (proves bash 3.2 compatibility; `steps/` does not exist yet).

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/install.bats tests/fixtures
git commit -m "feat: add install.sh orchestrator with step contract and fixture tests" -- install.sh tests/install.bats tests/fixtures
```

---

### Task 6: Steps 10 homebrew, 20 brew-bundle, 30 shell-config (+ `lib/shell-block.sh`)

**Files:**
- Create: `lib/shell-block.sh`, `tests/shell-block.bats`, `tests/steps.bats`, `steps/10-homebrew.sh`, `steps/20-brew-bundle.sh`, `steps/30-shell-config.sh`

**Interfaces:**
- Consumes: `load_brew`, `wi_run`, `wi_dry`, `brew_prefix_for`, `login_shell_name`, `rc_file_for_shell`, `managed_block_*`.
- Produces: `shell_block_render OS SHELL BREW_PREFIX` (prints the block body). `tests/steps.bats` is the structural test every later step task extends by simply existing in `steps/`.

- [ ] **Step 1: Write the failing tests `tests/shell-block.bats`**

```bash
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
```

- [ ] **Step 2: Write the failing structural test `tests/steps.bats`**

```bash
#!/usr/bin/env bats
# Every real step must load cleanly and honour the step contract.

setup() {
  load test_helper
  export WI_OS=macos WI_ARCH=arm64 WI_DRY_RUN=1 WI_YES=1
  export WI_SECRETS_FILE="$BATS_TEST_TMPDIR/secrets.env"
  export WI_HOSTS_FILE="$BATS_TEST_TMPDIR/hosts"
  # shellcheck source=/dev/null
  source "$WI_ROOT/config/versions.env"
  export JAVA_VERSIONS GRADLE_VERSION NODE_VERSION PYTHON_VERSION TERRAFORM_VERSION RUST_TARGET WORKSPACE_DIR
}

@test "there is at least one real step" {
  ls "$WI_ROOT"/steps/[0-9][0-9]-*.sh
}

@test "every step defines the contract" {
  for step in "$WI_ROOT"/steps/[0-9][0-9]-*.sh; do
    run bash -euo pipefail -c "
      source '$WI_ROOT/lib/common.sh'
      source '$step'
      [[ \"\$STEP_OS\" =~ ^(all|macos|linux)$ ]] || { echo 'bad STEP_OS'; exit 1; }
      [[ \"\$STEP_SUDO\" =~ ^(yes|no|linux)$ ]] || { echo 'bad STEP_SUDO'; exit 1; }
      [[ -n \"\$STEP_DESC\" ]] || { echo 'empty STEP_DESC'; exit 1; }
      declare -F step_check >/dev/null || { echo 'no step_check'; exit 1; }
      declare -F step_run   >/dev/null || { echo 'no step_run'; exit 1; }
    "
    [ "$status" -eq 0 ] || { echo "$step: $output"; return 1; }
  done
}

@test "install.sh --list loads every real step" {
  run "$WI_ROOT/install.sh" --list
  [ "$status" -eq 0 ]
  for step in "$WI_ROOT"/steps/[0-9][0-9]-*.sh; do
    name="$(basename "$step" .sh)"; name="${name#[0-9][0-9]-}"
    [[ "$output" == *"$name"* ]]
  done
}
```

- [ ] **Step 3: Run both** — `bats tests/shell-block.bats tests/steps.bats` → fail (no lib, no steps).

- [ ] **Step 4: Write `lib/shell-block.sh`**

```bash
#!/usr/bin/env bash
# lib/shell-block.sh — render the managed rc block for an OS/shell/brew prefix.

[[ -n "${_WI_SHELL_BLOCK_LOADED:-}" ]] && return 0
_WI_SHELL_BLOCK_LOADED=1

# shell_block_render OS SHELL BREW_PREFIX → block body on stdout
shell_block_render() {
  local os="$1" shell="$2" brew_prefix="$3"
  cat <<EOF
eval "\$($brew_prefix/bin/brew shellenv)"
export SDKMAN_DIR="\$HOME/.sdkman"
[[ -s "\$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "\$SDKMAN_DIR/bin/sdkman-init.sh"
export NVM_DIR="\$HOME/.nvm"
[ -s "$brew_prefix/opt/nvm/nvm.sh" ] && source "$brew_prefix/opt/nvm/nvm.sh"
export PYENV_ROOT="\$HOME/.pyenv"
command -v pyenv >/dev/null 2>&1 && eval "\$(pyenv init -)"
command -v direnv >/dev/null 2>&1 && eval "\$(direnv hook $shell)"
export PATH="\$HOME/.cargo/bin:\$HOME/.local/bin:$brew_prefix/opt/rustup/bin:$brew_prefix/opt/libpq/bin:\$PATH"
[ -f "\$HOME/.config/skoolscout/secrets.env" ] && set -a && source "\$HOME/.config/skoolscout/secrets.env" && set +a
EOF
  if [[ "$os" == macos ]]; then
    cat <<'EOF'
export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock
EOF
  fi
}
```
(`~/.local/bin` is on PATH for the native Claude Code install from Task 7.)

- [ ] **Step 5: Write `steps/10-homebrew.sh`**

```bash
#!/usr/bin/env bash
# steps/10-homebrew.sh — Homebrew present (bootstrap.sh normally did this) and updated.
STEP_DESC="Install Homebrew (macOS or Linuxbrew) and brew update"
STEP_OS="all"
STEP_SUDO="linux"

step_check() { load_brew; }

step_run() {
  if ! load_brew; then
    log_info "Installing Homebrew"
    if wi_dry "run the official Homebrew installer (NONINTERACTIVE=1)"; then return 0; fi
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    load_brew || die "Homebrew installed but not found in any known prefix"
  fi
  wi_run brew update
}
```

- [ ] **Step 6: Write `steps/20-brew-bundle.sh`**

```bash
#!/usr/bin/env bash
# steps/20-brew-bundle.sh — install Brewfile.common then Brewfile.<os>.
STEP_DESC="brew bundle: Brewfile.common + Brewfile.<os>"
STEP_OS="all"
STEP_SUDO="no"

brew_bundle_files() { printf '%s\n' "$WI_ROOT/Brewfile.common" "$WI_ROOT/Brewfile.$WI_OS"; }

step_check() {
  load_brew || return 1
  local f
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    brew bundle check --no-upgrade --file="$f" >/dev/null 2>&1 || return 1
  done < <(brew_bundle_files)
}

step_run() {
  load_brew || die "Homebrew missing — run the homebrew step first"
  local f
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    if ! grep -qE '^(tap|brew|cask) ' "$f"; then log_info "$(basename "$f") lists nothing, skipping"; continue; fi
    HOMEBREW_NO_AUTO_UPDATE=1 wi_run brew bundle install --no-upgrade --file="$f"
  done < <(brew_bundle_files)
}
```

- [ ] **Step 7: Write `steps/30-shell-config.sh`**

```bash
#!/usr/bin/env bash
# steps/30-shell-config.sh — managed block in the login shell's rc file.
STEP_DESC="Write the managed block to the login shell rc file"
STEP_OS="all"
STEP_SUDO="no"

# shellcheck source=lib/managed-block.sh
source "$WI_ROOT/lib/managed-block.sh"
# shellcheck source=lib/shell-block.sh
source "$WI_ROOT/lib/shell-block.sh"

shell_config_target() { rc_file_for_shell "$(login_shell_name)"; }
shell_config_body() {
  shell_block_render "$WI_OS" "$(login_shell_name)" "$(brew_prefix_for "$WI_OS" "$WI_ARCH")"
}

step_check() { managed_block_matches "$(shell_config_target)" "$(shell_config_body)"; }

step_run() {
  local target body
  target="$(shell_config_target)"
  body="$(shell_config_body)"
  if wi_dry "write managed block to $target"; then return 0; fi
  managed_block_write "$target" "$body"
  log_ok "managed block written to $target (open a new shell to pick it up)"
}
```

- [ ] **Step 8: Run the tests**

Run: `chmod +x steps/*.sh && bats tests/shell-block.bats tests/steps.bats && make lint` — Expected: `6 tests, 0 failures`, lint clean.
Run: `make list` — Expected: three steps listed via `/bin/bash`.
Run: `./install.sh --only shell-config --dry-run` — Expected: `[dry-run] write managed block to /Users/<you>/.zprofile`, summary `shell-config PASS`.

- [ ] **Step 9: Commit**

```bash
git add lib/shell-block.sh tests/shell-block.bats tests/steps.bats steps/10-homebrew.sh steps/20-brew-bundle.sh steps/30-shell-config.sh
git commit -m "feat: add homebrew, brew-bundle and shell-config steps" -- lib/shell-block.sh tests/shell-block.bats tests/steps.bats steps/10-homebrew.sh steps/20-brew-bundle.sh steps/30-shell-config.sh
```

---

### Task 7: Steps 40 sdkman, 41 node, 42 python, 43 terraform, 44 rust, 45 claude-code

**Files:**
- Create: `steps/40-sdkman.sh`, `steps/41-node.sh`, `steps/42-python.sh`, `steps/43-terraform.sh`, `steps/44-rust.sh`, `steps/45-claude-code.sh`
- Test: `tests/steps.bats` (already covers them structurally), `tests/node-step.bats`

**Interfaces:**
- Consumes: `load_brew`, `wi_run`, `wi_dry`, `command_exists`, `die`, the `config/versions.env` variables, `config/npm-globals.txt`, `config/claude-plugins.txt`.
- Produces: `npm_global_bin PKG` (bin name a global package exposes) used by doctor.sh.

Note on `set -u`: `sdkman-init.sh` and `nvm.sh` reference unset variables, so they are sourced between `set +u` / `set -u`.

- [ ] **Step 1: Write the failing test `tests/node-step.bats`**

```bash
#!/usr/bin/env bats

setup() {
  load test_helper
  load_lib common
  export WI_OS=macos WI_ARCH=arm64 WI_DRY_RUN=1
  # shellcheck source=/dev/null
  source "$WI_ROOT/config/versions.env"
  # shellcheck source=/dev/null
  source "$WI_ROOT/steps/41-node.sh"
}

@test "npm_global_bin maps package names to their binaries" {
  [ "$(npm_global_bin task-master-ai)" = task-master ]
  [ "$(npm_global_bin dotenv-cli)" = dotenv ]
  [ "$(npm_global_bin npm-check-updates)" = ncu ]
  [ "$(npm_global_bin some-other-tool)" = some-other-tool ]
}

@test "npm_globals lists the configured packages without comments" {
  run npm_globals
  [[ "$output" == *task-master-ai* ]]
  [[ "$output" != *"#"* ]]
}
```

- [ ] **Step 2: Run it** — fails (step file missing).

- [ ] **Step 3: Write `steps/40-sdkman.sh`**

```bash
#!/usr/bin/env bash
# steps/40-sdkman.sh — SDKMAN with the pinned Java(s) and Gradle.
STEP_DESC="SDKMAN: Java ${JAVA_VERSIONS} and Gradle ${GRADLE_VERSION}"
STEP_OS="all"
STEP_SUDO="no"

SDKMAN_DIR="${SDKMAN_DIR:-$HOME/.sdkman}"
export SDKMAN_DIR

sdk_load() {
  [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] || return 1
  set +u
  # shellcheck source=/dev/null
  source "$SDKMAN_DIR/bin/sdkman-init.sh"
  set -u
}

step_check() {
  local v
  for v in $JAVA_VERSIONS; do
    [[ -x "$SDKMAN_DIR/candidates/java/$v/bin/java" ]] || return 1
  done
  [[ -x "$SDKMAN_DIR/candidates/gradle/$GRADLE_VERSION/bin/gradle" ]] || return 1
  grep -q '^sdkman_auto_env=true' "$SDKMAN_DIR/etc/config" 2>/dev/null
}

step_run() {
  if [[ ! -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]]; then
    if wi_dry "install SDKMAN (curl get.sdkman.io, rcupdate=false)"; then return 0; fi
    curl -s "https://get.sdkman.io?rcupdate=false" | bash
  fi
  if ! wi_dry "set sdkman_auto_answer=true and sdkman_auto_env=true in $SDKMAN_DIR/etc/config"; then
    mkdir -p "$SDKMAN_DIR/etc"
    touch "$SDKMAN_DIR/etc/config"
    sed -i.bak -e '/^sdkman_auto_answer=/d' -e '/^sdkman_auto_env=/d' "$SDKMAN_DIR/etc/config"
    printf 'sdkman_auto_answer=true\nsdkman_auto_env=true\n' >> "$SDKMAN_DIR/etc/config"
    rm -f "$SDKMAN_DIR/etc/config.bak"
  fi
  sdk_load || { [[ "$WI_DRY_RUN" == 1 ]] && return 0; die "SDKMAN init script not found after install"; }
  set +u
  local v first=""
  for v in $JAVA_VERSIONS; do
    [[ -n "$first" ]] || first="$v"
    [[ -d "$SDKMAN_DIR/candidates/java/$v" ]] || wi_run sdk install java "$v"
  done
  wi_run sdk default java "$first"
  [[ -d "$SDKMAN_DIR/candidates/gradle/$GRADLE_VERSION" ]] || wi_run sdk install gradle "$GRADLE_VERSION"
  wi_run sdk default gradle "$GRADLE_VERSION"
  set -u
}
```

- [ ] **Step 4: Write `steps/41-node.sh`**

```bash
#!/usr/bin/env bash
# steps/41-node.sh — pinned Node via nvm (brew-installed) + global npm packages.
STEP_DESC="nvm: Node ${NODE_VERSION} + global npm packages"
STEP_OS="all"
STEP_SUDO="no"

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
export NVM_DIR

nvm_load() {
  load_brew || return 1
  local nvm_sh
  nvm_sh="$(brew --prefix nvm 2>/dev/null)/nvm.sh"
  [[ -s "$nvm_sh" ]] || return 1
  mkdir -p "$NVM_DIR"
  set +u
  # shellcheck source=/dev/null
  source "$nvm_sh"
  set -u
}

npm_globals() { grep -vE '^[[:space:]]*(#|$)' "$WI_ROOT/config/npm-globals.txt"; }

# npm_global_bin PKG → the executable the package installs
npm_global_bin() {
  case "$1" in
    task-master-ai)     echo task-master ;;
    dotenv-cli)         echo dotenv ;;
    npm-check-updates)  echo ncu ;;
    *)                  basename "$1" ;;
  esac
}

step_check() {
  nvm_load || return 1
  set +u
  if ! nvm use "$NODE_VERSION" >/dev/null 2>&1; then set -u; return 1; fi
  set -u
  [[ "$(node --version)" == "v$NODE_VERSION" ]] || return 1
  local pkg
  while IFS= read -r pkg; do
    command_exists "$(npm_global_bin "$pkg")" || return 1
  done < <(npm_globals)
}

step_run() {
  nvm_load || { [[ "$WI_DRY_RUN" == 1 ]] && return 0; die "nvm not installed (brew-bundle step)"; }
  set +u
  wi_run nvm install "$NODE_VERSION"
  wi_run nvm alias default "$NODE_VERSION"
  nvm use default >/dev/null 2>&1 || true
  set -u
  local pkg
  while IFS= read -r pkg; do
    command_exists "$(npm_global_bin "$pkg")" || wi_run npm install -g "$pkg"
  done < <(npm_globals)
}
```

- [ ] **Step 5: Write `steps/42-python.sh`**

```bash
#!/usr/bin/env bash
# steps/42-python.sh — pinned Python via pyenv (brew-installed).
STEP_DESC="pyenv: Python ${PYTHON_VERSION}"
STEP_OS="all"
STEP_SUDO="no"

PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
export PYENV_ROOT

pyenv_load() {
  load_brew || return 1
  command_exists pyenv || return 1
  eval "$(pyenv init -)"
}

step_check() {
  pyenv_load || return 1
  [[ -x "$PYENV_ROOT/versions/$PYTHON_VERSION/bin/python" ]] || return 1
  [[ "$(pyenv global)" == "$PYTHON_VERSION" ]]
}

step_run() {
  pyenv_load || { [[ "$WI_DRY_RUN" == 1 ]] && return 0; die "pyenv not installed (brew-bundle step)"; }
  wi_run pyenv install --skip-existing "$PYTHON_VERSION"
  wi_run pyenv global "$PYTHON_VERSION"
}
```

- [ ] **Step 6: Write `steps/43-terraform.sh`**

```bash
#!/usr/bin/env bash
# steps/43-terraform.sh — pinned Terraform via tfenv (brew-installed).
STEP_DESC="tfenv: Terraform ${TERRAFORM_VERSION}"
STEP_OS="all"
STEP_SUDO="no"

step_check() {
  load_brew || return 1
  command_exists tfenv || return 1
  command_exists terraform || return 1
  [[ "$(terraform version 2>/dev/null | head -n1)" == "Terraform v$TERRAFORM_VERSION" ]]
}

step_run() {
  load_brew || { [[ "$WI_DRY_RUN" == 1 ]] && return 0; die "tfenv not installed (brew-bundle step)"; }
  wi_run tfenv install "$TERRAFORM_VERSION"
  wi_run tfenv use "$TERRAFORM_VERSION"
}
```

- [ ] **Step 7: Write `steps/44-rust.sh`**

```bash
#!/usr/bin/env bash
# steps/44-rust.sh — stable Rust + the musl target the Lambda scrapers build for.
# brew's rustup formula is keg-only, so it is addressed by full path.
STEP_DESC="rustup: stable toolchain + ${RUST_TARGET} (macOS also musl-cross)"
STEP_OS="all"
STEP_SUDO="no"

rustup_bin() {
  if command_exists rustup; then command -v rustup; return 0; fi
  load_brew || return 1
  local p
  p="$(brew --prefix rustup 2>/dev/null)/bin/rustup"
  [[ -x "$p" ]] || return 1
  echo "$p"
}

step_check() {
  local r
  r="$(rustup_bin)" || return 1
  [[ -x "$HOME/.cargo/bin/cargo" ]] || return 1
  "$r" target list --installed 2>/dev/null | grep -qx "$RUST_TARGET" || return 1
  if [[ "$WI_OS" == macos ]]; then command_exists x86_64-linux-musl-gcc || return 1; fi
  return 0
}

step_run() {
  local r
  r="$(rustup_bin)" || { [[ "$WI_DRY_RUN" == 1 ]] && return 0; die "rustup not installed (brew-bundle step)"; }
  export RUSTUP_INIT_SKIP_PATH_CHECK=yes
  wi_run "$r" default stable
  wi_run "$r" target add "$RUST_TARGET"
  if [[ "$WI_OS" == macos ]] && ! command_exists x86_64-linux-musl-gcc; then
    log_warn "Installing musl-cross (compiles a cross toolchain; this can take a long time)"
    wi_run brew install filosottile/musl-cross/musl-cross
  fi
}
```

- [ ] **Step 8: Write `steps/45-claude-code.sh`**

```bash
#!/usr/bin/env bash
# steps/45-claude-code.sh — Claude Code (native installer) + marketplaces/plugins.
STEP_DESC="Claude Code (native install) + plugins from config/claude-plugins.txt"
STEP_OS="all"
STEP_SUDO="no"

CLAUDE_PLUGINS_FILE="$WI_ROOT/config/claude-plugins.txt"
export PATH="$HOME/.local/bin:$PATH"

claude_plugin_lines() { grep -vE '^[[:space:]]*(#|$)' "$CLAUDE_PLUGINS_FILE"; }

claude_plugin_installed() { claude plugin list 2>/dev/null | grep -qF "$1"; }

step_check() {
  command_exists claude || return 1
  local kind value
  while read -r kind value; do
    [[ "$kind" == plugin ]] || continue
    claude_plugin_installed "$value" || return 1
  done < <(claude_plugin_lines)
}

step_run() {
  if ! command_exists claude; then
    if ! wi_dry "install Claude Code via https://claude.ai/install.sh"; then
      curl -fsSL https://claude.ai/install.sh | bash
      command_exists claude || die "claude not on PATH after install (expected ~/.local/bin/claude)"
    fi
  fi
  local kind value
  while read -r kind value; do
    case "$kind" in
      marketplace) wi_run claude plugin marketplace add "$value" ;;
      plugin)
        if claude_plugin_installed "$value"; then log_ok "plugin $value present"; else wi_run claude plugin install "$value"; fi ;;
      *) log_warn "unknown line in claude-plugins.txt: $kind $value" ;;
    esac
  done < <(claude_plugin_lines)
}
```
(`claude plugin marketplace add` on an already-added marketplace just refreshes it; that is why it is not guarded.)

- [ ] **Step 9: Run the tests**

Run: `chmod +x steps/*.sh && bats tests/node-step.bats tests/steps.bats && make lint` — Expected: `5 tests, 0 failures`, lint clean.
Run: `./install.sh --only sdkman,node,python,terraform,rust,claude-code --dry-run --yes` — Expected: on this Mac most report `SKIP (done)` because the tools exist; any that don't print `[dry-run] ...` lines and `PASS`. No real changes.

- [ ] **Step 10: Commit**

```bash
git add steps/40-sdkman.sh steps/41-node.sh steps/42-python.sh steps/43-terraform.sh steps/44-rust.sh steps/45-claude-code.sh tests/node-step.bats
git commit -m "feat: add sdkman, node, python, terraform, rust and claude-code steps" -- steps/40-sdkman.sh steps/41-node.sh steps/42-python.sh steps/43-terraform.sh steps/44-rust.sh steps/45-claude-code.sh tests/node-step.bats
```

---

### Task 8: Steps 50 docker, 51 postgres

**Files:**
- Create: `steps/50-docker.sh`, `steps/51-postgres.sh`

**Interfaces:**
- Consumes: `load_brew`, `wi_run`, `wi_dry`, `command_exists`, `log_*`, `WI_OS`.
- Produces: nothing other steps call. `docker info` working is what step 90 (Playwright) and the doctor rely on.

- [ ] **Step 1: Write `steps/50-docker.sh`**

```bash
#!/usr/bin/env bash
# steps/50-docker.sh — Colima on macOS, Docker Engine (apt) on Ubuntu.
STEP_DESC="Docker: Colima on macOS, Docker Engine on Ubuntu"
STEP_OS="all"
STEP_SUDO="linux"

docker_ready() { command_exists docker && docker info >/dev/null 2>&1; }

# Inside a macOS VM this is 0 unless nested virtualization is enabled (M3+ host, macOS 15+).
macos_virt_available() { [[ "$(sysctl -n kern.hv_support 2>/dev/null)" == 1 ]]; }

step_check() {
  load_brew || true
  if [[ "$WI_OS" == macos ]]; then export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"; fi
  docker_ready
}

docker_run_macos() {
  load_brew || die "Homebrew missing"
  if ! macos_virt_available; then
    log_warn "Hardware virtualization is not available here (kern.hv_support != 1), so Colima cannot start."
    log_warn "Inside a macOS VM this needs an M3+ host on macOS 15+ AND nested virtualization enabled"
    log_warn "in the VM settings (Parallels: Hardware > CPU & Memory > Advanced). Skipping Docker."
    return 0
  fi
  if ! colima status >/dev/null 2>&1; then
    wi_run colima start --cpu 4 --memory 8 --vm-type vz --mount-type virtiofs
  fi
  wi_run brew services start colima
  export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
  if [[ "$WI_DRY_RUN" != 1 ]] && ! docker_ready; then die "colima is up but 'docker info' fails"; fi
}

docker_run_linux() {
  local arch codename
  arch="$(dpkg --print-architecture)"
  codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    wi_run sudo install -m 0755 -d /etc/apt/keyrings
    wi_run sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    wi_run sudo chmod a+r /etc/apt/keyrings/docker.asc
  fi
  if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
    if ! wi_dry "write /etc/apt/sources.list.d/docker.list ($codename, $arch)"; then
      printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
        "$arch" "$codename" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    fi
  fi
  wi_run sudo apt-get update -qq
  wi_run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  wi_run sudo usermod -aG docker "$USER"
  wi_run sudo systemctl enable --now docker
  if [[ "$WI_DRY_RUN" != 1 ]] && ! docker_ready; then
    log_warn "Docker installed. Log out and back in so the docker group applies; 'docker info' works after that."
  fi
}

step_run() {
  case "$WI_OS" in
    macos) docker_run_macos ;;
    linux) docker_run_linux ;;
  esac
}
```

- [ ] **Step 2: Write `steps/51-postgres.sh`**

```bash
#!/usr/bin/env bash
# steps/51-postgres.sh — PostgreSQL 15 server + psql, installed but NOT started:
# skoolscout-com's docker compose runs its own Postgres on 5432.
STEP_DESC="PostgreSQL 15 + psql (installed; service left stopped)"
STEP_OS="all"
STEP_SUDO="no"

step_check() {
  load_brew || return 1
  [[ -x "$(brew --prefix postgresql@15 2>/dev/null)/bin/postgres" ]] || return 1
  [[ -x "$(brew --prefix libpq 2>/dev/null)/bin/psql" ]]
}

step_run() {
  load_brew || { [[ "$WI_DRY_RUN" == 1 ]] && return 0; die "Homebrew missing"; }
  if ! step_check; then wi_run brew install postgresql@15 libpq; fi
  log_info "PostgreSQL 15 is installed and stopped (compose owns port 5432)."
  log_info "For a host Postgres instead: brew services start postgresql@15"
}
```

- [ ] **Step 3: Verify**

Run: `chmod +x steps/*.sh && bats tests/steps.bats && make lint` — Expected: pass, lint clean.
Run: `./install.sh --only docker,postgres --dry-run --yes` — Expected on this Mac: `postgres SKIP (done)`; docker prints `[dry-run] colima start ...` or `SKIP (done)` if Colima is running. `sysctl -n kern.hv_support` printed `1` on this host, so the nested-virt warning must NOT appear.

- [ ] **Step 4: Commit**

```bash
git add steps/50-docker.sh steps/51-postgres.sh
git commit -m "feat: add docker (colima / docker engine) and postgres steps" -- steps/50-docker.sh steps/51-postgres.sh
```

---

### Task 9: `lib/secrets.sh`, steps 60 github-auth and 70 clone-repos

**Files:**
- Create: `lib/secrets.sh`, `tests/secrets.bats`, `steps/60-github-auth.sh`, `steps/70-clone-repos.sh`, `tests/clone-repos.bats`

**Interfaces:**
- Consumes: `WI_SECRETS_FILE`, `wi_run`, `wi_dry`, `WI_YES`, `WI_DRY_RUN`, `config/secrets.env.example`, `config/repos.txt`, `WORKSPACE_DIR`.
- Produces: `secrets_names EXAMPLE`, `secrets_get FILE KEY`, `secrets_write FILE KEY=VALUE...`, `secrets_missing FILE EXAMPLE`, `maven_settings_render USERNAME` (all used by doctor.sh too); `repo_dir_for_url URL`.

- [ ] **Step 1: Write the failing tests `tests/secrets.bats`**

```bash
#!/usr/bin/env bats

setup() {
  load test_helper
  load_lib secrets
  example="$WI_ROOT/config/secrets.env.example"
  f="$BATS_TEST_TMPDIR/secrets.env"
}

@test "secrets_names lists the keys from the example file" {
  run secrets_names "$example"
  [ "$output" = $'GITHUB_TOKEN\nFONTAWESOME_PACKAGE_TOKEN\nLOCALSTACK_AUTH_TOKEN' ]
}

@test "secrets_write then secrets_get round-trips awkward values, mode 600" {
  secrets_write "$f" "GITHUB_TOKEN=ghp_abc" "FONTAWESOME_PACKAGE_TOKEN=a b'c\$d" "LOCALSTACK_AUTH_TOKEN="
  [ "$(secrets_get "$f" GITHUB_TOKEN)" = ghp_abc ]
  [ "$(secrets_get "$f" FONTAWESOME_PACKAGE_TOKEN)" = "a b'c\$d" ]
  [ -z "$(secrets_get "$f" LOCALSTACK_AUTH_TOKEN)" ]
  [ "$(stat -f %Lp "$f" 2>/dev/null || stat -c %a "$f")" = 600 ]
}

@test "secrets_get on a missing file is empty, not an error" {
  [ -z "$(secrets_get "$BATS_TEST_TMPDIR/nope" GITHUB_TOKEN)" ]
}

@test "secrets_missing names empty keys only" {
  secrets_write "$f" "GITHUB_TOKEN=x" "FONTAWESOME_PACKAGE_TOKEN=" "LOCALSTACK_AUTH_TOKEN="
  run secrets_missing "$f" "$example"
  [ "$output" = $'FONTAWESOME_PACKAGE_TOKEN\nLOCALSTACK_AUTH_TOKEN' ]
}

@test "maven_settings_render uses the env token, not a literal" {
  run maven_settings_render edwin
  [[ "$output" == *'<id>github</id>'* ]]
  [[ "$output" == *'<username>edwin</username>'* ]]
  [[ "$output" == *'<password>${env.GITHUB_TOKEN}</password>'* ]]
}
```

- [ ] **Step 2: Write the failing test `tests/clone-repos.bats`**

```bash
#!/usr/bin/env bats

setup() {
  load test_helper
  load_lib common
  export WI_OS=macos WI_ARCH=arm64 WI_DRY_RUN=1
  export WORKSPACE_DIR="$BATS_TEST_TMPDIR/ws"
  # shellcheck source=/dev/null
  source "$WI_ROOT/steps/70-clone-repos.sh"
}

@test "repo_dir_for_url strips .git and joins with WORKSPACE_DIR" {
  [ "$(repo_dir_for_url git@github.com:skoolscout/skoolscout-com.git)" = "$WORKSPACE_DIR/skoolscout-com" ]
}

@test "step_check fails when repos are absent" {
  ! step_check
}

@test "dry-run step_run prints clone commands for every repo and touches nothing" {
  run step_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"git clone --branch develop --recurse-submodules git@github.com:skoolscout/skoolscout-com.git"* ]]
  [[ "$output" == *"jefelabs-docs.git"* ]]
  [ ! -d "$WORKSPACE_DIR/skoolscout-com" ]
}
```

- [ ] **Step 3: Run both** — `bats tests/secrets.bats tests/clone-repos.bats` → fail.

- [ ] **Step 4: Write `lib/secrets.sh`**

```bash
#!/usr/bin/env bash
# lib/secrets.sh — secret names come from config/secrets.env.example; values live
# only in the user's secrets file (mode 600). Nothing here prints a value.

[[ -n "${_WI_SECRETS_LOADED:-}" ]] && return 0
_WI_SECRETS_LOADED=1

# secrets_names EXAMPLE_FILE → one KEY per line
secrets_names() { grep -oE '^[A-Z][A-Z0-9_]*=' "$1" | tr -d '='; }

# secrets_get FILE KEY → value (empty if unset or file missing)
secrets_get() {
  [[ -f "$1" ]] || return 0
  ( set +u; set -a
    # shellcheck source=/dev/null
    source "$1" >/dev/null 2>&1
    set +a
    printf '%s' "${!2:-}" )
}

# secrets_write FILE KEY=VALUE... → rewrite FILE (mode 600); values bash-quoted with %q
secrets_write() {
  local file="$1" tmp kv
  shift
  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"
  for kv in "$@"; do
    printf '%s=%q\n' "${kv%%=*}" "${kv#*=}" >> "$tmp"
  done
  chmod 600 "$tmp"
  mv "$tmp" "$file"
  chmod 600 "$file"
}

# secrets_missing FILE EXAMPLE → names whose value is empty, one per line
secrets_missing() {
  local key
  while IFS= read -r key; do
    [[ -n "$(secrets_get "$1" "$key")" ]] || echo "$key"
  done < <(secrets_names "$2")
}

# maven_settings_render USERNAME → ~/.m2/settings.xml body; token read from env at build time
maven_settings_render() {
  cat <<EOF
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 http://maven.apache.org/xsd/settings-1.0.0.xsd">
  <servers>
    <server>
      <id>github</id>
      <username>$1</username>
      <password>\${env.GITHUB_TOKEN}</password>
    </server>
  </servers>
</settings>
EOF
}
```

- [ ] **Step 5: Write `steps/60-github-auth.sh`**

```bash
#!/usr/bin/env bash
# steps/60-github-auth.sh — gh login, SSH key, secrets file, Maven settings.xml.
STEP_DESC="GitHub: gh login, SSH key, secrets file, Maven settings.xml"
STEP_OS="all"
STEP_SUDO="no"

# shellcheck source=lib/secrets.sh
source "$WI_ROOT/lib/secrets.sh"

SECRETS_EXAMPLE="$WI_ROOT/config/secrets.env.example"
SSH_KEY="$HOME/.ssh/id_ed25519"
MAVEN_SETTINGS="$HOME/.m2/settings.xml"

gh_logged_in() { command_exists gh && gh auth status -h github.com >/dev/null 2>&1; }

step_check() {
  load_brew || return 1
  gh_logged_in || return 1
  [[ -f "$SSH_KEY.pub" ]] || return 1
  [[ -z "$(secrets_missing "$WI_SECRETS_FILE" "$SECRETS_EXAMPLE")" ]] || return 1
  grep -q '<id>github</id>' "$MAVEN_SETTINGS" 2>/dev/null
}

ensure_ssh_key() {
  if [[ ! -f "$SSH_KEY" ]]; then
    if ! wi_dry "generate SSH key $SSH_KEY"; then
      mkdir -p "$HOME/.ssh"
      chmod 700 "$HOME/.ssh"
      ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -C "$USER@$(hostname -s)"
    fi
  fi
  if ! grep -q '^github.com ' "$HOME/.ssh/known_hosts" 2>/dev/null; then
    if ! wi_dry "add github.com to ~/.ssh/known_hosts"; then
      ssh-keyscan -t ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null
    fi
  fi
}

ensure_gh_login() {
  gh_logged_in && return 0
  if [[ "$WI_YES" == 1 ]]; then
    log_warn "gh is not logged in and --yes was given; skipping. Later: gh auth login --git-protocol ssh"
    return 0
  fi
  if wi_dry "gh auth login --git-protocol ssh --web (interactive)"; then return 0; fi
  gh auth login --hostname github.com --git-protocol ssh --web
  if [[ -f "$SSH_KEY.pub" ]] && ! gh ssh-key list 2>/dev/null | grep -qF "$(cut -d' ' -f2 "$SSH_KEY.pub")"; then
    gh ssh-key add "$SSH_KEY.pub" --title "$(hostname -s)" \
      || log_warn "could not upload the SSH key; run: gh ssh-key add $SSH_KEY.pub"
  fi
}

collect_secrets() {
  local key val missing=0
  local entries=()
  while IFS= read -r key; do
    val="${!key:-}"
    [[ -n "$val" ]] || val="$(secrets_get "$WI_SECRETS_FILE" "$key")"
    if [[ -z "$val" && "$WI_YES" != 1 && "$WI_DRY_RUN" != 1 ]]; then
      read -r -s -p "$key (leave empty to skip): " val
      echo
    fi
    [[ -n "$val" ]] || { log_warn "$key is not set"; missing=1; }
    entries+=("$key=$val")
  done < <(secrets_names "$SECRETS_EXAMPLE")
  if wi_dry "write $WI_SECRETS_FILE (mode 600)"; then return 0; fi
  secrets_write "$WI_SECRETS_FILE" ${entries[@]+"${entries[@]}"}
  log_ok "secrets written to $WI_SECRETS_FILE"
  [[ "$missing" == 0 ]] || log_warn "Some secrets are empty; project-deps stays skipped until they are set (re-run: ./install.sh --only github-auth)"
}

ensure_maven_settings() {
  local user
  if grep -q '<id>github</id>' "$MAVEN_SETTINGS" 2>/dev/null; then return 0; fi
  if [[ -f "$MAVEN_SETTINGS" ]]; then
    log_warn "$MAVEN_SETTINGS exists without a <server><id>github</id> entry; not overwriting. Add one that uses \${env.GITHUB_TOKEN}."
    return 0
  fi
  user="$(gh api user -q .login 2>/dev/null || echo "$USER")"
  if wi_dry "write $MAVEN_SETTINGS"; then return 0; fi
  mkdir -p "$HOME/.m2"
  maven_settings_render "$user" > "$MAVEN_SETTINGS"
  log_ok "wrote $MAVEN_SETTINGS"
}

step_run() {
  load_brew || { [[ "$WI_DRY_RUN" == 1 ]] && return 0; die "Homebrew missing"; }
  ensure_ssh_key
  ensure_gh_login
  collect_secrets
  ensure_maven_settings
}
```

- [ ] **Step 6: Write `steps/70-clone-repos.sh`**

```bash
#!/usr/bin/env bash
# steps/70-clone-repos.sh — clone config/repos.txt (with submodules) into WORKSPACE_DIR.
STEP_DESC="Clone skoolscout/jefelabs repos (with submodules) into ${WORKSPACE_DIR}"
STEP_OS="all"
STEP_SUDO="no"

REPOS_FILE="$WI_ROOT/config/repos.txt"

repos() { grep -vE '^[[:space:]]*(#|$)' "$REPOS_FILE"; }

# repo_dir_for_url URL → WORKSPACE_DIR/<name without .git>
repo_dir_for_url() {
  local n
  n="$(basename "$1")"
  printf '%s/%s\n' "$WORKSPACE_DIR" "${n%.git}"
}

# a leading "-" in `git submodule status` marks an uninitialised submodule
submodules_ready() { ! git -C "$1" submodule status --recursive 2>/dev/null | grep -q '^-'; }

step_check() {
  local url branch dir
  while read -r url branch; do
    dir="$(repo_dir_for_url "$url")"
    [[ -d "$dir/.git" ]] || return 1
    submodules_ready "$dir" || return 1
  done < <(repos)
}

step_run() {
  local url branch dir
  if ! wi_dry "mkdir -p $WORKSPACE_DIR"; then mkdir -p "$WORKSPACE_DIR"; fi
  while read -r url branch; do
    dir="$(repo_dir_for_url "$url")"
    if [[ ! -d "$dir/.git" ]]; then
      wi_run git clone --branch "$branch" --recurse-submodules "$url" "$dir"
    else
      log_info "$dir exists; updating submodules"
      wi_run git -C "$dir" submodule update --init --recursive
    fi
  done < <(repos)
}
```

- [ ] **Step 7: Run the tests**

Run: `chmod +x steps/*.sh && bats tests/secrets.bats tests/clone-repos.bats tests/steps.bats && make lint` — Expected: `11 tests, 0 failures`, lint clean.
Run: `./install.sh --only github-auth,clone-repos --dry-run --yes` — Expected: `[dry-run]` lines only; no files under `~/.config/skoolscout` or `~/.m2` are created or changed (`ls -la ~/.m2/settings.xml` mtime unchanged).

- [ ] **Step 8: Commit**

```bash
git add lib/secrets.sh tests/secrets.bats steps/60-github-auth.sh steps/70-clone-repos.sh tests/clone-repos.bats
git commit -m "feat: add secrets helpers, github-auth and clone-repos steps" -- lib/secrets.sh tests/secrets.bats steps/60-github-auth.sh steps/70-clone-repos.sh tests/clone-repos.bats
```

---

### Task 10: Steps 80 local-dev-wiring, 90 project-deps

**Files:**
- Create: `steps/80-local-dev-wiring.sh`, `steps/90-project-deps.sh`, `tests/local-dev-wiring.bats`

**Interfaces:**
- Consumes: `config/dev-hosts.txt`, `WORKSPACE_DIR`, `NODE_VERSION`, `load_secrets`, `wi_run`, `wi_dry`, `load_brew`.
- Produces: `host_present HOST` and `dev_hosts` (doctor.sh reuses the same regex); `WI_HOSTS_FILE` env override for tests (defaults to `/etc/hosts`).

- [ ] **Step 1: Write the failing test `tests/local-dev-wiring.bats`**

```bash
#!/usr/bin/env bats

setup() {
  load test_helper
  load_lib common
  export WI_OS=macos WI_ARCH=arm64 WI_DRY_RUN=1
  export WI_HOSTS_FILE="$BATS_TEST_TMPDIR/hosts"
  # shellcheck source=/dev/null
  source "$WI_ROOT/steps/80-local-dev-wiring.sh"
}

@test "dev_hosts lists the five hosts from config" {
  run dev_hosts
  [ "${#lines[@]}" -eq 5 ]
  [[ "$output" == *skoolscout.com.local* ]]
}

@test "host_present matches whole hostnames and ignores comments" {
  printf '127.0.0.1\tlocalhost\n127.0.0.1\tskoolscout.com.local\n# 127.0.0.1 demo-org.skoolscout.com.local\n' > "$WI_HOSTS_FILE"
  host_present skoolscout.com.local
  ! host_present demo-org.skoolscout.com.local
  ! host_present scout.com.local
}

@test "dry-run step_run prints what it would append without touching the file" {
  printf '127.0.0.1\tlocalhost\n' > "$WI_HOSTS_FILE"
  run step_run
  [[ "$output" == *"append 127.0.0.1 skoolscout.com.local"* ]]
  [ "$(wc -l < "$WI_HOSTS_FILE")" -eq 1 ]
}
```

- [ ] **Step 2: Run it** — fails (step missing).

- [ ] **Step 3: Write `steps/80-local-dev-wiring.sh`**

```bash
#!/usr/bin/env bash
# steps/80-local-dev-wiring.sh — /etc/hosts entries for the dev tenants + mkcert CA.
STEP_DESC="/etc/hosts dev entries + mkcert local CA"
STEP_OS="all"
STEP_SUDO="yes"

HOSTS_FILE="${WI_HOSTS_FILE:-/etc/hosts}"

dev_hosts() { grep -vE '^[[:space:]]*(#|$)' "$WI_ROOT/config/dev-hosts.txt"; }

# host_present HOST — true if an uncommented line maps HOST
host_present() { grep -qE "^[^#]*[[:space:]]$1([[:space:]]|\$)" "$HOSTS_FILE"; }

mkcert_ca_present() {
  command_exists mkcert || return 1
  [[ -f "$(mkcert -CAROOT 2>/dev/null)/rootCA.pem" ]]
}

step_check() {
  load_brew || return 1
  local h
  while IFS= read -r h; do host_present "$h" || return 1; done < <(dev_hosts)
  mkcert_ca_present
}

step_run() {
  load_brew || { [[ "$WI_DRY_RUN" == 1 ]] && return 0; die "Homebrew missing"; }
  local h
  while IFS= read -r h; do
    if host_present "$h"; then log_ok "$h already in $HOSTS_FILE"; continue; fi
    if wi_dry "append 127.0.0.1 $h to $HOSTS_FILE"; then continue; fi
    printf '127.0.0.1\t%s\n' "$h" | sudo tee -a "$HOSTS_FILE" >/dev/null
    log_ok "added $h"
  done < <(dev_hosts)
  if mkcert_ca_present; then log_ok "mkcert CA already present"; else wi_run mkcert -install; fi
}
```

- [ ] **Step 4: Write `steps/90-project-deps.sh`**

```bash
#!/usr/bin/env bash
# steps/90-project-deps.sh — npm/pnpm installs in the cloned repos + Playwright chromium.
# Needs the private-registry tokens from the secrets file; skips (with a warning) without them.
STEP_DESC="npm/pnpm install in cloned repos + Playwright chromium"
STEP_OS="all"
STEP_SUDO="linux"

SS="$WORKSPACE_DIR/skoolscout-com"
TENANTS="$WORKSPACE_DIR/skoolscout-com-tenants"
JL="$WORKSPACE_DIR/jefelabs-com"

playwright_cache() {
  if [[ "$WI_OS" == macos ]]; then echo "$HOME/Library/Caches/ms-playwright"; else echo "$HOME/.cache/ms-playwright"; fi
}

node_loaded() {
  load_brew || return 1
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  local nvm_sh
  nvm_sh="$(brew --prefix nvm 2>/dev/null)/nvm.sh"
  [[ -s "$nvm_sh" ]] || return 1
  set +u
  # shellcheck source=/dev/null
  source "$nvm_sh"
  nvm use "$NODE_VERSION" >/dev/null 2>&1
  set -u
  command_exists node
}

secrets_ok() {
  load_secrets 2>/dev/null || true
  [[ -n "${GITHUB_TOKEN:-}" && -n "${FONTAWESOME_PACKAGE_TOKEN:-}" ]]
}

step_check() {
  [[ -d "$SS/node_modules" && -d "$SS/app-ui/node_modules" && -d "$SS/app-test-e2e-runner/node_modules" ]] || return 1
  [[ -d "$TENANTS/node_modules" && -d "$JL/node_modules" ]] || return 1
  ls -d "$(playwright_cache)"/chromium-* >/dev/null 2>&1
}

step_run() {
  if ! secrets_ok; then
    log_warn "GITHUB_TOKEN / FONTAWESOME_PACKAGE_TOKEN not set; skipping project-deps. Re-run after: ./install.sh --only github-auth"
    return 0
  fi
  local d
  for d in "$SS" "$TENANTS" "$JL"; do
    if [[ ! -d "$d" ]]; then log_warn "$d missing; run the clone-repos step first"; return 0; fi
  done
  node_loaded || { [[ "$WI_DRY_RUN" == 1 ]] && return 0; die "Node $NODE_VERSION not available (node step)"; }
  if command_exists direnv; then wi_run direnv allow "$SS"; fi
  ( cd "$SS" && wi_run npm install --no-workspaces )
  ( cd "$SS/app-ui" && wi_run npm install )
  ( cd "$SS/app-test-e2e-runner" && wi_run npm install && wi_run npx playwright install --with-deps chromium )
  ( cd "$TENANTS" && wi_run npm install )
  ( cd "$JL" && wi_run pnpm install )
}
```

- [ ] **Step 5: Run the tests**

Run: `chmod +x steps/*.sh && bats tests/local-dev-wiring.bats tests/steps.bats && make lint` — `6 tests, 0 failures`, lint clean.
Run: `./install.sh --only local-dev-wiring,project-deps --dry-run --yes` — Expected: hosts already present on this Mac print `✓ ... already in /etc/hosts`; project-deps prints `[dry-run] npm install` lines or `SKIP (done)`. No sudo prompt under `--dry-run`.

- [ ] **Step 6: Commit**

```bash
git add steps/80-local-dev-wiring.sh steps/90-project-deps.sh tests/local-dev-wiring.bats
git commit -m "feat: add local-dev-wiring and project-deps steps" -- steps/80-local-dev-wiring.sh steps/90-project-deps.sh tests/local-dev-wiring.bats
```

---

### Task 11: `doctor.sh`

**Files:**
- Create: `doctor.sh`, `tests/doctor.bats`

**Interfaces:**
- Consumes: `lib/common.sh`, `lib/versions.sh`, `lib/verdict.sh` (`doctor_verdict`), `lib/secrets.sh` (`secrets_missing`), `config/*`.
- Produces: exit 0 only when no check FAILed; `--skip STEP,...` mirrors install.sh step names (`docker`, `github-auth`, `clone-repos`, `local-dev-wiring`) so the Linux smoke test can skip what a container cannot have.

- [ ] **Step 1: Write the failing test `tests/doctor.bats`**

```bash
#!/usr/bin/env bats

setup() {
  load test_helper
  export WI_SECRETS_FILE="$BATS_TEST_TMPDIR/secrets.env"
}

@test "--help exits 0" {
  run "$WI_ROOT/doctor.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--skip"* ]]
}

@test "runs to completion and prints a result line" {
  run "$WI_ROOT/doctor.sh" --skip docker,github-auth,clone-repos,local-dev-wiring
  [ "$status" -le 1 ]
  [[ "$output" == *"passed"*"warnings"*"failed"* ]]
}

@test "skipped sections do not appear" {
  run "$WI_ROOT/doctor.sh" --skip docker,github-auth,clone-repos,local-dev-wiring
  [[ "$output" != *"━━━ Docker"* ]]
  [[ "$output" != *"━━━ GitHub"* ]]
  [[ "$output" != *"━━━ Repos"* ]]
}

@test "reports a missing secrets file as a failure" {
  run "$WI_ROOT/doctor.sh" --skip docker,clone-repos,local-dev-wiring
  [[ "$output" == *"secrets file missing"* ]]
}
```

- [ ] **Step 2: Run it** — fails (`doctor.sh` missing).

- [ ] **Step 3: Write `doctor.sh`**

```bash
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
    -h|--help) echo "Usage: doctor.sh [--skip docker,github-auth,clone-repos,local-dev-wiring]"; exit 0 ;;
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
         node npm pnpm python3 pyenv java gradle terraform cargo rustup docker stripe xmllint zip unzip \
         task-master dotenv ncu claude; do
  check_cmd "$t"
done
if [[ "$WI_OS" == macos ]]; then check_cmd colima; fi

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

if ! skipped docker; then
  log_header "Docker"
  if [[ "$WI_OS" == macos ]]; then export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"; fi
  if docker info >/dev/null 2>&1; then report PASS "docker daemon reachable"; else report FAIL "docker info fails" "colima start (macOS) or re-login for the docker group (Linux)"; fi
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
  while read -r url _; do
    dir="$WORKSPACE_DIR/$(basename "${url%.git}")"
    if [[ ! -d "$dir/.git" ]]; then report FAIL "$dir missing"
    elif git -C "$dir" submodule status --recursive 2>/dev/null | grep -q '^-'; then report WARN "$dir" "submodules not initialised"
    else report PASS "$dir"; fi
  done < <(grep -vE '^[[:space:]]*(#|$)' "$WI_ROOT/config/repos.txt")
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
```

- [ ] **Step 4: Run the tests**

Run: `chmod +x doctor.sh && bats tests/doctor.bats && make lint` — `4 tests, 0 failures`, lint clean.
Run: `./doctor.sh` on this Mac — Expected: a table; exit 1 is fine here (this Mac is not the VM), but every line must be one of ✓ ⚠ ✗ and the Result line must print.

- [ ] **Step 5: Commit**

```bash
git add doctor.sh tests/doctor.bats
git commit -m "feat: add doctor.sh verification" -- doctor.sh tests/doctor.bats
```

---

### Task 12: `bootstrap.sh`

**Files:**
- Create: `bootstrap.sh`, `tests/bootstrap.bats`

**Interfaces:**
- Consumes: `config/apt-packages.txt` (Linux), `install.sh` flags (forwarded verbatim).
- Produces: env overrides `INSTALLER_REPO`, `INSTALLER_REF`, `INSTALLER_DIR`.

- [ ] **Step 1: Write the failing test `tests/bootstrap.bats`**

```bash
#!/usr/bin/env bats

setup() { load test_helper; }

@test "bootstrap.sh is self-contained (sources nothing from lib/)" {
  ! grep -qE 'source .*lib/' "$WI_ROOT/bootstrap.sh"
}

@test "bootstrap.sh refuses unsupported kernels" {
  run bash -c 'uname() { echo Plan9; }; export -f uname; bash "$1"' _ "$WI_ROOT/bootstrap.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported OS"* ]]
}

@test "bootstrap.sh uses a local checkout when run next to install.sh" {
  # Simulate macOS with Xcode CLT and Homebrew already present, and stub install.sh
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
```
`BOOTSTRAP_SKIP_BREW=1` is a test-only escape hatch (bootstrap looks for brew at fixed prefixes, which a test cannot fake); it is documented in the script header.

- [ ] **Step 2: Run it** — fails (file missing).

- [ ] **Step 3: Write `bootstrap.sh`**

```bash
#!/usr/bin/env bash
# bootstrap.sh — the only file a fresh VM needs.
#
#   curl -fsSL https://raw.githubusercontent.com/ecruz165/macos-workspace-installer/main/bootstrap.sh | bash
#   curl -fsSL .../bootstrap.sh | bash -s -- --skip rust,postgres     # forward install.sh flags
#   ./bootstrap.sh                                                     # from a local checkout
#
# Installs OS prerequisites and Homebrew, fetches this repo, then execs install.sh.
# Deliberately self-contained: it cannot source lib/ because lib/ is not here yet.
# Env: INSTALLER_REPO, INSTALLER_REF, INSTALLER_DIR; BOOTSTRAP_SKIP_BREW=1 (tests only).
set -euo pipefail

INSTALLER_REPO="${INSTALLER_REPO:-https://github.com/ecruz165/macos-workspace-installer.git}"
INSTALLER_REF="${INSTALLER_REF:-main}"
INSTALLER_DIR="${INSTALLER_DIR:-$HOME/Development/Workspaces/ecruz165/macos-workspace-installer}"

say()  { printf '\033[1;36m→\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

os=""
case "$(uname -s)" in
  Darwin) os=macos ;;
  Linux)  if grep -qiE '^(ID|ID_LIKE)=.*(ubuntu|debian)' /etc/os-release 2>/dev/null; then os=linux; fi ;;
esac
[[ -n "$os" ]] || fail "Unsupported OS. This installer supports macOS and Ubuntu."

# 1. Base prerequisites: enough to clone the repo.
if [[ "$os" == macos ]]; then
  if ! xcode-select -p >/dev/null 2>&1; then
    say "Installing Xcode Command Line Tools (accept the dialog; this waits for it)"
    xcode-select --install 2>/dev/null || true
    until xcode-select -p >/dev/null 2>&1; do sleep 15; done
  fi
else
  say "Installing git/curl via apt"
  sudo -v
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git curl ca-certificates
fi

# 2. Get the installer: local checkout wins, otherwise clone (HTTPS: no SSH key exists yet).
script_dir=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "$(dirname "${BASH_SOURCE[0]}")/install.sh" ]]; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [[ -n "$script_dir" ]]; then
  INSTALLER_DIR="$script_dir"
  say "Using local checkout $INSTALLER_DIR"
elif [[ -d "$INSTALLER_DIR/.git" ]]; then
  say "Updating $INSTALLER_DIR"
  git -C "$INSTALLER_DIR" fetch --quiet origin "$INSTALLER_REF"
  git -C "$INSTALLER_DIR" checkout --quiet "$INSTALLER_REF"
  git -C "$INSTALLER_DIR" pull --quiet --ff-only origin "$INSTALLER_REF" || true
else
  say "Cloning $INSTALLER_REPO ($INSTALLER_REF) into $INSTALLER_DIR"
  mkdir -p "$(dirname "$INSTALLER_DIR")"
  git clone --quiet --branch "$INSTALLER_REF" "$INSTALLER_REPO" "$INSTALLER_DIR"
fi

# 3. Linux: the full apt prerequisite list now that the repo is present.
if [[ "$os" == linux ]]; then
  say "Installing apt prerequisites from config/apt-packages.txt"
  # shellcheck disable=SC2046
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    $(grep -vE '^[[:space:]]*(#|$)' "$INSTALLER_DIR/config/apt-packages.txt" | tr '\n' ' ')
fi

# 4. Homebrew.
if [[ "${BOOTSTRAP_SKIP_BREW:-0}" != 1 ]]; then
  brew_found=0
  for p in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew; do
    if [[ -x "$p/bin/brew" ]]; then eval "$("$p/bin/brew" shellenv)"; brew_found=1; break; fi
  done
  if [[ "$brew_found" == 0 ]]; then
    say "Installing Homebrew"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    for p in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew; do
      if [[ -x "$p/bin/brew" ]]; then eval "$("$p/bin/brew" shellenv)"; break; fi
    done
  fi
fi

# 5. Hand off. When piped through curl, stdin is the script itself, so reattach the terminal
#    for the interactive prompts (gh login, secrets) if one exists.
say "Running install.sh $*"
if [[ ! -t 0 ]] && ( exec < /dev/tty ) 2>/dev/null; then
  exec "$INSTALLER_DIR/install.sh" "$@" < /dev/tty
else
  exec "$INSTALLER_DIR/install.sh" "$@"
fi
```

- [ ] **Step 4: Run the tests**

Run: `chmod +x bootstrap.sh && bats tests/bootstrap.bats && make lint` — `3 tests, 0 failures`, lint clean.
Run: `./bootstrap.sh --list` on this Mac — Expected: `Using local checkout ...`, then the real step list (Homebrew found, nothing installed).

- [ ] **Step 5: Commit**

```bash
git add bootstrap.sh tests/bootstrap.bats
git commit -m "feat: add curl-pipeable bootstrap.sh" -- bootstrap.sh tests/bootstrap.bats
```

---

### Task 13: Ubuntu smoke test and README

**Files:**
- Create: `tests/Dockerfile.ubuntu`, `tests/smoke-linux.sh`, `.dockerignore`, `README.md`

**Interfaces:**
- Consumes: `bootstrap.sh`, `install.sh`, `doctor.sh` and their `--skip` names.
- Produces: `make smoke-linux`.

- [ ] **Step 1: Write `.dockerignore`**

```
.git
.idea
*.iml
tests/tmp
docs
```

- [ ] **Step 2: Write `tests/Dockerfile.ubuntu`**

```dockerfile
# Ubuntu 24.04 with a passwordless-sudo user, the installer copied in. Used by tests/smoke-linux.sh.
FROM ubuntu:24.04
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y sudo curl ca-certificates git \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -s /bin/bash dev \
 && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev
USER dev
ENV HOME=/home/dev
WORKDIR /home/dev/installer
COPY --chown=dev:dev . .
```

- [ ] **Step 3: Write `tests/smoke-linux.sh`**

```bash
#!/usr/bin/env bash
# tests/smoke-linux.sh — run the full Linux path in a container, then doctor it.
# Skips what a container cannot provide: Docker-in-Docker, GitHub auth, private repos,
# /etc/hosts + mkcert, and the project installs that need the private registries.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

SKIPS="docker,github-auth,clone-repos,project-deps,local-dev-wiring"
PLATFORM="${SMOKE_PLATFORM:-linux/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')}"
IMAGE="workspace-installer-smoke"

docker build --platform "$PLATFORM" -t "$IMAGE" -f tests/Dockerfile.ubuntu .
docker run --rm --platform "$PLATFORM" "$IMAGE" bash -lc "
  set -euo pipefail
  ./bootstrap.sh --yes --skip $SKIPS
  ./doctor.sh --skip $SKIPS
"
```

- [ ] **Step 4: Write `README.md`**

```markdown
# macos-workspace-installer

One command turns a fresh **macOS** or **Ubuntu** VM into a machine that can build,
run and test `skoolscout-com`, `skoolscout-com-tenants` and `jefelabs-com`.

## Quick start (new VM)

```bash
curl -fsSL https://raw.githubusercontent.com/ecruz165/macos-workspace-installer/main/bootstrap.sh | bash
```

Have ready: your GitHub login (a browser opens for `gh auth login`), a GitHub PAT with
`read:packages`, the Font Awesome Pro token, and the LocalStack Pro token. Then open a
new terminal and run `./doctor.sh` from the installer directory
(`~/Development/Workspaces/ecruz165/macos-workspace-installer`).

From a local checkout (shared folder, USB): `./bootstrap.sh`.

## What it installs

| Area | Tools |
|---|---|
| Package manager | Homebrew (macOS) / Linuxbrew (Ubuntu) + `Brewfile.common`, `Brewfile.<os>` |
| Languages | Java 25.0.3 + 21.0.9 (Corretto, sdkman), Gradle 9.6.1, Node 24.18.0 (nvm), Python 3.10.11 (pyenv), Terraform 1.15.8 (tfenv), Rust stable + musl target |
| Containers | Colima + docker CLI (macOS), Docker Engine (Ubuntu) |
| Data | PostgreSQL 15 + `psql` (installed, not started — compose owns 5432) |
| CLI | git, gh, jq, direnv, tmux, neovim, herdr, mkcert, awscli, awslocal, tflocal, localstack, stripe, libxml2, zip |
| npm globals | task-master-ai, dotenv-cli, npm-check-updates |
| Claude Code | native install + plugins from `config/claude-plugins.txt` (superpowers, mattpocock-skills) |
| GUI (macOS) | Ghostty, VS Code, Google Chrome, Postman, Figma |
| Setup | shell rc block, `gh auth login`, SSH key, secrets file, `~/.m2/settings.xml`, repo clones with submodules, `/etc/hosts` dev entries, mkcert CA, `npm install` + Playwright chromium |

Pins live in `config/versions.env`; repos in `config/repos.txt`; hosts in `config/dev-hosts.txt`.

## Running pieces

```bash
./install.sh --list                    # see the steps
./install.sh --only docker,postgres    # just those
./install.sh --skip rust               # everything else
./install.sh --dry-run --yes           # show what would change
./install.sh --only github-auth        # re-enter secrets
./doctor.sh                            # verify; exit 0 = healthy
```

Every step checks itself first, so re-running is safe and fast. Logs:
`~/.local/state/workspace-installer/install-<timestamp>.log` (token values redacted).

## Secrets

Names in `config/secrets.env.example`; values are prompted once and stored in
`~/.config/skoolscout/secrets.env` (mode 600), exported by the shell block. Maven reads
`${env.GITHUB_TOKEN}` from `~/.m2/settings.xml`. Nothing secret is ever in this repo.

## Docker in a macOS VM

Colima needs hardware virtualization inside the VM. That requires an M3 or newer host on
macOS 15+ **and** nested virtualization enabled for the VM (Parallels: Hardware → CPU &
Memory → Advanced). Without it the docker step prints a warning and moves on; Ubuntu VMs
have no such limit.

## Development

```bash
brew install bats-core shellcheck
make lint          # shellcheck everything
make test          # bats unit tests
make list          # step list via macOS's stock bash 3.2
make dry-run       # full dry run on this machine
make smoke-linux   # full Linux path in an Ubuntu 24.04 container (slow: 20–40 min)
```

`lib/verdict.sh` holds `doctor_verdict`, the policy for how loudly the doctor complains
when an installed version drifts from the pin.

## Not installed, on purpose

dnsmasq (unused by any script), Docker Desktop, IntelliJ, yarn/bun, k6, ngrok, the
Qodana CLI (JetBrains installer) and `mtauth-install` (private; install it by hand).
```

- [ ] **Step 5: Verify**

Run: `chmod +x tests/smoke-linux.sh && make lint` — clean.
Run: `make smoke-linux` (Colima must be running: `colima start`). Expected: the container ends with the doctor's `Result` line and exit 0. Every listed Tool line under "Tools" that the skipped steps don't own must be ✓; `brew doctor` may be ⚠. This takes 20–40 minutes; if `stripe/stripe-cli/stripe` or `postgresql@15` fails to install on arm64 Linux, record the failure in the task notes and move it to `Brewfile.macos` rather than blocking.

- [ ] **Step 6: Commit**

```bash
git add .dockerignore tests/Dockerfile.ubuntu tests/smoke-linux.sh README.md
git commit -m "feat: add Ubuntu smoke test and README" -- .dockerignore tests/Dockerfile.ubuntu tests/smoke-linux.sh README.md
```

---

### Task 14: Full verification on this Mac

**Files:** none new.

- [ ] **Step 1: Everything green**

Run: `make lint && make test` — Expected: lint silent; bats reports all files passing (≈55 tests).

- [ ] **Step 2: Real step list with bash 3.2**

Run: `make list` — Expected: 15 steps in order: homebrew, brew-bundle, shell-config, sdkman, node, python, terraform, rust, claude-code, docker, postgres, github-auth, clone-repos, local-dev-wiring, project-deps.

- [ ] **Step 3: Whole-installer dry run**

Run: `make dry-run` — Expected: exit 0; every step is `PASS` or `SKIP (done)`; no file under `$HOME` changed (compare `ls -la ~/.zprofile ~/.m2/settings.xml ~/.config/skoolscout` before and after).

- [ ] **Step 4: Confirm the spec's exclusions and manual items are in the README** (dnsmasq, Docker Desktop, IntelliJ, Qodana, mtauth-install) and that `README.md` documents `INSTALLER_REPO` needing the repo pushed to GitHub before the curl one-liner works. Add a line if missing.

- [ ] **Step 5: Commit any fixes, then report**

Report to the user: test counts, the dry-run summary, and the two things only they can do next — push this repo to GitHub (so the curl one-liner resolves) and run `bootstrap.sh` in a fresh Parallels VM, then `doctor.sh`.
