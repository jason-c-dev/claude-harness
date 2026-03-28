#!/usr/bin/env bash
# Hook: SubagentStop for generator
# Verifies the generator produced required output files.
# Exit 2 = block (send feedback to Claude), 0 = allow

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Find the active sprint directory
HARNESS_STATE="harness-state"
ACTIVE_SPRINT=""

for dir in "${HARNESS_STATE}"/sprints/sprint-* "${HARNESS_STATE}"/sprints/fix-* "${HARNESS_STATE}"/sprints/refactor-*; do
  if [[ -d "$dir" ]]; then
    status_file="${dir}/status.json"
    if [[ -f "$status_file" ]]; then
      status=$(jq -r '.status // ""' "$status_file" 2>/dev/null || echo "")
      if [[ "$status" == "ready-for-eval" || "$status" == "active" || "$status" == "blocked" ]]; then
        ACTIVE_SPRINT="$dir"
        break
      fi
    fi
    # Also check for contract negotiation (no status.json yet, but proposal exists)
    if [[ -f "${dir}/contract-proposal.json" && ! -f "${dir}/contract.json" ]]; then
      ACTIVE_SPRINT="$dir"
      break
    fi
  fi
done

if [[ -z "$ACTIVE_SPRINT" ]]; then
  # No active sprint found, allow
  exit 0
fi

# Check if this was an implementation phase (status.json should exist)
if [[ -f "${ACTIVE_SPRINT}/status.json" ]]; then
  status=$(jq -r '.status // ""' "${ACTIVE_SPRINT}/status.json" 2>/dev/null || echo "")

  if [[ "$status" != "ready-for-eval" && "$status" != "blocked" ]]; then
    echo "Generator finished but status is '${status}', not 'ready-for-eval' or 'blocked'. Did you forget to update status.json?" >&2
    exit 2
  fi

  # Check generator log exists
  if [[ "$status" == "ready-for-eval" && ! -f "${ACTIVE_SPRINT}/generator-log.md" ]]; then
    echo "Generator marked ready-for-eval but generator-log.md is missing. Write your work log before completing." >&2
    exit 2
  fi
fi

# Check git commits reference criteria (warning only)
if command -v git &>/dev/null; then
  recent_commits=$(git log --oneline -10 2>/dev/null || echo "")
  if [[ -n "$recent_commits" ]] && ! echo "$recent_commits" | grep -q "harness\|C[0-9]"; then
    echo "Warning: recent commits don't follow harness convention (harness(sprint-NN): desc [C-ID])" >&2
    # Don't block, just warn
  fi
fi

exit 0
