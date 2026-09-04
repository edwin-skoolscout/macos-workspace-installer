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
