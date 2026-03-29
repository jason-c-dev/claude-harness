#!/usr/bin/env bash
# Harness Orchestrator
#
# Coordinates the Planner-Generator-Evaluator pipeline for building software
# through structured sprint cycles with context resets.
#
# Usage:
#   bash harness/orchestrate.sh "Build a kanban board" [options]
#   bash harness/orchestrate.sh --extend "Add collaboration features"
#   bash harness/orchestrate.sh --fix "Cards vanish on rapid drag"
#   bash harness/orchestrate.sh --refactor "Extract state into Zustand"
#   bash harness/orchestrate.sh --resume --from-sprint 4
#   bash harness/orchestrate.sh --regression
#
# Options:
#   --project-type TYPE   web-frontend|backend-api|cli-tool|general (default: general)
#   --context-strategy S  reset|compact (default: reset)
#   --model MODEL         opus|sonnet (default: opus)
#   --max-cost DOLLARS    Total cost cap (default: 200)
#   --from-sprint N       Start/resume from sprint N
#   --extend PROMPT       Add features to existing project
#   --fix DESCRIPTION     Fix a specific bug
#   --refactor DESC       Refactor without behavior change
#   --regression          Run all prior evaluations
#   --dry-run             Show what would happen without executing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/invoke.sh"
source "${SCRIPT_DIR}/lib/git.sh"
source "${SCRIPT_DIR}/lib/planner.sh"
source "${SCRIPT_DIR}/lib/contract.sh"
source "${SCRIPT_DIR}/lib/generator.sh"
source "${SCRIPT_DIR}/lib/evaluator.sh"

# Defaults
MODE="new"
USER_PROMPT=""
PROJECT_TYPE="general"
CONTEXT_STRATEGY="reset"
MODEL="opus"
TOTAL_COST_CAP=200
COST_CAP_PER_SPRINT=25
MAX_SPRINT_ATTEMPTS=3
MAX_CONTRACT_ROUNDS=3
FROM_SPRINT=1
DRY_RUN=false

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --extend)
        MODE="extend"
        USER_PROMPT="$2"
        shift 2
        ;;
      --fix)
        MODE="fix"
        USER_PROMPT="$2"
        shift 2
        ;;
      --refactor)
        MODE="refactor"
        USER_PROMPT="$2"
        shift 2
        ;;
      --regression)
        MODE="regression"
        shift
        ;;
      --resume)
        MODE="resume"
        shift
        ;;
      --project-type)
        PROJECT_TYPE="$2"
        shift 2
        ;;
      --context-strategy)
        CONTEXT_STRATEGY="$2"
        shift 2
        ;;
      --model)
        MODEL="$2"
        shift 2
        ;;
      --max-cost)
        TOTAL_COST_CAP="$2"
        shift 2
        ;;
      --from-sprint)
        FROM_SPRINT="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      -*)
        log_error "Unknown option: $1"
        exit 1
        ;;
      *)
        USER_PROMPT="$1"
        shift
        ;;
    esac
  done

  # Validate
  if [[ "$MODE" == "new" && -z "$USER_PROMPT" ]]; then
    log_error "Usage: bash harness/orchestrate.sh \"Your project description\" [options]"
    exit 1
  fi
}

# Run a single sprint cycle: contract -> implement -> evaluate
run_sprint() {
  local sprint_num="$1"
  local harness_branch="$2"
  local dir
  dir=$(sprint_dir "$sprint_num")

  local sprint_name
  sprint_name=$(jq -r ".sprints[$(( sprint_num - 1 ))] | .name // .title // \"Sprint ${sprint_num}\"" "${HARNESS_STATE}/sprint-plan.json" 2>/dev/null)

  log_phase "SPRINT $(sprint_pad "$sprint_num"): ${sprint_name}"

  mkdir -p "$dir"

  # Contract negotiation (if no contract exists)
  if ! file_exists "${dir}/contract.json"; then
    negotiate_contract "$sprint_num"
    git_commit_harness_state "harness(contract): sprint-$(sprint_pad "$sprint_num") agreed"
  else
    log_info "Contract already exists, skipping negotiation"
  fi

  # Implementation + evaluation loop
  local max_attempts="${MAX_SPRINT_ATTEMPTS}"
  for attempt in $(seq 1 "$max_attempts"); do
    log_info "Attempt ${attempt}/${max_attempts}"

    # Create sprint branch
    local sprint_branch
    sprint_branch=$(git_create_sprint_branch "$harness_branch" "$sprint_num")

    # Generator implements
    if ! invoke_generator "$sprint_num" "$attempt"; then
      local gen_status
      gen_status=$(json_read "${dir}/status.json" ".status" 2>/dev/null || echo "failed")
      if [[ "$gen_status" == "blocked" ]]; then
        log_error "Generator is blocked. Aborting sprint."
        git_fail_sprint_attempt "$harness_branch" "$sprint_num" "$attempt"
        return 2
      fi
      git_fail_sprint_attempt "$harness_branch" "$sprint_num" "$attempt"
      continue
    fi

    # Evaluator tests
    if invoke_evaluator "$sprint_num" "$attempt"; then
      # PASS: merge, tag, handoff
      local merge_sha
      merge_sha=$(git_merge_sprint "$harness_branch" "$sprint_num" "$attempt")
      local tag="harness/sprint-$(sprint_pad "$sprint_num")/pass"

      update_handoff "$sprint_num" "$merge_sha" "$tag" "$harness_branch"
      update_progress "$sprint_num" "PASS" "$attempt" "$merge_sha"
      update_regression_registry "$sprint_num"
      git_commit_harness_state "harness(eval): sprint-$(sprint_pad "$sprint_num") PASS"

      log_success "Sprint $(sprint_pad "$sprint_num") PASSED on attempt ${attempt}"
      return 0
    else
      # FAIL: tag, delete branch, retry
      git_fail_sprint_attempt "$harness_branch" "$sprint_num" "$attempt"
      update_progress "$sprint_num" "FAIL" "$attempt"
      log_warn "Sprint $(sprint_pad "$sprint_num") failed on attempt ${attempt}"
    fi
  done

  log_error "Sprint $(sprint_pad "$sprint_num") failed all ${max_attempts} attempts"
  update_progress "$sprint_num" "FAILED (all attempts exhausted)" "$max_attempts"
  git_commit_harness_state "harness(eval): sprint-$(sprint_pad "$sprint_num") FAILED"
  return 1
}

# Mode: new build
run_new_build() {
  local project_slug
  project_slug=$(slugify "$USER_PROMPT")

  log_phase "HARNESS: NEW BUILD"
  log_info "Project: ${USER_PROMPT}"
  log_info "Slug: ${project_slug}"
  log_info "Type: ${PROJECT_TYPE}"
  log_info "Model: ${MODEL}"
  log_info "Context strategy: ${CONTEXT_STRATEGY}"

  # Ensure we're in a git repo (auto-init for new projects)
  if ! git rev-parse --git-dir &>/dev/null; then
    log_info "No git repo found. Initializing..."
    git init -q -b main
    git config user.email "${GIT_EMAIL:-harness@claude-harness.dev}"
    git config user.name "${GIT_NAME:-Claude Harness}"
    echo "# ${project_slug}" > README.md
    git add README.md
    git commit -q -m "initial commit"
  fi

  # Initialize state
  init_harness_state "$USER_PROMPT" "$PROJECT_TYPE"

  # Create harness branch
  local harness_branch
  harness_branch=$(git_create_harness_branch "$project_slug")

  # Initialize handoff.json with harness branch
  cat > "${HARNESS_STATE}/handoff.json" <<EOF
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
    "harnessBranch": "${harness_branch}",
    "latestTag": "",
    "latestMergeSha": "",
    "prNumbers": []
  }
}
EOF

  git_commit_harness_state "harness: initialize state for ${project_slug}"

  # Plan
  local sprint_count
  sprint_count=$(invoke_planner "new")
  git_commit_harness_state "harness(plan): product spec and sprint plan"
  git tag "harness/plan"

  log_info "Sprint plan: ${sprint_count} sprints"

  # Sprint loop
  local failed_sprints=0
  for sprint_num in $(seq "$FROM_SPRINT" "$sprint_count"); do
    if ! run_sprint "$sprint_num" "$harness_branch"; then
      (( failed_sprints++ ))
      log_warn "Sprint ${sprint_num} failed. Continuing to next sprint."
    fi
    check_cost_cap
  done

  # Completion
  log_phase "HARNESS COMPLETE"

  local pr_body
  pr_body=$(generate_pr_body)
  git_create_pr "$harness_branch" "$project_slug" "$pr_body"

  if [[ "$failed_sprints" -gt 0 ]]; then
    log_warn "${failed_sprints} sprint(s) failed. Review harness-state/progress.md for details."
  else
    log_success "All sprints passed!"
  fi
}

# Mode: extend existing project
run_extend() {
  log_phase "HARNESS: EXTEND"
  log_info "New features: ${USER_PROMPT}"

  if ! file_exists "${HARNESS_STATE}/config.json"; then
    log_error "No existing harness state found. Run a new build first."
    exit 1
  fi

  # Update config with new prompt
  local tmp
  tmp=$(mktemp)
  jq --arg prompt "$USER_PROMPT" '.userPrompt = $prompt' \
    "${HARNESS_STATE}/config.json" > "$tmp" && mv "$tmp" "${HARNESS_STATE}/config.json"

  local harness_branch
  harness_branch=$(json_read "${HARNESS_STATE}/handoff.json" ".git.harnessBranch")
  git checkout "$harness_branch"

  # Plan (extend mode)
  local sprint_count
  sprint_count=$(invoke_planner "extend")
  git_commit_harness_state "harness(plan): extend with new features"

  local total_sprints
  total_sprints=$(json_read "${HARNESS_STATE}/sprint-plan.json" ".sprints | length")
  local new_start=$(( total_sprints - sprint_count + 1 ))

  log_info "Added ${sprint_count} new sprints (${new_start}-${total_sprints})"

  # Run new sprints
  for sprint_num in $(seq "$new_start" "$total_sprints"); do
    run_sprint "$sprint_num" "$harness_branch" || true
    check_cost_cap
  done

  log_phase "EXTEND COMPLETE"
  local pr_body
  pr_body=$(generate_pr_body)
  git_create_pr "$harness_branch" "extend-$(slugify "$USER_PROMPT")" "$pr_body"
}

# Mode: fix a bug
run_fix() {
  log_phase "HARNESS: FIX"
  log_info "Bug: ${USER_PROMPT}"

  if ! file_exists "${HARNESS_STATE}/config.json"; then
    log_error "No existing harness state found."
    exit 1
  fi

  local harness_branch
  harness_branch=$(json_read "${HARNESS_STATE}/handoff.json" ".git.harnessBranch")
  git checkout "$harness_branch"

  # Create GitHub issue
  git_create_issue "Bug: ${USER_PROMPT}" "## Reported behavior\n${USER_PROMPT}\n\n## Harness tracking\nAutomated fix via harness."

  # Determine fix sprint number
  local fix_count
  fix_count=$(find "${HARNESS_STATE}/sprints" -maxdepth 1 -name "fix-*" -type d 2>/dev/null | wc -l | tr -d ' ')
  local fix_id="fix-$(printf '%03d' $(( fix_count + 1 )))"
  local fix_dir="${HARNESS_STATE}/sprints/${fix_id}"
  mkdir -p "$fix_dir"

  # Generate fix contract via generator
  log_info "Generating fix contract..."
  claude -p "Create a fix contract for this bug: ${USER_PROMPT}. Write a surgical contract with criteria that verify the fix AND regression criteria from related sprints. Write to harness-state/sprints/${fix_id}/contract.json." \
    --agent generator \
    --output-format json \
    --max-turns 30 \
    2>&1 > /dev/null

  # Run fix sprint
  local sprint_branch
  sprint_branch="${harness_branch}/${fix_id}"
  git checkout -b "$sprint_branch" "$harness_branch"

  # Generate fix
  claude -p "Fix this bug: ${USER_PROMPT}. Read the contract at harness-state/sprints/${fix_id}/contract.json. Write your log to harness-state/sprints/${fix_id}/generator-log.md. Set status to ready-for-eval." \
    --agent generator \
    --output-format json \
    --max-turns 100 \
    2>&1 > /dev/null

  # Evaluate fix
  if invoke_evaluator "${fix_id}" 1; then
    git checkout "$harness_branch"
    git merge --no-ff "$sprint_branch" -m "harness(${fix_id}): merge fix (PASS)"
    git tag "harness/${fix_id}/pass"
    git branch -d "$sprint_branch"
    update_regression_registry "$fix_id"
    git_commit_harness_state "harness(${fix_id}): fix verified"
    log_success "Fix verified and merged"
  else
    log_error "Fix did not pass evaluation. See ${fix_dir}/eval-report.json"
  fi
}

# Mode: refactor
run_refactor() {
  log_phase "HARNESS: REFACTOR"
  log_info "Refactor: ${USER_PROMPT}"

  local harness_branch
  harness_branch=$(json_read "${HARNESS_STATE}/handoff.json" ".git.harnessBranch")
  git checkout "$harness_branch"

  # Full regression before and after
  log_info "Running pre-refactor regression baseline..."
  invoke_regression || log_warn "Pre-refactor regression had failures"

  # Generate refactor contract
  local ref_dir="${HARNESS_STATE}/sprints/refactor-001"
  mkdir -p "$ref_dir"

  claude -p "Create a refactor contract: ${USER_PROMPT}. This must not change any behavior. Include ALL prior sprint criteria as regression tests. Write to harness-state/sprints/refactor-001/contract.json." \
    --agent generator \
    --output-format json \
    --max-turns 30 \
    2>&1 > /dev/null

  # Implement refactor
  local sprint_branch="${harness_branch}/refactor-001"
  git checkout -b "$sprint_branch" "$harness_branch"

  claude -p "Implement this refactor: ${USER_PROMPT}. Read the contract at harness-state/sprints/refactor-001/contract.json. Behavior MUST NOT change. Write log to harness-state/sprints/refactor-001/generator-log.md." \
    --agent generator \
    --output-format json \
    --max-turns 200 \
    2>&1 > /dev/null

  # Full regression
  if invoke_evaluator "refactor-001" 1 && invoke_regression; then
    git checkout "$harness_branch"
    git merge --no-ff "$sprint_branch" -m "harness(refactor): merge (PASS, full regression)"
    git tag "harness/refactor-001/pass"
    git branch -d "$sprint_branch"
    git_commit_harness_state "harness(refactor): verified with full regression"
    log_success "Refactor complete with full regression pass"
  else
    log_error "Refactor failed regression. See eval reports."
  fi
}

# Mode: resume
run_resume() {
  log_phase "HARNESS: RESUME from sprint ${FROM_SPRINT}"

  local harness_branch
  harness_branch=$(json_read "${HARNESS_STATE}/handoff.json" ".git.harnessBranch")
  git checkout "$harness_branch"

  local total_sprints
  total_sprints=$(json_read "${HARNESS_STATE}/sprint-plan.json" ".sprints | length")

  for sprint_num in $(seq "$FROM_SPRINT" "$total_sprints"); do
    run_sprint "$sprint_num" "$harness_branch" || true
    check_cost_cap
  done

  log_phase "RESUME COMPLETE"
  local pr_body
  pr_body=$(generate_pr_body)
  git_create_pr "$harness_branch" "$(slugify "$(json_read "${HARNESS_STATE}/config.json" ".userPrompt")")" "$pr_body"
}

# Main
main() {
  parse_args "$@"

  if [[ "$DRY_RUN" == true ]]; then
    log_info "DRY RUN -- would execute mode: ${MODE}"
    log_info "Prompt: ${USER_PROMPT}"
    log_info "Config: type=${PROJECT_TYPE} strategy=${CONTEXT_STRATEGY} model=${MODEL} maxcost=${TOTAL_COST_CAP}"
    exit 0
  fi

  local start_time
  start_time=$(date +%s)

  case "$MODE" in
    new)       run_new_build ;;
    extend)    run_extend ;;
    fix)       run_fix ;;
    refactor)  run_refactor ;;
    resume)    run_resume ;;
    regression) invoke_regression ;;
    *)
      log_error "Unknown mode: ${MODE}"
      exit 1
      ;;
  esac

  local end_time
  end_time=$(date +%s)
  local duration=$(( end_time - start_time ))
  local hours=$(( duration / 3600 ))
  local minutes=$(( (duration % 3600) / 60 ))

  log_phase "DONE"
  log_info "Total time: ${hours}h ${minutes}m"
  log_info "Cost log: ${HARNESS_STATE}/cost-log.json"
  log_info "Progress: ${HARNESS_STATE}/progress.md"
}

main "$@"
