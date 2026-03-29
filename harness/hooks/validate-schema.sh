#!/usr/bin/env bash
# PreToolUse hook for Write operations targeting harness-state/sprints/
# Validates JSON files against canonical schemas before allowing the write.
# Exit 2 = block (sends stderr to Claude as feedback)
# Exit 0 = allow

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Only check Write tool
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
if [[ "$TOOL_NAME" != "Write" ]]; then
  exit 0
fi

# Get the file path being written
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Only validate files in harness-state/sprints/
if [[ "$FILE_PATH" != *harness-state/sprints/* ]]; then
  exit 0
fi

# Get the content being written
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)
if [[ -z "$CONTENT" ]]; then
  exit 0
fi

# Determine which schema to validate against based on filename
BASENAME=$(basename "$FILE_PATH")

validate_json() {
  if ! echo "$CONTENT" | jq empty 2>/dev/null; then
    echo "SCHEMA ERROR: $BASENAME is not valid JSON. Please write valid JSON." >&2
    exit 2
  fi
}

case "$BASENAME" in
  contract-proposal.json|contract.json)
    validate_json
    # Must have .criteria array with .id, .description, .testMethod, .testSteps on each
    has_criteria=$(echo "$CONTENT" | jq 'has("criteria") and (.criteria | type == "array") and (.criteria | length > 0)' 2>/dev/null)
    if [[ "$has_criteria" != "true" ]]; then
      cat >&2 <<'FEEDBACK'
SCHEMA ERROR: contract-proposal.json must have a "criteria" array with at least one entry.

Required format:
{
  "sprintNumber": 1,
  "sprintName": "Sprint Name",
  "criteria": [
    {
      "id": "C1-01",
      "category": "functionality",
      "description": "What must be true",
      "testMethod": "command",
      "testSteps": "How to verify",
      "threshold": "pass/fail"
    }
  ],
  "outOfScope": [],
  "regressionSprints": []
}

Do NOT use "features" or "acceptanceCriteria" or "deliverables". Use "criteria" with the exact fields shown above.
FEEDBACK
      exit 2
    fi
    # Validate first criterion has required fields
    missing=$(echo "$CONTENT" | jq -r '.criteria[0] | [if has("id") then empty else "id" end, if has("description") then empty else "description" end, if has("testSteps") then empty else "testSteps" end] | join(", ")' 2>/dev/null)
    if [[ -n "$missing" ]]; then
      echo "SCHEMA ERROR: criteria[0] is missing required fields: $missing. Each criterion needs: id, category, description, testMethod, testSteps, threshold." >&2
      exit 2
    fi
    ;;

  contract-review.json)
    validate_json
    # Must have .decision field with value "accepted" or "revise"
    decision=$(echo "$CONTENT" | jq -r '.decision // empty' 2>/dev/null)
    if [[ -z "$decision" ]]; then
      cat >&2 <<'FEEDBACK'
SCHEMA ERROR: contract-review.json must have a "decision" field.

Required format:
{
  "decision": "accepted",
  "feedback": "Criteria are testable and complete.",
  "missingCriteria": [],
  "unclearCriteria": []
}

Use "decision" (not "reviewVerdict" or "verdict"). Value must be "accepted" or "revise".
FEEDBACK
      exit 2
    fi
    if [[ "$decision" != "accepted" && "$decision" != "revise" ]]; then
      echo "SCHEMA ERROR: contract-review.json .decision must be \"accepted\" or \"revise\", got \"$decision\". Use exactly \"accepted\" or \"revise\"." >&2
      exit 2
    fi
    ;;

  eval-report.json)
    validate_json
    # Must have .overallResult field with value "PASS" or "FAIL" (uppercase)
    result=$(echo "$CONTENT" | jq -r '.overallResult // empty' 2>/dev/null)
    if [[ -z "$result" ]]; then
      cat >&2 <<'FEEDBACK'
SCHEMA ERROR: eval-report.json must have an "overallResult" field.

Required format:
{
  "sprintNumber": 1,
  "attempt": 1,
  "timestamp": "2026-01-01T00:00:00Z",
  "overallResult": "PASS",
  "scores": {
    "dimension1": {"score": 8, "max": 10, "threshold": 7, "pass": true}
  },
  "criteriaResults": [
    {"id": "C1-01", "result": "PASS", "evidence": "Description of what was observed"},
    {"id": "C1-02", "result": "FAIL", "evidence": "What went wrong", "severity": "blocking", "suggestedFix": "How to fix"}
  ],
  "passCount": 10,
  "failCount": 2,
  "blockingFailures": 1,
  "summary": "Brief summary"
}

Use "overallResult" (not "result" or "verdict"). Value must be "PASS" or "FAIL" (uppercase).
Use "criteriaResults" array (not "features" or "score"). Use "passCount"/"failCount" (not nested under "score").
FEEDBACK
      exit 2
    fi
    if [[ "$result" != "PASS" && "$result" != "FAIL" ]]; then
      echo "SCHEMA ERROR: eval-report.json .overallResult must be \"PASS\" or \"FAIL\" (uppercase), got \"$result\"." >&2
      exit 2
    fi
    # Check criteriaResults exists
    has_cr=$(echo "$CONTENT" | jq 'has("criteriaResults")' 2>/dev/null)
    if [[ "$has_cr" != "true" ]]; then
      echo "SCHEMA ERROR: eval-report.json must have a \"criteriaResults\" array. Use \"criteriaResults\" (not \"features\" or \"results\")." >&2
      exit 2
    fi
    # Check passCount exists
    has_pc=$(echo "$CONTENT" | jq 'has("passCount")' 2>/dev/null)
    if [[ "$has_pc" != "true" ]]; then
      echo "SCHEMA ERROR: eval-report.json must have \"passCount\" and \"failCount\" as top-level integer fields (not nested under \"score\")." >&2
      exit 2
    fi
    ;;

  status.json)
    validate_json
    # Must have .status field
    status_val=$(echo "$CONTENT" | jq -r '.status // empty' 2>/dev/null)
    if [[ -z "$status_val" ]]; then
      echo "SCHEMA ERROR: status.json must have a \"status\" field. Values: \"ready-for-eval\", \"pass\", \"fail\", \"blocked\"." >&2
      exit 2
    fi
    ;;

  *)
    # Unknown file in sprints dir -- allow
    ;;
esac

exit 0
