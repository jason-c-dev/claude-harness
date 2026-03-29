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
  mkdir -p "$HARNESS_STATE/sprints" "$HARNESS_STATE/regression"
  export MAX_CONTRACT_ROUNDS=3

  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/utils.sh"
  source "$PROJECT_DIR/harness/lib/invoke.sh"
  init_harness_state "Test" "general"
  cp "$FIXTURE_DIR/product-spec-minimal.md" "$HARNESS_STATE/product-spec.md"
  cp "$FIXTURE_DIR/sprint-plan-2sprint.json" "$HARNESS_STATE/sprint-plan.json"
  cp "$FIXTURE_DIR/handoff-initial.json" "$HARNESS_STATE/handoff.json"
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

@test "negotiate_contract: creates contract.json on acceptance" {
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/contract.sh"

  negotiate_contract 1
  [[ -f "$HARNESS_STATE/sprints/sprint-01/contract.json" ]]
}

@test "negotiate_contract: creates proposal and review" {
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/contract.sh"

  negotiate_contract 1
  [[ -f "$HARNESS_STATE/sprints/sprint-01/contract-proposal.json" ]]
  [[ -f "$HARNESS_STATE/sprints/sprint-01/contract-review.json" ]]
}

@test "negotiate_contract: invokes both generator and evaluator" {
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/contract.sh"

  negotiate_contract 1
  grep -q "agent=generator" "$MOCK_CLAUDE_LOG"
  grep -q "agent=evaluator" "$MOCK_CLAUDE_LOG"
}

@test "negotiate_contract: revise then accept takes 2 rounds" {
  export MOCK_CLAUDE_SCENARIO="revise-then-accept"
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/contract.sh"

  negotiate_contract 1

  # Should have called generator twice (two proposals)
  gen_count=$(grep -c "agent=generator" "$MOCK_CLAUDE_LOG")
  [[ "$gen_count" -eq 2 ]]
}

@test "negotiate_contract: returns 0 on success" {
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/contract.sh"

  run negotiate_contract 1
  [[ "$status" -eq 0 ]]
}
