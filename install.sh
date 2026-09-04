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
  cat <<'USAGE'
Usage: install.sh [OPTIONS]

  --only STEP[,STEP...]   run only these steps
  --skip STEP[,STEP...]   run everything except these steps
  --list                  list steps and exit
  --dry-run               print mutating commands instead of running them
  --yes, -y               never prompt; use defaults, skip missing secrets
  --fail-fast             stop at the first failed step
  --help, -h              this text

Steps are addressed by name (file name without number and .sh), e.g. sdkman.
USAGE
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
  if [[ -n "$ONLY" ]]; then in_csv "$1" "$ONLY"; return; fi
  if in_csv "$1" "$SKIP"; then return 1; fi
  return 0
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
