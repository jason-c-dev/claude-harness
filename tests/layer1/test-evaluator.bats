#!/usr/bin/env bats

load '../helpers/test-helper'

setup() {
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
  mkdir -p "$HARNESS_STATE/sprints/sprint-01" "$HARNESS_STATE/regression"

  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/utils.sh"
  source "$PROJECT_DIR/harness/lib/invoke.sh"
  init_harness_state "Test" "general"

  cp "$FIXTURE_DIR/contract-sprint01.json" "$HARNESS_STATE/sprints/sprint-01/contract.json"
  cp "$FIXTURE_DIR/handoff-initial.json" "$HARNESS_STATE/handoff.json"
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

@test "invoke_evaluator: returns 0 on PASS" {
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/evaluator.sh"

  run invoke_evaluator 1 1
  [[ "$status" -eq 0 ]]
}

@test "invoke_evaluator: returns 1 on FAIL" {
  export MOCK_CLAUDE_SCENARIO="fail-eval"
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/evaluator.sh"

  run invoke_evaluator 1 1
  [[ "$status" -eq 1 ]]
}

@test "invoke_evaluator: creates eval-report.json" {
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/evaluator.sh"

  invoke_evaluator 1 1
  [[ -f "$HARNESS_STATE/sprints/sprint-01/eval-report.json" ]]
  jq -e '.overallResult' "$HARNESS_STATE/sprints/sprint-01/eval-report.json" > /dev/null
}

@test "invoke_evaluator: logs invocation" {
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/evaluator.sh"

  invoke_evaluator 1 1
  grep -q "agent=evaluator" "$MOCK_CLAUDE_LOG"
}

@test "invoke_regression: returns 0 on pass" {
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/evaluator.sh"

  run invoke_regression
  [[ "$status" -eq 0 ]]
}
