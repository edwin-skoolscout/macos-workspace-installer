#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
STEP_DESC="beta: always fails"
STEP_OS="all"
STEP_SUDO="no"
step_check() { return 1; }
step_run()   { echo "beta exploding"; return 3; }
