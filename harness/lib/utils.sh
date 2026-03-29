#!/usr/bin/env bash
# Shared utilities for the harness orchestrator

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

HARNESS_STATE="harness-state"

log_info() {
  echo -e "${BLUE}[harness]${NC} $*" >&2
}

log_success() {
  echo -e "${GREEN}[harness]${NC} $*" >&2
}

log_warn() {
  echo -e "${YELLOW}[harness]${NC} $*" >&2
}

log_error() {
  echo -e "${RED}[harness]${NC} $*" >&2
}

log_phase() {
  echo "" >&2
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
  echo -e "${CYAN}  $*${NC}" >&2
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
  echo "" >&2
}

# Pad sprint number to 2 digits
sprint_pad() {
  printf '%02d' "$1"
}

# Sprint directory path
sprint_dir() {
  echo "${HARNESS_STATE}/sprints/sprint-$(sprint_pad "$1")"
}

# Slugify a string for use in branch names
slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | cut -c1-50
}

# Read a JSON field from a file
json_read() {
  local file="$1"
  local field="$2"
  jq -r "$field" "$file" 2>/dev/null || echo ""
}

# Check if a file exists and is non-empty
file_exists() {
  [[ -f "$1" && -s "$1" ]]
}

# Initialize harness-state directory with config
init_harness_state() {
  local prompt="$1"
  local project_type="${2:-general}"

  mkdir -p "${HARNESS_STATE}/regression" "${HARNESS_STATE}/sprints"

  # Write config
  cat > "${HARNESS_STATE}/config.json" <<EOF
{
  "userPrompt": $(echo "$prompt" | jq -Rs .),
  "projectType": "${project_type}",
  "contextStrategy": "${CONTEXT_STRATEGY:-reset}",
  "model": "${MODEL:-opus}",
  "maxSprintAttempts": ${MAX_SPRINT_ATTEMPTS:-3},
  "maxContractRounds": ${MAX_CONTRACT_ROUNDS:-3},
  "costCapPerSprint": ${COST_CAP_PER_SPRINT:-25.00},
  "totalCostCap": ${TOTAL_COST_CAP:-200.00}
}
EOF

  # Initialize cost log
  echo '{"invocations": [], "totalCost": 0}' > "${HARNESS_STATE}/cost-log.json"

  # Initialize regression registry
  echo '{"sprints": {}, "lastFullRun": null}' > "${HARNESS_STATE}/regression/registry.json"

  # Initialize progress log
  cat > "${HARNESS_STATE}/progress.md" <<EOF
# Harness Progress Log

**Project**: ${prompt}
**Started**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
**Model**: ${MODEL:-opus}
**Context strategy**: ${CONTEXT_STRATEGY:-reset}

---

EOF
}

# Log cost for an invocation
log_cost() {
  local role="$1"
  local sprint="$2"
  local output_json="$3"

  # Extract usage from claude output if available
  local input_tokens output_tokens
  input_tokens=$(echo "$output_json" | jq -r '.usage.input_tokens // 0' 2>/dev/null || echo "0")
  output_tokens=$(echo "$output_json" | jq -r '.usage.output_tokens // 0' 2>/dev/null || echo "0")

  local cost_file="${HARNESS_STATE}/cost-log.json"
  local entry
  entry=$(cat <<EOF
{
  "role": "${role}",
  "sprint": ${sprint},
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "inputTokens": ${input_tokens},
  "outputTokens": ${output_tokens}
}
EOF
)

  # Append to cost log
  local tmp
  tmp=$(mktemp)
  jq ".invocations += [${entry}]" "$cost_file" > "$tmp" && mv "$tmp" "$cost_file"
}

# Check if total cost exceeds cap
check_cost_cap() {
  local total_cost_cap
  total_cost_cap=$(json_read "${HARNESS_STATE}/config.json" ".totalCostCap")
  # On Pro/Max plan, we can't directly measure cost, so this is a sprint-count heuristic
  # For API usage, this would check actual token costs
  log_info "Cost tracking: see ${HARNESS_STATE}/cost-log.json for invocation details"
}

# Update progress.md with a sprint entry
update_progress() {
  local sprint_num="$1"
  local status="$2"
  local attempt="${3:-1}"
  local merge_sha="${4:-}"

  local sprint_name
  sprint_name=$(jq -r ".sprints[$(( sprint_num - 1 ))] | .name // .title // \"Sprint ${sprint_num}\"" "${HARNESS_STATE}/sprint-plan.json" 2>/dev/null)

  cat >> "${HARNESS_STATE}/progress.md" <<EOF

## Sprint $(sprint_pad "$sprint_num"): ${sprint_name}

- **Status**: ${status}
- **Attempt**: ${attempt}
- **Time**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
$([ -n "$merge_sha" ] && echo "- **Merge commit**: ${merge_sha}")

EOF
}

# Update handoff.json after a sprint completes
update_handoff() {
  local sprint_num="$1"
  local merge_sha="${2:-}"
  local tag="${3:-}"
  local harness_branch="${4:-}"

  local handoff_file="${HARNESS_STATE}/handoff.json"

  if ! file_exists "$handoff_file"; then
    # Initialize handoff
    cat > "$handoff_file" <<EOF
{
  "projectName": "",
  "completedSprints": [],
  "currentSprint": 1,
  "totalSprints": 0,
  "completedFeatures": [],
  "keyFiles": {},
  "techStack": {},
  "outstandingIssues": [],
  "devServerCommand": "",
  "devServerPort": 0,
  "git": {
    "harnessBranch": "",
    "latestTag": "",
    "latestMergeSha": "",
    "prNumbers": []
  }
}
EOF
  fi

  # Update completed sprints and git info
  local tmp
  tmp=$(mktemp)
  jq \
    --argjson sprint "$sprint_num" \
    --arg tag "$tag" \
    --arg sha "$merge_sha" \
    --arg branch "$harness_branch" \
    '
    .completedSprints += [$sprint] |
    .completedSprints |= unique |
    .currentSprint = ($sprint + 1) |
    .git.latestTag = $tag |
    .git.latestMergeSha = $sha |
    (if $branch != "" then .git.harnessBranch = $branch else . end)
    ' "$handoff_file" > "$tmp" && mv "$tmp" "$handoff_file"
}

# Update regression registry with blocking criteria from a sprint
update_regression_registry() {
  local sprint_num="$1"
  local contract_path
  contract_path="$(sprint_dir "$sprint_num")/contract.json"
  local registry="${HARNESS_STATE}/regression/registry.json"

  if ! file_exists "$contract_path"; then
    return
  fi

  # Extract blocking criteria IDs (all criteria are considered blocking by default)
  local criteria_ids
  criteria_ids=$(jq '[.criteria[].id]' "$contract_path")

  local tmp
  tmp=$(mktemp)
  jq \
    --arg sprint "$sprint_num" \
    --arg path "sprints/sprint-$(sprint_pad "$sprint_num")/contract.json" \
    --argjson criteria "$criteria_ids" \
    '.sprints[$sprint] = {"criteria": $criteria, "contractPath": $path}' \
    "$registry" > "$tmp" && mv "$tmp" "$registry"
}
