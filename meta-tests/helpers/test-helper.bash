# Shared setup/teardown and utility helpers for meta-tests
# Source this at the top of every .bats file:
#   load 'helpers/test-helper'

# Resolve directories
# META_DIR = the meta-tests/ directory (where .bats files live)
# HARNESS_PROJECT_DIR = the project root (parent of meta-tests/)
META_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
FIXTURE_DIR="${META_DIR}/helpers/fixtures"
HARNESS_PROJECT_DIR="$(cd "$META_DIR/.." && pwd)"

setup() {
  # Create isolated temp directory for each test
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  # Work inside temp dir
  cd "$TEST_TEMP_DIR"

  # Set HARNESS_STATE relative to temp dir
  export HARNESS_STATE="harness-state"
  mkdir -p "$HARNESS_STATE/sprints" "$HARNESS_STATE/regression"
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

# Initialize a git repo in the temp dir with an initial commit
init_test_repo() {
  git init . -q -b main
  git config user.email "meta-test@test.com"
  git config user.name "Meta Test"
  echo "initial" > README.md
  mkdir -p "$HARNESS_STATE/sprints" "$HARNESS_STATE/regression"
  git add README.md "$HARNESS_STATE"
  git commit -q -m "initial commit"
}

# Source a harness lib file with correct SCRIPT_DIR so sibling imports resolve
source_harness_lib() {
  local lib="$1"
  # Set SCRIPT_DIR to the harness/lib directory so libs can find siblings via source
  SCRIPT_DIR="$HARNESS_PROJECT_DIR/harness/lib"
  export SCRIPT_DIR
  source "$HARNESS_PROJECT_DIR/harness/lib/$lib"
}

# Copy a fixture file from meta-tests/helpers/fixtures/ to a destination, creating parent directories
install_fixture() {
  local fixture="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  cp "$FIXTURE_DIR/$fixture" "$dest"
}

# Assert a jq field value with clear error messages on failure
assert_json_field() {
  local file="$1"
  local jq_path="$2"
  local expected="$3"

  local actual
  actual=$(jq -r "$jq_path" "$file" 2>/dev/null)

  if [[ "$actual" != "$expected" ]]; then
    echo "JSON assertion failed for $file"
    echo "  Path:     $jq_path"
    echo "  Expected: $expected"
    echo "  Actual:   $actual"
    return 1
  fi
}

# Run a hook script with empty stdin and capture exit code
run_hook() {
  local hook_name="$1"
  local hook_path="$HARNESS_PROJECT_DIR/harness/hooks/${hook_name}"
  local exit_code=0
  echo "" | bash "$hook_path" 2>&1 || exit_code=$?
  return "$exit_code"
}
