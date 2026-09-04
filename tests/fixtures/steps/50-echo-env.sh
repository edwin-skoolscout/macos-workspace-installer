#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
STEP_DESC="echo-env: prints the environment steps receive"
STEP_OS="all"
STEP_SUDO="no"
step_check() { return 1; }
step_run()   { echo "WI_DRY_RUN=$WI_DRY_RUN WI_YES=$WI_YES WI_OS=$WI_OS NODE_VERSION=$NODE_VERSION"; }
