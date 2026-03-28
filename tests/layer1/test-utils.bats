#!/usr/bin/env bats

load '../helpers/test-helper'

# --- slugify ---

@test "slugify: simple string" {
  source_harness_lib utils.sh
  result=$(slugify "Hello World")
  [[ "$result" == "hello-world" ]]
}

@test "slugify: special characters removed" {
  source_harness_lib utils.sh
  result=$(slugify "Build a web-app!!!")
  [[ "$result" == "build-a-web-app" ]]
}

@test "slugify: truncates at 50 chars" {
  source_harness_lib utils.sh
  long_input="this is a very long string that should be truncated at fifty characters exactly"
  result=$(slugify "$long_input")
  [[ ${#result} -le 50 ]]
}

@test "slugify: collapses multiple hyphens" {
  source_harness_lib utils.sh
  result=$(slugify "a    b    c")
  [[ "$result" == "a-b-c" ]]
}

@test "slugify: no leading or trailing hyphens" {
  source_harness_lib utils.sh
  result=$(slugify "---test---")
  [[ "$result" == "test" ]]
}

# --- sprint_pad ---

@test "sprint_pad: single digit" {
  source_harness_lib utils.sh
  result=$(sprint_pad 3)
  [[ "$result" == "03" ]]
}

@test "sprint_pad: double digit" {
  source_harness_lib utils.sh
  result=$(sprint_pad 12)
  [[ "$result" == "12" ]]
}

# --- sprint_dir ---

@test "sprint_dir: constructs correct path" {
  source_harness_lib utils.sh
  result=$(sprint_dir 1)
  [[ "$result" == "harness-state/sprints/sprint-01" ]]
}

@test "sprint_dir: double digit sprint" {
  source_harness_lib utils.sh
  result=$(sprint_dir 10)
  [[ "$result" == "harness-state/sprints/sprint-10" ]]
}

# --- json_read ---

@test "json_read: reads simple field" {
  source_harness_lib utils.sh
  install_fixture config-general.json "$HARNESS_STATE/config.json"
  result=$(json_read "$HARNESS_STATE/config.json" ".userPrompt")
  [[ "$result" == "Build a test project" ]]
}

@test "json_read: reads nested field" {
  source_harness_lib utils.sh
  install_fixture handoff-after-sprint1.json "$HARNESS_STATE/handoff.json"
  result=$(json_read "$HARNESS_STATE/handoff.json" ".git.harnessBranch")
  [[ "$result" == "harness/test-project" ]]
}

@test "json_read: returns empty for missing field" {
  source_harness_lib utils.sh
  install_fixture config-general.json "$HARNESS_STATE/config.json"
  result=$(json_read "$HARNESS_STATE/config.json" ".nonexistent")
  [[ "$result" == "null" || "$result" == "" ]]
}

@test "json_read: returns empty for missing file" {
  source_harness_lib utils.sh
  result=$(json_read "nonexistent-file.json" ".field")
  [[ "$result" == "" ]]
}

# --- file_exists ---

@test "file_exists: true for non-empty file" {
  source_harness_lib utils.sh
  echo "content" > "$TEST_TEMP_DIR/testfile"
  file_exists "$TEST_TEMP_DIR/testfile"
}

@test "file_exists: false for missing file" {
  source_harness_lib utils.sh
  run file_exists "$TEST_TEMP_DIR/nonexistent"
  [[ "$status" -ne 0 ]]
}

@test "file_exists: false for empty file" {
  source_harness_lib utils.sh
  touch "$TEST_TEMP_DIR/emptyfile"
  run file_exists "$TEST_TEMP_DIR/emptyfile"
  [[ "$status" -ne 0 ]]
}

# --- init_harness_state ---

@test "init_harness_state: creates all required files" {
  source_harness_lib utils.sh
  init_harness_state "Test project" "general"

  [[ -f "$HARNESS_STATE/config.json" ]]
  [[ -f "$HARNESS_STATE/cost-log.json" ]]
  [[ -f "$HARNESS_STATE/regression/registry.json" ]]
  [[ -f "$HARNESS_STATE/progress.md" ]]
}

@test "init_harness_state: config contains prompt and type" {
  source_harness_lib utils.sh
  init_harness_state "Build something" "cli-tool"

  result=$(jq -r '.userPrompt' "$HARNESS_STATE/config.json")
  [[ "$result" == "Build something" ]]

  result=$(jq -r '.projectType' "$HARNESS_STATE/config.json")
  [[ "$result" == "cli-tool" ]]
}

@test "init_harness_state: cost log starts empty" {
  source_harness_lib utils.sh
  init_harness_state "Test" "general"

  result=$(jq '.invocations | length' "$HARNESS_STATE/cost-log.json")
  [[ "$result" == "0" ]]
}

@test "init_harness_state: registry starts empty" {
  source_harness_lib utils.sh
  init_harness_state "Test" "general"

  result=$(jq '.sprints | length' "$HARNESS_STATE/regression/registry.json")
  [[ "$result" == "0" ]]
}

# --- update_handoff ---

@test "update_handoff: creates handoff if missing" {
  source_harness_lib utils.sh
  update_handoff 1 "abc123" "harness/sprint-01/pass"

  [[ -f "$HARNESS_STATE/handoff.json" ]]
  result=$(jq '.completedSprints | length' "$HARNESS_STATE/handoff.json")
  [[ "$result" == "1" ]]
}

@test "update_handoff: adds sprint and updates git info" {
  source_harness_lib utils.sh
  install_fixture handoff-initial.json "$HARNESS_STATE/handoff.json"

  update_handoff 1 "abc123" "harness/sprint-01/pass"

  result=$(jq '.completedSprints[0]' "$HARNESS_STATE/handoff.json")
  [[ "$result" == "1" ]]

  result=$(jq -r '.git.latestTag' "$HARNESS_STATE/handoff.json")
  [[ "$result" == "harness/sprint-01/pass" ]]
}

@test "update_handoff: idempotent for same sprint" {
  source_harness_lib utils.sh
  install_fixture handoff-initial.json "$HARNESS_STATE/handoff.json"

  update_handoff 1 "abc" "tag1"
  update_handoff 1 "def" "tag2"

  result=$(jq '.completedSprints | length' "$HARNESS_STATE/handoff.json")
  [[ "$result" == "1" ]]
}

# --- update_regression_registry ---

@test "update_regression_registry: adds sprint criteria" {
  source_harness_lib utils.sh
  install_fixture registry-empty.json "$HARNESS_STATE/regression/registry.json"
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture contract-sprint01.json "$HARNESS_STATE/sprints/sprint-01/contract.json"

  update_regression_registry 1

  result=$(jq '.sprints["1"].criteria | length' "$HARNESS_STATE/regression/registry.json")
  [[ "$result" == "3" ]]
}

@test "update_regression_registry: no-op without contract" {
  source_harness_lib utils.sh
  install_fixture registry-empty.json "$HARNESS_STATE/regression/registry.json"

  update_regression_registry 1

  result=$(jq '.sprints | length' "$HARNESS_STATE/regression/registry.json")
  [[ "$result" == "0" ]]
}
