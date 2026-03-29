#!/usr/bin/env bats
# Sanity checks for the meta-tests infrastructure itself

load 'helpers/test-helper'

@test "test-helper: setup creates TEST_TEMP_DIR" {
  [[ -d "$TEST_TEMP_DIR" ]]
}

@test "test-helper: setup creates HARNESS_STATE with subdirectories" {
  [[ -d "$HARNESS_STATE/sprints" ]]
  [[ -d "$HARNESS_STATE/regression" ]]
}

@test "test-helper: FIXTURE_DIR points to existing directory" {
  [[ -d "$FIXTURE_DIR" ]]
}

@test "test-helper: install_fixture copies file and creates parent dirs" {
  install_fixture "config-valid.json" "nested/path/config.json"
  [[ -f "nested/path/config.json" ]]
  jq -e '.userPrompt' "nested/path/config.json" >/dev/null
}

@test "test-helper: assert_json_field passes on correct value" {
  install_fixture "config-valid.json" "config.json"
  assert_json_field "config.json" ".projectType" "web-app"
}

@test "test-helper: assert_json_field fails on incorrect value" {
  install_fixture "config-valid.json" "config.json"
  run assert_json_field "config.json" ".projectType" "wrong-value"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"Expected"* ]]
  [[ "$output" == *"Actual"* ]]
}

@test "test-helper: init_test_repo creates a git repo" {
  init_test_repo
  [[ -d ".git" ]]
  git log --oneline | grep -q "initial commit"
}

@test "test-helper: source_harness_lib loads utils.sh without error" {
  source_harness_lib "utils.sh"
  # Verify a function from utils.sh is available
  declare -f slugify >/dev/null
}
