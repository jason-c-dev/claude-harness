# Shared setup for all bats tests
# Source this at the top of every .bats file:
#   load '../helpers/test-helper'

PROJECT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
FIXTURE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../helpers/fixtures" && pwd)"

# Mock claude configuration
export MOCK_CLAUDE_FIXTURE_DIR="$FIXTURE_DIR"
export MOCK_CLAUDE_SCENARIO="${MOCK_CLAUDE_SCENARIO:-pass}"

setup() {
  # Create isolated temp directory for each test
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  # Mock claude log and state
  export MOCK_CLAUDE_LOG="$TEST_TEMP_DIR/mock-claude.log"
  export MOCK_CLAUDE_STATE_DIR="$TEST_TEMP_DIR/mock-state"
  mkdir -p "$MOCK_CLAUDE_STATE_DIR"

  # Put mock claude on PATH (before real claude)
  export PATH="$PROJECT_DIR/tests/helpers:$PATH"

  # Work inside temp dir
  cd "$TEST_TEMP_DIR"

  # Set HARNESS_STATE relative to temp dir
  export HARNESS_STATE="harness-state"
  mkdir -p "$HARNESS_STATE/sprints" "$HARNESS_STATE/regression"
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

# Helper: initialize a git repo in the temp dir
init_test_repo() {
  git init . -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "initial" > README.md
  mkdir -p "$HARNESS_STATE/sprints" "$HARNESS_STATE/regression"
  git add README.md "$HARNESS_STATE"
  git commit -q -m "initial commit"
}

# Helper: source a harness lib file (handles SCRIPT_DIR)
source_harness_lib() {
  local lib="$1"
  # Set SCRIPT_DIR so libs can find siblings via source
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/$lib"
}

# Helper: install a fixture file to a destination
install_fixture() {
  local fixture="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  cp "$FIXTURE_DIR/$fixture" "$dest"
}

# Helper: count lines in mock claude log matching a pattern
mock_call_count() {
  local pattern="${1:-.}"
  grep -c "$pattern" "$MOCK_CLAUDE_LOG" 2>/dev/null || echo "0"
}
