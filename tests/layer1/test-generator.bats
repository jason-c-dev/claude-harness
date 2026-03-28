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
  init_harness_state "Test" "general"

  # Install a contract so generator has something to work with
  cp "$FIXTURE_DIR/contract-sprint01.json" "$HARNESS_STATE/sprints/sprint-01/contract.json"
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

@test "invoke_generator: creates status.json" {
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/generator.sh"

  invoke_generator 1 1
  [[ -f "$HARNESS_STATE/sprints/sprint-01/status.json" ]]
  result=$(jq -r '.status' "$HARNESS_STATE/sprints/sprint-01/status.json")
  [[ "$result" == "ready-for-eval" ]]
}

@test "invoke_generator: creates generator-log.md" {
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/generator.sh"

  invoke_generator 1 1
  [[ -f "$HARNESS_STATE/sprints/sprint-01/generator-log.md" ]]
}

@test "invoke_generator: returns 0 on success" {
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/generator.sh"

  run invoke_generator 1 1
  [[ "$status" -eq 0 ]]
}

@test "invoke_generator: returns 2 when blocked" {
  export MOCK_CLAUDE_SCENARIO="fail-generator-blocked"
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/generator.sh"

  run invoke_generator 1 1
  [[ "$status" -eq 2 ]]
}

@test "invoke_generator: logs invocation" {
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/generator.sh"

  invoke_generator 1 1
  grep -q "agent=generator" "$MOCK_CLAUDE_LOG"
}
