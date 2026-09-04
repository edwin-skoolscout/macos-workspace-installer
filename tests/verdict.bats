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
