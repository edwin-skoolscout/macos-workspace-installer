#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
STEP_DESC="delta: creates a marker file"
STEP_OS="all"
STEP_SUDO="no"
step_check() { [[ -f "$WI_FIXTURE_DIR/delta.done" ]]; }
step_run()   { touch "$WI_FIXTURE_DIR/delta.done"; }
