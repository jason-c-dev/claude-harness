#!/usr/bin/env bats
# Unit tests for state management functions in harness/lib/utils.sh
# Covers: init_harness_state, log_cost, update_progress, update_handoff, update_regression_registry

load 'helpers/test-helper'

setup() {
  # Create isolated temp directory for each test
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR
  cd "$TEST_TEMP_DIR"
  export HARNESS_STATE="harness-state"
  mkdir -p "$HARNESS_STATE/sprints" "$HARNESS_STATE/regression"

  # Clear environment variables that init_harness_state reads
  unset MODEL
  unset CONTEXT_STRATEGY
  unset MAX_SPRINT_ATTEMPTS
  unset MAX_CONTRACT_ROUNDS
  unset COST_CAP_PER_SPRINT
  unset TOTAL_COST_CAP

  # Source the library under test
  source_harness_lib 'utils.sh'
}

# ===========================================================================
# init_harness_state
# ===========================================================================

@test "init_harness_state: creates config.json with correct userPrompt and projectType" {
  init_harness_state "Build a web app" "web-app"

  [[ -f "$HARNESS_STATE/config.json" ]]
  assert_json_field "$HARNESS_STATE/config.json" ".userPrompt" "Build a web app"
  assert_json_field "$HARNESS_STATE/config.json" ".projectType" "web-app"
}

@test "init_harness_state: creates all required files" {
  init_harness_state "Test prompt" "general"

  [[ -f "$HARNESS_STATE/config.json" ]]
  [[ -f "$HARNESS_STATE/cost-log.json" ]]
  [[ -f "$HARNESS_STATE/regression/registry.json" ]]
  [[ -f "$HARNESS_STATE/progress.md" ]]
}

@test "init_harness_state: cost-log.json starts with empty invocations array and totalCost of 0" {
  init_harness_state "Test prompt" "general"

  local inv_length
  inv_length=$(jq '.invocations | length' "$HARNESS_STATE/cost-log.json")
  [[ "$inv_length" -eq 0 ]]

  assert_json_field "$HARNESS_STATE/cost-log.json" ".totalCost" "0"
}

@test "init_harness_state: regression/registry.json starts with empty sprints object and lastFullRun as null" {
  init_harness_state "Test prompt" "general"

  local sprints_length
  sprints_length=$(jq '.sprints | length' "$HARNESS_STATE/regression/registry.json")
  [[ "$sprints_length" -eq 0 ]]

  assert_json_field "$HARNESS_STATE/regression/registry.json" ".lastFullRun" "null"
}

@test "init_harness_state: progress.md contains the project prompt text and model name" {
  init_harness_state "Build a REST API" "api"

  grep -q "Build a REST API" "$HARNESS_STATE/progress.md"
  grep -q "opus" "$HARNESS_STATE/progress.md"
}

@test "init_harness_state: respects environment variables MODEL, CONTEXT_STRATEGY, MAX_SPRINT_ATTEMPTS, COST_CAP_PER_SPRINT, TOTAL_COST_CAP" {
  export MODEL="sonnet"
  export CONTEXT_STRATEGY="continue"
  export MAX_SPRINT_ATTEMPTS=5
  export COST_CAP_PER_SPRINT=50.00
  export TOTAL_COST_CAP=500.00

  init_harness_state "Custom config test" "general"

  assert_json_field "$HARNESS_STATE/config.json" ".model" "sonnet"
  assert_json_field "$HARNESS_STATE/config.json" ".contextStrategy" "continue"
  assert_json_field "$HARNESS_STATE/config.json" ".maxSprintAttempts" "5"
  assert_json_field "$HARNESS_STATE/config.json" ".costCapPerSprint" "50.00"
  assert_json_field "$HARNESS_STATE/config.json" ".totalCostCap" "500.00"
}

@test "init_harness_state: config.json uses correct defaults when environment variables are not set" {
  init_harness_state "Defaults test" "general"

  assert_json_field "$HARNESS_STATE/config.json" ".model" "opus"
  assert_json_field "$HARNESS_STATE/config.json" ".contextStrategy" "reset"
  assert_json_field "$HARNESS_STATE/config.json" ".maxSprintAttempts" "3"
  assert_json_field "$HARNESS_STATE/config.json" ".costCapPerSprint" "25.00"
  assert_json_field "$HARNESS_STATE/config.json" ".totalCostCap" "200.00"
}

# ===========================================================================
# log_cost
# ===========================================================================

@test "log_cost: appends an entry with correct role, sprint, and token counts" {
  # Initialize cost-log.json
  echo '{"invocations": [], "totalCost": 0}' > "$HARNESS_STATE/cost-log.json"

  local usage_json='{"usage": {"input_tokens": 1500, "output_tokens": 800}}'
  log_cost "generator" 2 "$usage_json"

  assert_json_field "$HARNESS_STATE/cost-log.json" ".invocations[0].role" "generator"
  assert_json_field "$HARNESS_STATE/cost-log.json" ".invocations[0].sprint" "2"
  assert_json_field "$HARNESS_STATE/cost-log.json" ".invocations[0].inputTokens" "1500"
  assert_json_field "$HARNESS_STATE/cost-log.json" ".invocations[0].outputTokens" "800"
}

@test "log_cost: handles missing usage fields gracefully, defaulting token counts to 0" {
  echo '{"invocations": [], "totalCost": 0}' > "$HARNESS_STATE/cost-log.json"

  log_cost "evaluator" 1 '{}'

  assert_json_field "$HARNESS_STATE/cost-log.json" ".invocations[0].inputTokens" "0"
  assert_json_field "$HARNESS_STATE/cost-log.json" ".invocations[0].outputTokens" "0"
}

@test "log_cost: multiple calls accumulate entries in the invocations array" {
  echo '{"invocations": [], "totalCost": 0}' > "$HARNESS_STATE/cost-log.json"

  log_cost "planner" 1 '{"usage": {"input_tokens": 100, "output_tokens": 50}}'
  log_cost "generator" 1 '{"usage": {"input_tokens": 200, "output_tokens": 100}}'
  log_cost "evaluator" 1 '{"usage": {"input_tokens": 300, "output_tokens": 150}}'

  local count
  count=$(jq '.invocations | length' "$HARNESS_STATE/cost-log.json")
  [[ "$count" -eq 3 ]]
}

# ===========================================================================
# update_progress
# ===========================================================================

@test "update_progress: appends a sprint entry with correct sprint name from sprint-plan.json" {
  # Set up progress.md and sprint-plan fixture
  echo "# Progress" > "$HARNESS_STATE/progress.md"
  install_fixture "sprint-plan-3sprint.json" "$HARNESS_STATE/sprint-plan.json"

  update_progress 1 "PASS" 1 ""

  grep -q "Foundation Setup" "$HARNESS_STATE/progress.md"
}

@test "update_progress: includes status and attempt number in the appended entry" {
  echo "# Progress" > "$HARNESS_STATE/progress.md"
  install_fixture "sprint-plan-3sprint.json" "$HARNESS_STATE/sprint-plan.json"

  update_progress 2 "PASS" 2 ""

  grep -Fq "**Status**: PASS" "$HARNESS_STATE/progress.md"
  grep -Fq "**Attempt**: 2" "$HARNESS_STATE/progress.md"
}

@test "update_progress: includes merge SHA in the entry when provided" {
  echo "# Progress" > "$HARNESS_STATE/progress.md"
  install_fixture "sprint-plan-3sprint.json" "$HARNESS_STATE/sprint-plan.json"

  update_progress 1 "PASS" 1 "abc123def456"

  grep -q "abc123def456" "$HARNESS_STATE/progress.md"
}

@test "update_progress: omits merge SHA line when merge_sha argument is empty or not provided" {
  echo "# Progress" > "$HARNESS_STATE/progress.md"
  install_fixture "sprint-plan-3sprint.json" "$HARNESS_STATE/sprint-plan.json"

  update_progress 1 "PASS" 1 ""

  ! grep -q "Merge commit" "$HARNESS_STATE/progress.md"
}

# ===========================================================================
# update_handoff
# ===========================================================================

@test "update_handoff: creates handoff.json from scratch when the file does not exist" {
  # Ensure handoff.json does not exist
  rm -f "$HARNESS_STATE/handoff.json"

  update_handoff 1 "sha123" "harness/sprint-01/pass"

  [[ -f "$HARNESS_STATE/handoff.json" ]]
  # Verify structure
  jq -e '.completedSprints' "$HARNESS_STATE/handoff.json" >/dev/null
  jq -e '.currentSprint' "$HARNESS_STATE/handoff.json" >/dev/null
  jq -e '.git' "$HARNESS_STATE/handoff.json" >/dev/null
}

@test "update_handoff: adds sprint number to completedSprints array" {
  rm -f "$HARNESS_STATE/handoff.json"

  update_handoff 1 "sha123" "tag1"

  local sprints
  sprints=$(jq '.completedSprints' "$HARNESS_STATE/handoff.json")
  echo "$sprints" | jq -e 'index(1) != null'
}

@test "update_handoff: updates currentSprint to N+1" {
  rm -f "$HARNESS_STATE/handoff.json"

  update_handoff 3 "sha456" "tag3"

  assert_json_field "$HARNESS_STATE/handoff.json" ".currentSprint" "4"
}

@test "update_handoff: updates git.latestTag and git.latestMergeSha" {
  rm -f "$HARNESS_STATE/handoff.json"

  update_handoff 1 "merge-sha-abc" "harness/sprint-01/pass"

  assert_json_field "$HARNESS_STATE/handoff.json" ".git.latestTag" "harness/sprint-01/pass"
  assert_json_field "$HARNESS_STATE/handoff.json" ".git.latestMergeSha" "merge-sha-abc"
}

@test "update_handoff: idempotent -- calling with the same sprint number twice does not duplicate in completedSprints" {
  rm -f "$HARNESS_STATE/handoff.json"

  update_handoff 1 "sha1" "tag1"
  update_handoff 1 "sha2" "tag2"

  local count
  count=$(jq '[.completedSprints[] | select(. == 1)] | length' "$HARNESS_STATE/handoff.json")
  [[ "$count" -eq 1 ]]
}

@test "update_handoff: preserves existing fields (projectName, techStack, etc.) when updating" {
  # Create handoff.json with custom fields
  cat > "$HARNESS_STATE/handoff.json" <<'EOF'
{
  "projectName": "My Custom Project",
  "completedSprints": [],
  "currentSprint": 1,
  "totalSprints": 5,
  "completedFeatures": ["Feature A"],
  "keyFiles": {"main": ["index.js"]},
  "techStack": {"runtime": "node"},
  "outstandingIssues": ["Bug #42"],
  "devServerCommand": "npm start",
  "devServerPort": 3000,
  "git": {
    "harnessBranch": "harness/my-project",
    "latestTag": "",
    "latestMergeSha": "",
    "prNumbers": [10]
  }
}
EOF

  update_handoff 1 "sha123" "harness/sprint-01/pass"

  assert_json_field "$HARNESS_STATE/handoff.json" ".projectName" "My Custom Project"
  assert_json_field "$HARNESS_STATE/handoff.json" ".techStack.runtime" "node"
  assert_json_field "$HARNESS_STATE/handoff.json" ".devServerCommand" "npm start"
  assert_json_field "$HARNESS_STATE/handoff.json" ".devServerPort" "3000"
  assert_json_field "$HARNESS_STATE/handoff.json" ".completedFeatures[0]" "Feature A"
  assert_json_field "$HARNESS_STATE/handoff.json" ".outstandingIssues[0]" "Bug #42"
}

# ===========================================================================
# update_regression_registry
# ===========================================================================

@test "update_regression_registry: extracts criteria IDs from contract.json and adds sprint entry to registry" {
  # Set up registry
  echo '{"sprints": {}, "lastFullRun": null}' > "$HARNESS_STATE/regression/registry.json"

  # Install contract fixture to sprint directory
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "contract-3criteria.json" "$HARNESS_STATE/sprints/sprint-01/contract.json"

  update_regression_registry 1

  # Verify registry has the sprint entry with criteria IDs
  local criteria
  criteria=$(jq -r '.sprints["1"].criteria | join(",")' "$HARNESS_STATE/regression/registry.json")
  [[ "$criteria" == "C1-01,C1-02,C1-03" ]]

  # Verify contractPath
  local contract_path
  contract_path=$(jq -r '.sprints["1"].contractPath' "$HARNESS_STATE/regression/registry.json")
  [[ "$contract_path" == "sprints/sprint-01/contract.json" ]]
}

@test "update_regression_registry: no-op when contract file is missing" {
  echo '{"sprints": {}, "lastFullRun": null}' > "$HARNESS_STATE/regression/registry.json"

  # No contract file -- sprint dir doesn't even exist
  update_regression_registry 1

  local sprints_length
  sprints_length=$(jq '.sprints | length' "$HARNESS_STATE/regression/registry.json")
  [[ "$sprints_length" -eq 0 ]]
}

@test "update_regression_registry: no-op when contract file is empty" {
  echo '{"sprints": {}, "lastFullRun": null}' > "$HARNESS_STATE/regression/registry.json"

  # Create empty contract file
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  touch "$HARNESS_STATE/sprints/sprint-01/contract.json"

  update_regression_registry 1

  local sprints_length
  sprints_length=$(jq '.sprints | length' "$HARNESS_STATE/regression/registry.json")
  [[ "$sprints_length" -eq 0 ]]
}

@test "update_regression_registry: handles contract with no criteria array gracefully" {
  echo '{"sprints": {}, "lastFullRun": null}' > "$HARNESS_STATE/regression/registry.json"

  # Install contract with empty criteria
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "contract-empty-criteria.json" "$HARNESS_STATE/sprints/sprint-01/contract.json"

  update_regression_registry 1

  local criteria_length
  criteria_length=$(jq '.sprints["1"].criteria | length' "$HARNESS_STATE/regression/registry.json")
  [[ "$criteria_length" -eq 0 ]]
}
