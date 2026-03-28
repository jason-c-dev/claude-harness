#!/usr/bin/env bash
# Planner phase: invoke the planner agent to produce product spec and sprint plan

set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=utils.sh
[[ -z "${HARNESS_STATE:-}" ]] && source "${SCRIPT_DIR}/utils.sh"

invoke_planner() {
  local mode="${1:-new}"  # "new" or "extend"

  log_phase "PLANNER PHASE (${mode})"

  local prompt
  if [[ "$mode" == "extend" ]]; then
    prompt="You are extending an existing project. Read harness-state/product-spec.md, harness-state/handoff.json, and harness-state/sprint-plan.json to understand what exists. Then read harness-state/config.json for the new feature request. Design additive sprints that build on the existing architecture. APPEND to product-spec.md and ADD new sprints to sprint-plan.json."
  else
    prompt="Read harness-state/config.json for the user prompt and project type. Produce a comprehensive product spec in harness-state/product-spec.md and sprint decomposition in harness-state/sprint-plan.json."
  fi

  log_info "Invoking planner..."

  if ! invoke_claude --agent planner --max-turns 50 "$prompt"; then
    log_error "Planner invocation failed"
    return 1
  fi

  # Verify outputs
  if ! file_exists "${HARNESS_STATE}/product-spec.md"; then
    log_error "Planner did not produce product-spec.md"
    return 1
  fi

  if ! file_exists "${HARNESS_STATE}/sprint-plan.json"; then
    log_error "Planner did not produce sprint-plan.json"
    return 1
  fi

  # Validate sprint-plan.json is valid JSON with sprints
  local sprint_count
  sprint_count=$(jq '.sprints | length' "${HARNESS_STATE}/sprint-plan.json" 2>/dev/null) || {
    log_error "sprint-plan.json is not valid JSON"
    return 1
  }

  log_success "Planner produced spec with ${sprint_count} sprints"
  echo "$sprint_count"
}
