#!/usr/bin/env bash
# Evaluator phase: invoke the evaluator agent to test a sprint

set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=utils.sh
[[ -z "${HARNESS_STATE:-}" ]] && source "${SCRIPT_DIR}/utils.sh"

invoke_evaluator() {
  local sprint_num="$1"
  local attempt="${2:-1}"
  local dir
  dir=$(sprint_dir "$sprint_num")

  log_info "Evaluator testing sprint $(sprint_pad "$sprint_num") (attempt ${attempt})..."

  local project_type
  project_type=$(json_read "${HARNESS_STATE}/config.json" ".projectType")

  local prompt="Evaluate sprint ${sprint_num}. Read the contract at harness-state/sprints/sprint-$(sprint_pad "$sprint_num")/contract.json. Read harness-state/handoff.json for git branch info and dev server details. Use git diff to understand what changed. Start the dev server, test every criterion, run regression tests if the contract specifies regressionSprints, score the holistic dimensions for project type '${project_type}'. Write your report to harness-state/sprints/sprint-$(sprint_pad "$sprint_num")/eval-report.json and update status.json."

  local mcp_flag=""
  if [[ "$project_type" == "web-frontend" ]] && [[ -f ".mcp.json" ]]; then
    mcp_flag="--mcp-config .mcp.json"
  fi

  local output
  output=$(claude -p "$prompt" \
    --agent evaluator \
    --output-format json \
    --max-turns 100 \
    --dangerously-skip-permissions \
    ${mcp_flag} \
    2>&1) || {
    log_error "Evaluator invocation failed"
    echo "$output" >&2
    return 1
  }

  # Verify outputs
  if ! file_exists "${dir}/eval-report.json"; then
    log_error "Evaluator did not produce eval-report.json"
    return 1
  fi

  local result
  result=$(json_read "${dir}/eval-report.json" ".overallResult")
  local pass_count fail_count blocking
  pass_count=$(json_read "${dir}/eval-report.json" ".passCount")
  fail_count=$(json_read "${dir}/eval-report.json" ".failCount")
  blocking=$(json_read "${dir}/eval-report.json" ".blockingFailures")

  log_cost "evaluator" "$sprint_num" "$output"

  if [[ "$result" == "PASS" ]]; then
    log_success "Sprint $(sprint_pad "$sprint_num") PASSED (${pass_count} pass, ${fail_count} fail, ${blocking} blocking)"
    return 0
  else
    log_warn "Sprint $(sprint_pad "$sprint_num") FAILED (${pass_count} pass, ${fail_count} fail, ${blocking} blocking)"
    log_warn "Summary: $(json_read "${dir}/eval-report.json" ".summary" | head -c 300)"
    return 1
  fi
}

# Run regression tests against all prior sprints
invoke_regression() {
  log_phase "REGRESSION TEST"

  local project_type
  project_type=$(json_read "${HARNESS_STATE}/config.json" ".projectType")

  local prompt="Run regression tests. Read harness-state/regression/registry.json for all prior sprint criteria. For each sprint in the registry, load its contract and test the listed blocking criteria. Start the dev server and test the running application. Write results to harness-state/regression/last-run.json."

  local mcp_flag=""
  if [[ "$project_type" == "web-frontend" ]] && [[ -f ".mcp.json" ]]; then
    mcp_flag="--mcp-config .mcp.json"
  fi

  local output
  output=$(claude -p "$prompt" \
    --agent evaluator \
    --output-format json \
    --max-turns 100 \
    --dangerously-skip-permissions \
    ${mcp_flag} \
    2>&1) || {
    log_error "Regression test invocation failed"
    echo "$output" >&2
    return 1
  }

  if file_exists "${HARNESS_STATE}/regression/last-run.json"; then
    local total_pass total_fail
    total_pass=$(json_read "${HARNESS_STATE}/regression/last-run.json" ".pass" || echo "0")
    total_fail=$(json_read "${HARNESS_STATE}/regression/last-run.json" ".fail" || echo "0")

    if [[ "$total_fail" -gt 0 ]]; then
      log_error "Regression FAILED: ${total_pass} pass, ${total_fail} fail"
      return 1
    else
      log_success "Regression PASSED: ${total_pass} pass, ${total_fail} fail"
    fi
  fi
}
