#!/usr/bin/env bash
# Generator phase: invoke the generator agent to implement a sprint

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"

invoke_generator() {
  local sprint_num="$1"
  local attempt="${2:-1}"
  local dir
  dir=$(sprint_dir "$sprint_num")

  log_info "Generator implementing sprint $(sprint_pad "$sprint_num") (attempt ${attempt})..."

  local prompt="Implement sprint ${sprint_num}. Read the contract at harness-state/sprints/sprint-$(sprint_pad "$sprint_num")/contract.json. Read harness-state/handoff.json for current project state and harness-state/progress.md for history."

  if [[ "$attempt" -gt 1 ]] && file_exists "${dir}/eval-report.json"; then
    prompt="${prompt} This is retry attempt ${attempt}. Read the evaluator's failure report at harness-state/sprints/sprint-$(sprint_pad "$sprint_num")/eval-report.json and fix every blocking failure."
  fi

  prompt="${prompt} When done, write your work log to harness-state/sprints/sprint-$(sprint_pad "$sprint_num")/generator-log.md and set harness-state/sprints/sprint-$(sprint_pad "$sprint_num")/status.json to {\"status\": \"ready-for-eval\", \"attempt\": ${attempt}}."

  local output
  output=$(claude -p "$prompt" \
    --agent generator \
    --output-format json \
    --max-turns 200 \
    2>&1) || {
    log_error "Generator invocation failed"
    echo "$output" >&2
    return 1
  }

  # Verify outputs
  if ! file_exists "${dir}/status.json"; then
    log_error "Generator did not produce status.json"
    return 1
  fi

  local status
  status=$(json_read "${dir}/status.json" ".status")

  if [[ "$status" == "blocked" ]]; then
    log_error "Generator is blocked. See ${dir}/generator-log.md"
    return 2
  fi

  if [[ "$status" != "ready-for-eval" ]]; then
    log_warn "Generator status is '${status}', expected 'ready-for-eval'"
  fi

  log_cost "generator" "$sprint_num" "$output"
  log_success "Generator completed sprint $(sprint_pad "$sprint_num") (attempt ${attempt})"
}
