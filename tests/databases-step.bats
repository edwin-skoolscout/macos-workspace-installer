#!/usr/bin/env bats

setup() {
  load test_helper
  load_lib common
  export WI_OS=macos WI_ARCH=arm64 WI_DRY_RUN=0 WI_YES=1
  export WORKSPACE_DIR="$BATS_TEST_TMPDIR/ws"
  export DATABASES_DIR="$BATS_TEST_TMPDIR/dbs"
  export WI_REPOS_FILE="$BATS_TEST_TMPDIR/repos.txt"
  export WI_DATABASES_FILE="$BATS_TEST_TMPDIR/databases.txt"
  printf 'git@github.com:skoolscout/skoolscout-com.git develop\ngit@github.com:acme/ghost.git main\n' > "$WI_REPOS_FILE"
  printf 'skoolscout-com skoolscout_db 5432 skoolscout admin123 app-service/init-scripts\nghost ghost_db 5434 u p\n' > "$WI_DATABASES_FILE"
  mkdir -p "$WORKSPACE_DIR/skoolscout/skoolscout-com/.git"   # cloned; ghost is not
  stub="$BATS_TEST_TMPDIR/create-database-stub.sh"
  printf '#!/usr/bin/env bash\necho "create-database $*"\n' > "$stub"; chmod +x "$stub"
  export WI_CREATE_DATABASE_CMD="$stub"
  # shellcheck source=/dev/null
  source "$WI_ROOT/steps/75-databases.sh"
}

@test "applicable_databases lists only entries whose repo is cloned" {
  run applicable_databases
  [ "$output" = "skoolscout_db" ]
}

@test "step_check fails while a cloned repo's instance is missing and passes once it is initialised" {
  ! step_check
  mkdir -p "$DATABASES_DIR/skoolscout_db"; : > "$DATABASES_DIR/skoolscout_db/PG_VERSION"
  step_check
}

@test "step_check passes when nothing applies" {
  rm "$WI_REPOS_FILE"
  step_check
}

@test "step_run hands off to create-database.sh sync" {
  run step_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"create-database sync"* ]]
}

@test "under --dry-run step_run only prints the sync command" {
  export WI_DRY_RUN=1
  run step_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"*"sync"* ]]
}
