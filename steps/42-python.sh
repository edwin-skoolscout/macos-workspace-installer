#!/usr/bin/env bash
# shellcheck disable=SC2034  # STEP_* are read by install.sh after sourcing
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
