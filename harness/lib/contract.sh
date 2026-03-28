#!/usr/bin/env bash
# Contract negotiation: generator proposes, evaluator reviews, iterate

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"

negotiate_contract() {
  local sprint_num="$1"
  local max_rounds="${MAX_CONTRACT_ROUNDS:-3}"
  local dir
  dir=$(sprint_dir "$sprint_num")

  log_phase "CONTRACT NEGOTIATION — Sprint $(sprint_pad "$sprint_num")"

  mkdir -p "$dir"

  for round in $(seq 1 "$max_rounds"); do
    log_info "Round ${round}/${max_rounds}"

    # Generator proposes
    log_info "Generator proposing contract..."
    local gen_prompt="Propose a sprint contract for sprint ${sprint_num}. Read harness-state/product-spec.md and harness-state/sprint-plan.json for context. Read harness-state/handoff.json for current state. Write your proposal to harness-state/sprints/sprint-$(sprint_pad "$sprint_num")/contract-proposal.json."

    if [[ "$round" -gt 1 ]]; then
      gen_prompt="${gen_prompt} The evaluator has provided feedback in harness-state/sprints/sprint-$(sprint_pad "$sprint_num")/contract-review.json. Address all feedback in your revised proposal."
    fi

    claude -p "$gen_prompt" \
      --agent generator \
      --output-format json \
      --max-turns 30 \
      2>&1 > /dev/null || {
      log_error "Generator contract proposal failed"
      return 1
    }

    if ! file_exists "${dir}/contract-proposal.json"; then
      log_error "Generator did not produce contract-proposal.json"
      return 1
    fi

    local criteria_count
    criteria_count=$(jq '.criteria | length' "${dir}/contract-proposal.json" 2>/dev/null || echo "0")
    log_info "Proposal: ${criteria_count} criteria"

    # Evaluator reviews
    log_info "Evaluator reviewing contract..."
    claude -p "Review the sprint contract proposal at harness-state/sprints/sprint-$(sprint_pad "$sprint_num")/contract-proposal.json. Check that criteria are testable, complete, and cover the sprint's features from the sprint plan. Write your review to harness-state/sprints/sprint-$(sprint_pad "$sprint_num")/contract-review.json." \
      --agent evaluator \
      --output-format json \
      --max-turns 30 \
      2>&1 > /dev/null || {
      log_error "Evaluator contract review failed"
      return 1
    }

    if ! file_exists "${dir}/contract-review.json"; then
      log_error "Evaluator did not produce contract-review.json"
      return 1
    fi

    local decision
    decision=$(json_read "${dir}/contract-review.json" ".decision")

    if [[ "$decision" == "accepted" ]]; then
      # Copy proposal to contract
      cp "${dir}/contract-proposal.json" "${dir}/contract.json"
      log_success "Contract agreed (round ${round}, ${criteria_count} criteria)"
      return 0
    fi

    log_warn "Evaluator requested revisions: $(json_read "${dir}/contract-review.json" ".feedback" | head -c 200)"
  done

  # Max rounds reached -- accept the latest proposal
  log_warn "Max negotiation rounds reached. Accepting latest proposal."
  cp "${dir}/contract-proposal.json" "${dir}/contract.json"
}
