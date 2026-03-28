#!/usr/bin/env bash
# Hook: Stop
# Checks for premature completion when sprints are still pending.
# Exit 2 = block (send feedback to Claude), 0 = allow

set -euo pipefail

INPUT=$(cat)
HARNESS_STATE="harness-state"

# Only check if we're in an active harness session
if [[ ! -f "${HARNESS_STATE}/sprint-plan.json" ]]; then
  exit 0
fi

# Check for in-progress sprints
for dir in "${HARNESS_STATE}"/sprints/sprint-*; do
  if [[ -d "$dir" && -f "${dir}/status.json" ]]; then
    status=$(jq -r '.status // ""' "${dir}/status.json" 2>/dev/null || echo "")
    sprint_name=$(basename "$dir")

    if [[ "$status" == "active" || "$status" == "negotiating" ]]; then
      echo "${sprint_name} is still ${status}. Complete the current sprint before stopping." >&2
      exit 2
    fi

    if [[ "$status" == "ready-for-eval" ]]; then
      echo "${sprint_name} is ready for evaluation but hasn't been evaluated yet. Run the evaluator before stopping." >&2
      exit 2
    fi
  fi
done

exit 0
