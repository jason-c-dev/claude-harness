#!/usr/bin/env bash
# Hook: SubagentStop for evaluator
# Verifies the evaluator produced a valid eval report.
# Exit 2 = block (send feedback to Claude), 0 = allow

set -euo pipefail

INPUT=$(cat)
HARNESS_STATE="harness-state"

# Find the sprint that's being evaluated
EVAL_SPRINT=""
for dir in "${HARNESS_STATE}"/sprints/sprint-* "${HARNESS_STATE}"/sprints/fix-* "${HARNESS_STATE}"/sprints/refactor-*; do
  if [[ -d "$dir" ]]; then
    status_file="${dir}/status.json"
    if [[ -f "$status_file" ]]; then
      status=$(jq -r '.status // ""' "$status_file" 2>/dev/null || echo "")
      if [[ "$status" == "ready-for-eval" ]]; then
        EVAL_SPRINT="$dir"
        break
      fi
    fi
  fi
done

# Also check for contract review mode
for dir in "${HARNESS_STATE}"/sprints/sprint-*; do
  if [[ -d "$dir" && -f "${dir}/contract-proposal.json" && ! -f "${dir}/contract.json" ]]; then
    # Contract review mode - check for review file
    if [[ ! -f "${dir}/contract-review.json" ]]; then
      echo "Evaluator finished contract review but contract-review.json is missing." >&2
      exit 2
    fi
    # Validate review JSON
    if ! jq -e '.decision' "${dir}/contract-review.json" &>/dev/null; then
      echo "contract-review.json is missing 'decision' field (must be 'accepted' or 'revise')." >&2
      exit 2
    fi
    exit 0
  fi
done

if [[ -z "$EVAL_SPRINT" ]]; then
  exit 0
fi

# Check eval report exists
if [[ ! -f "${EVAL_SPRINT}/eval-report.json" ]]; then
  echo "Evaluator finished but eval-report.json is missing. Write your evaluation report." >&2
  exit 2
fi

# Validate eval report structure (tolerate field name variations)
if ! jq -e '.overallResult // .result // .verdict' "${EVAL_SPRINT}/eval-report.json" &>/dev/null; then
  echo "eval-report.json is missing result field (overallResult, result, or verdict)." >&2
  exit 2
fi

# criteriaResults may be named differently or structured as nested features
if ! jq -e '.criteriaResults // .features // .score // .results' "${EVAL_SPRINT}/eval-report.json" &>/dev/null; then
  echo "eval-report.json is missing results data." >&2
  exit 2
fi

# Check that criteria count matches contract
if [[ -f "${EVAL_SPRINT}/contract.json" ]]; then
  contract_count=$(jq '.criteria | length' "${EVAL_SPRINT}/contract.json" 2>/dev/null || echo "0")
  report_count=$(jq '.criteriaResults | length' "${EVAL_SPRINT}/eval-report.json" 2>/dev/null || echo "0")

  if [[ "$report_count" -lt "$contract_count" ]]; then
    echo "eval-report.json has ${report_count} criteria results but the contract has ${contract_count} criteria. Test ALL criteria." >&2
    exit 2
  fi
fi

exit 0
