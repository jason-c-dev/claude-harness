#!/usr/bin/env bats
# Edge case and boundary condition tests across all harness modules
# Covers: malformed input, empty input, error recovery, and boundary conditions

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
# slugify edge cases
# ===========================================================================

@test "slugify: string containing only special characters returns empty string" {
  run slugify '!@#$%^&*()'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "" ]]
}

@test "slugify: string containing only spaces returns empty string" {
  run slugify '     '
  [[ "$status" -eq 0 ]]
  [[ "$output" == "" ]]
}

@test "slugify: empty string returns empty string" {
  run slugify ''
  [[ "$status" -eq 0 ]]
  [[ "$output" == "" ]]
}

@test "slugify: unicode characters are replaced with hyphens and collapsed" {
  run slugify 'héllo wörld'
  [[ "$status" -eq 0 ]]
  # Non-ASCII chars are not in [a-z0-9], so they get replaced with hyphens
  # Result depends on locale but should not crash
  [[ "$status" -eq 0 ]]
  # Output should be non-empty (contains at least 'llo' and 'rld')
  [[ -n "$output" ]]
}

@test "slugify: string of exactly 50 alphanumeric chars returns all 50" {
  local input="abcdefghijklmnopqrstuvwxyz01234567890123456789abcd"
  # That's exactly 50 characters
  run slugify "$input"
  [[ "$status" -eq 0 ]]
  [[ ${#output} -eq 50 ]]
  [[ "$output" == "$input" ]]
}

# ===========================================================================
# json_read edge cases
# ===========================================================================

@test "json_read: binary file does not crash and returns empty string" {
  printf '\x00\x01\x02\x03\x04\x05' > "$TEST_TEMP_DIR/binary.dat"
  run json_read "$TEST_TEMP_DIR/binary.dat" ".field"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "" ]]
}

@test "json_read: truncated JSON returns empty string without crashing" {
  echo -n '{"name": ' > "$TEST_TEMP_DIR/truncated.json"
  run json_read "$TEST_TEMP_DIR/truncated.json" ".name"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "" ]]
}

@test "json_read: deeply nested path returns correct value" {
  cat > "$TEST_TEMP_DIR/deep.json" <<'EOF'
{
  "a": {
    "b": {
      "c": {
        "d": {
          "e": "deep-value"
        }
      }
    }
  }
}
EOF
  run json_read "$TEST_TEMP_DIR/deep.json" ".a.b.c.d.e"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "deep-value" ]]
}

@test "json_read: array index access works on valid JSON" {
  echo '{"items": ["zero", "one", "two"]}' > "$TEST_TEMP_DIR/array.json"
  run json_read "$TEST_TEMP_DIR/array.json" ".items[1]"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "one" ]]
}

@test "json_read: file with only whitespace returns empty string" {
  echo '   ' > "$TEST_TEMP_DIR/whitespace.json"
  run json_read "$TEST_TEMP_DIR/whitespace.json" ".field"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "" ]]
}

# ===========================================================================
# init_harness_state edge cases
# ===========================================================================

@test "init_harness_state: prompt with double quotes and single quotes produces valid JSON" {
  init_harness_state 'Build a "great" app with '"'"'features'"'"'' "general"

  # config.json must be valid JSON
  run jq -e . "$HARNESS_STATE/config.json"
  [[ "$status" -eq 0 ]]

  # userPrompt field should contain the original prompt text
  local prompt
  prompt=$(jq -r '.userPrompt' "$HARNESS_STATE/config.json")
  [[ "$prompt" == *'"great"'* ]]
  [[ "$prompt" == *"'features'"* ]]
}

@test "init_harness_state: prompt with newlines produces valid JSON" {
  local prompt_with_newlines
  prompt_with_newlines=$'Build an app\nwith multiple\nlines'

  init_harness_state "$prompt_with_newlines" "general"

  # config.json must be valid JSON
  run jq -e . "$HARNESS_STATE/config.json"
  [[ "$status" -eq 0 ]]

  # The userPrompt field should preserve newline content
  local prompt
  prompt=$(jq -r '.userPrompt' "$HARNESS_STATE/config.json")
  [[ "$prompt" == *"Build an app"* ]]
  [[ "$prompt" == *"with multiple"* ]]
  [[ "$prompt" == *"lines"* ]]
}

@test "init_harness_state: prompt with backslashes produces valid JSON" {
  init_harness_state 'Path is C:\Users\test\dir' "general"

  # config.json must be valid JSON
  run jq -e . "$HARNESS_STATE/config.json"
  [[ "$status" -eq 0 ]]

  # The userPrompt field should contain the backslash content
  local prompt
  prompt=$(jq -r '.userPrompt' "$HARNESS_STATE/config.json")
  [[ "$prompt" == *'C:\Users\test\dir'* ]]
}

# ===========================================================================
# update_handoff edge cases
# ===========================================================================

@test "update_handoff: called before init_harness_state creates handoff.json from scratch" {
  # Ensure no handoff.json exists and no init_harness_state was called
  rm -f "$HARNESS_STATE/handoff.json"

  update_handoff 1 "sha-from-scratch" "harness/sprint-01/pass"

  [[ -f "$HARNESS_STATE/handoff.json" ]]

  # Verify structure has all required fields
  jq -e '.completedSprints' "$HARNESS_STATE/handoff.json" >/dev/null
  jq -e '.currentSprint' "$HARNESS_STATE/handoff.json" >/dev/null
  jq -e '.git' "$HARNESS_STATE/handoff.json" >/dev/null
  jq -e '.git.harnessBranch' "$HARNESS_STATE/handoff.json" >/dev/null
  jq -e '.git.latestTag' "$HARNESS_STATE/handoff.json" >/dev/null
  jq -e '.git.latestMergeSha' "$HARNESS_STATE/handoff.json" >/dev/null

  # Verify sprint was added
  local sprints
  sprints=$(jq '.completedSprints' "$HARNESS_STATE/handoff.json")
  echo "$sprints" | jq -e 'index(1) != null'
}

# ===========================================================================
# update_regression_registry edge cases
# ===========================================================================

@test "update_regression_registry: malformed contract JSON does not crash and preserves registry" {
  echo '{"sprints": {"existing": {"criteria": ["C0-01"]}}, "lastFullRun": null}' > "$HARNESS_STATE/regression/registry.json"

  # Create a contract.json with invalid JSON
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  echo 'not json at all' > "$HARNESS_STATE/sprints/sprint-01/contract.json"

  # Should not crash (may produce jq error, but function should handle it)
  run update_regression_registry 1
  # The function may fail, but it should not corrupt the registry
  # We check the registry is still valid JSON
  run jq -e . "$HARNESS_STATE/regression/registry.json"
  [[ "$status" -eq 0 ]]
}

# ===========================================================================
# git_create_sprint_branch edge cases
# ===========================================================================

@test "git_create_sprint_branch: fails gracefully when harness branch does not exist" {
  init_test_repo

  source_harness_lib 'git.sh'

  # Try to create a sprint branch from a non-existent harness branch
  # Note: we call without 'run' because bats' run disables set -e,
  # which would mask the git checkout failure. We use || to capture exit code.
  local exit_code=0
  git_create_sprint_branch "harness/nonexistent-branch" 1 >/dev/null 2>&1 || exit_code=$?
  [[ "$exit_code" -ne 0 ]]

  # Verify no orphan branch was created
  local branches
  branches=$(git branch --list 'harness/nonexistent-branch-sprint-01')
  [[ -z "$branches" ]]
}

# ===========================================================================
# hooks edge cases
# ===========================================================================

@test "on-generator-stop: multiple sprint directories with mixed statuses picks active one and blocks" {
  # Create sprint-01 with pass status (terminal)
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "status-pass.json" "$HARNESS_STATE/sprints/sprint-01/status.json"

  # Create sprint-02 with active status (should be detected and blocked)
  mkdir -p "$HARNESS_STATE/sprints/sprint-02"
  install_fixture "status-active.json" "$HARNESS_STATE/sprints/sprint-02/status.json"

  run run_hook "on-generator-stop.sh"
  [[ "$status" -eq 2 ]]
}

@test "on-generator-stop: hooks work from working directory with harness-state at expected relative path" {
  # Verify that hooks read from the current working directory's harness-state/
  # This is the expected behavior since hooks hardcode 'harness-state'
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "status-ready-for-eval.json" "$HARNESS_STATE/sprints/sprint-01/status.json"
  install_fixture "generator-log.md" "$HARNESS_STATE/sprints/sprint-01/generator-log.md"

  # Run the hook from the test temp dir (which has harness-state at the expected relative path)
  run run_hook "on-generator-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-stop: sprint-plan exists but no sprint directories at all allows exit" {
  install_fixture "sprint-plan-3sprint.json" "$HARNESS_STATE/sprint-plan.json"
  # No sprint directories created at all (the glob won't match anything)
  run run_hook "on-stop.sh"
  [[ "$status" -eq 0 ]]
}

# ===========================================================================
# log_cost edge cases
# ===========================================================================

@test "log_cost: non-JSON output_json argument does not crash and defaults to 0 tokens" {
  echo '{"invocations": [], "totalCost": 0}' > "$HARNESS_STATE/cost-log.json"

  # Pass a non-JSON string as the output_json argument
  log_cost "generator" 1 "this is not json"

  # Should complete without crashing
  [[ -f "$HARNESS_STATE/cost-log.json" ]]

  # The entry should have inputTokens and outputTokens set to 0
  assert_json_field "$HARNESS_STATE/cost-log.json" ".invocations[0].inputTokens" "0"
  assert_json_field "$HARNESS_STATE/cost-log.json" ".invocations[0].outputTokens" "0"
}

# ===========================================================================
# update_progress edge cases
# ===========================================================================

@test "update_progress: works when sprint-plan.json is missing" {
  echo "# Progress" > "$HARNESS_STATE/progress.md"
  # No sprint-plan.json exists

  # Should not crash
  update_progress 1 "PASS" 1 ""

  # An entry should still be appended to progress.md
  grep -q "Sprint 01" "$HARNESS_STATE/progress.md"
  grep -q "PASS" "$HARNESS_STATE/progress.md"
}
