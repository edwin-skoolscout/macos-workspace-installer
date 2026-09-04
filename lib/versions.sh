#!/usr/bin/env bash
# lib/versions.sh — parse and compare dotted version strings.

[[ -n "${_WI_VERSIONS_LOADED:-}" ]] && return 0
_WI_VERSIONS_LOADED=1

# version_extract TEXT — first "x.y[.z...]" in TEXT (empty if none)
version_extract() {
  printf '%s\n' "$1" | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1
}

# version_major V — leading component
version_major() { printf '%s\n' "${1%%.*}"; }

# version_compare A B — prints -1, 0 or 1; missing components count as 0
version_compare() {
  local -a a b
  IFS=. read -r -a a <<< "$1"
  IFS=. read -r -a b <<< "$2"
  local i n=${#a[@]}
  (( ${#b[@]} > n )) && n=${#b[@]}
  for (( i = 0; i < n; i++ )); do
    local x="${a[i]:-0}" y="${b[i]:-0}"
    if (( 10#$x > 10#$y )); then echo 1; return; fi
    if (( 10#$x < 10#$y )); then echo -1; return; fi
  done
  echo 0
}

# version_ge A B — true if A >= B
version_ge() { [[ "$(version_compare "$1" "$2")" != "-1" ]]; }
