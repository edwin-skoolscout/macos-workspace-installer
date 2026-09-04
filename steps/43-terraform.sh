#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
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
