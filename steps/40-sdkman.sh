#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
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
