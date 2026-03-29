#!/usr/bin/env bats

load '../helpers/test-helper'

setup() {
  # Standard setup
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR
  export MOCK_CLAUDE_LOG="$TEST_TEMP_DIR/mock-claude.log"
  export MOCK_CLAUDE_STATE_DIR="$TEST_TEMP_DIR/mock-state"
  export MOCK_CLAUDE_SCENARIO="pass"
  mkdir -p "$MOCK_CLAUDE_STATE_DIR"

  PROJECT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  FIXTURE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../helpers/fixtures" && pwd)"
  export MOCK_CLAUDE_FIXTURE_DIR="$FIXTURE_DIR"
  export PATH="$PROJECT_DIR/tests/helpers:$PATH"

  cd "$TEST_TEMP_DIR"
  export HARNESS_STATE="harness-state"
  mkdir -p "$HARNESS_STATE/sprints" "$HARNESS_STATE/regression"

  # Initialize state
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/utils.sh"
  source "$PROJECT_DIR/harness/lib/invoke.sh"
  init_harness_state "Test project" "general"
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

@test "invoke_planner: returns sprint count as last line" {
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/planner.sh"

  result=$(invoke_planner "new" | tail -1)
  [[ "$result" == "2" ]]
}

@test "invoke_planner: creates product-spec.md" {
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/planner.sh"

  invoke_planner "new"
  [[ -f "$HARNESS_STATE/product-spec.md" ]]
  [[ -s "$HARNESS_STATE/product-spec.md" ]]
}

@test "invoke_planner: creates sprint-plan.json" {
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/planner.sh"

  invoke_planner "new"
  [[ -f "$HARNESS_STATE/sprint-plan.json" ]]
  jq -e '.sprints' "$HARNESS_STATE/sprint-plan.json" > /dev/null
}

@test "invoke_planner: logs mock invocation" {
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/planner.sh"

  invoke_planner "new"
  grep -q "agent=planner" "$MOCK_CLAUDE_LOG"
}

@test "invoke_planner: extend mode passes correct prompt" {
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/planner.sh"

  invoke_planner "extend"
  grep -q "extend" "$MOCK_CLAUDE_LOG"
}
