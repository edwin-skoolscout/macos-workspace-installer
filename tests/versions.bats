#!/usr/bin/env bats

setup() {
  load test_helper
  load_lib versions
}

@test "version_extract pulls the first dotted number from tool output" {
  [ "$(version_extract 'openjdk version "25.0.3" 2026-01-20 LTS')" = 25.0.3 ]
  [ "$(version_extract 'v24.18.0')" = 24.18.0 ]
  [ "$(version_extract 'Terraform v1.15.8')" = 1.15.8 ]
  [ "$(version_extract 'Python 3.10.11')" = 3.10.11 ]
  [ "$(version_extract 'Gradle 9.6.1')" = 9.6.1 ]
  [ "$(version_extract '25.0.3-amzn')" = 25.0.3 ]
  [ -z "$(version_extract 'no version here')" ]
}

@test "version_major" {
  [ "$(version_major 25.0.3)" = 25 ]
  [ "$(version_major 9)" = 9 ]
}

@test "version_compare orders numerically, not lexically" {
  [ "$(version_compare 1.15.8 1.7.5)" = 1 ]
  [ "$(version_compare 1.7.5 1.15.8)" = -1 ]
  [ "$(version_compare 24.18.0 24.18.0)" = 0 ]
  [ "$(version_compare 24.18 24.18.0)" = 0 ]
  [ "$(version_compare 3.10.11 3.9)" = 1 ]
}

@test "version_ge" {
  version_ge 25.0.4 25.0.3
  version_ge 25.0.3 25.0.3
  ! version_ge 21.0.9 25.0.3
}
