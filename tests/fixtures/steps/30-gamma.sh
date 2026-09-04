#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
STEP_DESC="gamma: only for plan9"
STEP_OS="plan9"
STEP_SUDO="no"
step_check() { return 1; }
step_run()   { touch "$WI_FIXTURE_DIR/gamma.done"; }
