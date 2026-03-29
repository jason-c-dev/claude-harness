#!/usr/bin/env bats
# Hook validation tests for on-generator-stop.sh, on-evaluator-stop.sh, and on-stop.sh
# Covers: exit codes, error messages, and contract/eval validation flows

load 'helpers/test-helper'

# ===========================================================================
# on-generator-stop.sh
# ===========================================================================

@test "on-generator-stop: allows when no active sprint directory exists" {
  # No sprint directories under harness-state/sprints/
  run run_hook "on-generator-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-generator-stop: allows when status is ready-for-eval and generator-log.md exists" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "status-ready-for-eval.json" "$HARNESS_STATE/sprints/sprint-01/status.json"
  install_fixture "generator-log.md" "$HARNESS_STATE/sprints/sprint-01/generator-log.md"
  run run_hook "on-generator-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-generator-stop: allows when status is blocked" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "status-blocked.json" "$HARNESS_STATE/sprints/sprint-01/status.json"
  run run_hook "on-generator-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-generator-stop: blocks when status is active" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "status-active.json" "$HARNESS_STATE/sprints/sprint-01/status.json"
  run run_hook "on-generator-stop.sh"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"not 'ready-for-eval' or 'blocked'"* ]]
}

@test "on-generator-stop: blocks when ready-for-eval but generator-log.md is missing" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "status-ready-for-eval.json" "$HARNESS_STATE/sprints/sprint-01/status.json"
  # No generator-log.md
  run run_hook "on-generator-stop.sh"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"generator-log.md"* ]]
}

@test "on-generator-stop: allows during contract negotiation phase" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  echo '{"sprintNumber": 1, "criteria": []}' > "$HARNESS_STATE/sprints/sprint-01/contract-proposal.json"
  # No contract.json and no status.json -- contract negotiation in progress
  run run_hook "on-generator-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-generator-stop: detects fix-* directory with active status and blocks" {
  mkdir -p "$HARNESS_STATE/sprints/fix-issue-42"
  install_fixture "status-active.json" "$HARNESS_STATE/sprints/fix-issue-42/status.json"
  run run_hook "on-generator-stop.sh"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"not 'ready-for-eval' or 'blocked'"* ]]
}

@test "on-generator-stop: detects refactor-* directory with active status and blocks" {
  mkdir -p "$HARNESS_STATE/sprints/refactor-cleanup"
  install_fixture "status-active.json" "$HARNESS_STATE/sprints/refactor-cleanup/status.json"
  run run_hook "on-generator-stop.sh"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"not 'ready-for-eval' or 'blocked'"* ]]
}

@test "on-generator-stop: allows when only terminal-status sprint exists (pass)" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "status-pass.json" "$HARNESS_STATE/sprints/sprint-01/status.json"
  run run_hook "on-generator-stop.sh"
  [[ "$status" -eq 0 ]]
}

# ===========================================================================
# on-evaluator-stop.sh
# ===========================================================================

@test "on-evaluator-stop: allows when no sprint is being evaluated" {
  # No sprint directories at all
  run run_hook "on-evaluator-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-evaluator-stop: allows when only terminal-status sprints exist" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "status-pass.json" "$HARNESS_STATE/sprints/sprint-01/status.json"
  run run_hook "on-evaluator-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-evaluator-stop: allows when eval-report.json has valid overallResult and criteriaResults" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "status-ready-for-eval.json" "$HARNESS_STATE/sprints/sprint-01/status.json"
  install_fixture "contract-3criteria.json" "$HARNESS_STATE/sprints/sprint-01/contract.json"
  install_fixture "eval-report-pass.json" "$HARNESS_STATE/sprints/sprint-01/eval-report.json"
  run run_hook "on-evaluator-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-evaluator-stop: allows with FAIL overallResult when report structure is valid" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "status-ready-for-eval.json" "$HARNESS_STATE/sprints/sprint-01/status.json"
  install_fixture "contract-3criteria.json" "$HARNESS_STATE/sprints/sprint-01/contract.json"
  install_fixture "eval-report-fail.json" "$HARNESS_STATE/sprints/sprint-01/eval-report.json"
  run run_hook "on-evaluator-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-evaluator-stop: blocks when eval-report.json is missing" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "status-ready-for-eval.json" "$HARNESS_STATE/sprints/sprint-01/status.json"
  # No eval-report.json
  run run_hook "on-evaluator-stop.sh"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"eval-report.json"* ]]
}

@test "on-evaluator-stop: blocks when overallResult field is missing from eval-report.json" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "status-ready-for-eval.json" "$HARNESS_STATE/sprints/sprint-01/status.json"
  install_fixture "eval-report-malformed.json" "$HARNESS_STATE/sprints/sprint-01/eval-report.json"
  run run_hook "on-evaluator-stop.sh"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"overallResult"* ]]
}

@test "on-evaluator-stop: blocks when criteriaResults field is missing from eval-report.json" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "status-ready-for-eval.json" "$HARNESS_STATE/sprints/sprint-01/status.json"
  # Create eval report with overallResult but no criteriaResults
  cat > "$HARNESS_STATE/sprints/sprint-01/eval-report.json" <<'FIXTURE'
{
  "sprintNumber": 1,
  "overallResult": "FAIL",
  "summary": "Missing criteriaResults array."
}
FIXTURE
  run run_hook "on-evaluator-stop.sh"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"criteriaResults"* ]]
}

@test "on-evaluator-stop: blocks when criteria count in eval report is less than contract" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "status-ready-for-eval.json" "$HARNESS_STATE/sprints/sprint-01/status.json"
  install_fixture "contract-3criteria.json" "$HARNESS_STATE/sprints/sprint-01/contract.json"
  # Create eval report with only 1 criteriaResult (contract has 3)
  cat > "$HARNESS_STATE/sprints/sprint-01/eval-report.json" <<'FIXTURE'
{
  "sprintNumber": 1,
  "overallResult": "FAIL",
  "criteriaResults": [
    { "id": "C1-01", "result": "PASS", "evidence": "Only one criterion tested" }
  ],
  "summary": "Incomplete: only 1 of 3 criteria tested."
}
FIXTURE
  run run_hook "on-evaluator-stop.sh"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"criteria"* ]]
}

@test "on-evaluator-stop: allows when criteria count in eval report matches contract" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "status-ready-for-eval.json" "$HARNESS_STATE/sprints/sprint-01/status.json"
  install_fixture "contract-3criteria.json" "$HARNESS_STATE/sprints/sprint-01/contract.json"
  install_fixture "eval-report-pass.json" "$HARNESS_STATE/sprints/sprint-01/eval-report.json"
  # eval-report-pass.json has 3 criteriaResults, contract-3criteria.json has 3 criteria
  run run_hook "on-evaluator-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-evaluator-stop: allows for valid contract review with decision field present" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "contract-3criteria.json" "$HARNESS_STATE/sprints/sprint-01/contract-proposal.json"
  install_fixture "contract-review-accepted.json" "$HARNESS_STATE/sprints/sprint-01/contract-review.json"
  # No contract.json -- this is contract review mode
  run run_hook "on-evaluator-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-evaluator-stop: blocks during contract review when contract-review.json is missing" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "contract-3criteria.json" "$HARNESS_STATE/sprints/sprint-01/contract-proposal.json"
  # No contract.json, no contract-review.json
  run run_hook "on-evaluator-stop.sh"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"contract-review.json"* ]]
}

@test "on-evaluator-stop: blocks during contract review when decision field is missing" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "contract-3criteria.json" "$HARNESS_STATE/sprints/sprint-01/contract-proposal.json"
  install_fixture "contract-review-no-decision.json" "$HARNESS_STATE/sprints/sprint-01/contract-review.json"
  # No contract.json -- contract review mode
  run run_hook "on-evaluator-stop.sh"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"decision"* ]]
}

# ===========================================================================
# on-stop.sh
# ===========================================================================

@test "on-stop: allows when no sprint-plan.json exists" {
  # No sprint-plan.json -- not a harness session
  run run_hook "on-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-stop: allows when all sprints have terminal status (pass)" {
  install_fixture "sprint-plan-3sprint.json" "$HARNESS_STATE/sprint-plan.json"
  mkdir -p "$HARNESS_STATE/sprints/sprint-01" "$HARNESS_STATE/sprints/sprint-02" "$HARNESS_STATE/sprints/sprint-03"
  install_fixture "status-pass.json" "$HARNESS_STATE/sprints/sprint-01/status.json"
  install_fixture "status-pass.json" "$HARNESS_STATE/sprints/sprint-02/status.json"
  install_fixture "status-pass.json" "$HARNESS_STATE/sprints/sprint-03/status.json"
  run run_hook "on-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-stop: blocks when any sprint has status active" {
  install_fixture "sprint-plan-3sprint.json" "$HARNESS_STATE/sprint-plan.json"
  mkdir -p "$HARNESS_STATE/sprints/sprint-01" "$HARNESS_STATE/sprints/sprint-02"
  install_fixture "status-pass.json" "$HARNESS_STATE/sprints/sprint-01/status.json"
  install_fixture "status-active.json" "$HARNESS_STATE/sprints/sprint-02/status.json"
  run run_hook "on-stop.sh"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"still active"* ]]
}

@test "on-stop: blocks when any sprint has status negotiating" {
  install_fixture "sprint-plan-3sprint.json" "$HARNESS_STATE/sprint-plan.json"
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  echo '{"status": "negotiating", "attempt": 1}' > "$HARNESS_STATE/sprints/sprint-01/status.json"
  run run_hook "on-stop.sh"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"still negotiating"* ]]
}

@test "on-stop: blocks when any sprint has status ready-for-eval" {
  install_fixture "sprint-plan-3sprint.json" "$HARNESS_STATE/sprint-plan.json"
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "status-ready-for-eval.json" "$HARNESS_STATE/sprints/sprint-01/status.json"
  run run_hook "on-stop.sh"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"ready for evaluation"* ]]
}

@test "on-stop: allows when sprint directories exist but have no status.json files" {
  install_fixture "sprint-plan-3sprint.json" "$HARNESS_STATE/sprint-plan.json"
  mkdir -p "$HARNESS_STATE/sprints/sprint-01" "$HARNESS_STATE/sprints/sprint-02"
  # No status.json in any sprint directory
  run run_hook "on-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-stop: allows with a mix of pass and fail terminal statuses" {
  install_fixture "sprint-plan-3sprint.json" "$HARNESS_STATE/sprint-plan.json"
  mkdir -p "$HARNESS_STATE/sprints/sprint-01" "$HARNESS_STATE/sprints/sprint-02"
  install_fixture "status-pass.json" "$HARNESS_STATE/sprints/sprint-01/status.json"
  echo '{"status": "fail", "attempt": 3}' > "$HARNESS_STATE/sprints/sprint-02/status.json"
  run run_hook "on-stop.sh"
  [[ "$status" -eq 0 ]]
}
