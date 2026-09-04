# tests/test_helper.bash — shared setup for every .bats file
WI_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
export WI_ROOT

# load_lib NAME — source lib/NAME.sh into the test shell
load_lib() {
  # shellcheck source=/dev/null
  source "$WI_ROOT/lib/$1.sh"
}
