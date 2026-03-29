#!/usr/bin/env bats
# Unit tests for pure functions in harness/lib/utils.sh
# Covers: slugify, sprint_pad, sprint_dir, json_read, file_exists

load 'helpers/test-helper'

setup() {
  # Create isolated temp directory for each test
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR
  cd "$TEST_TEMP_DIR"
  export HARNESS_STATE="harness-state"
  mkdir -p "$HARNESS_STATE/sprints" "$HARNESS_STATE/regression"

  # Source the library under test
  source_harness_lib 'utils.sh'
}

# ---------------------------------------------------------------------------
# slugify
# ---------------------------------------------------------------------------

@test "slugify: converts uppercase to lowercase" {
  run slugify 'HELLO'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "hello" ]]
}

@test "slugify: replaces special characters with hyphens" {
  run slugify 'hello world'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "hello-world" ]]
}

@test "slugify: collapses consecutive special characters into a single hyphen" {
  run slugify 'hello---world'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "hello-world" ]]
}

@test "slugify: strips leading and trailing hyphens" {
  run slugify '---hello---'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "hello" ]]
}

@test "slugify: truncates output to 50 characters" {
  local long_input="this is a very long string that should definitely be longer than fifty characters when slugified completely"
  run slugify "$long_input"
  [[ "$status" -eq 0 ]]
  [[ ${#output} -le 50 ]]
}

@test "slugify: handles empty string input" {
  run slugify ''
  [[ "$status" -eq 0 ]]
  [[ "$output" == "" ]]
}

@test "slugify: passes through already-slugified input unchanged" {
  run slugify 'already-slugified'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "already-slugified" ]]
}

@test "slugify: handles spaces and tabs correctly" {
  run slugify $'hello\tworld here'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "hello-world-here" ]]
}

@test "slugify: handles mixed case with numbers" {
  run slugify 'Build V2 App'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "build-v2-app" ]]
}

# ---------------------------------------------------------------------------
# sprint_pad
# ---------------------------------------------------------------------------

@test "sprint_pad: pads single digit to two digits with leading zero" {
  run sprint_pad 3
  [[ "$status" -eq 0 ]]
  [[ "$output" == "03" ]]
}

@test "sprint_pad: preserves double-digit numbers as-is" {
  run sprint_pad 12
  [[ "$status" -eq 0 ]]
  [[ "$output" == "12" ]]
}

@test "sprint_pad: pads zero to 00" {
  run sprint_pad 0
  [[ "$status" -eq 0 ]]
  [[ "$output" == "00" ]]
}

@test "sprint_pad: handles large numbers without truncation" {
  run sprint_pad 100
  [[ "$status" -eq 0 ]]
  [[ "$output" == "100" ]]
}

# ---------------------------------------------------------------------------
# sprint_dir
# ---------------------------------------------------------------------------

@test "sprint_dir: constructs correct path for single-digit sprint number" {
  run sprint_dir 3
  [[ "$status" -eq 0 ]]
  [[ "$output" == "harness-state/sprints/sprint-03" ]]
}

@test "sprint_dir: constructs correct path for double-digit sprint number" {
  run sprint_dir 12
  [[ "$status" -eq 0 ]]
  [[ "$output" == "harness-state/sprints/sprint-12" ]]
}

@test "sprint_dir: respects HARNESS_STATE environment variable override" {
  export HARNESS_STATE="custom-state"
  run sprint_dir 5
  [[ "$status" -eq 0 ]]
  [[ "$output" == "custom-state/sprints/sprint-05" ]]
}

# ---------------------------------------------------------------------------
# json_read
# ---------------------------------------------------------------------------

@test "json_read: reads a top-level field from a JSON file" {
  echo '{"name": "test-project", "version": "1.0"}' > test.json
  run json_read test.json '.name'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "test-project" ]]
}

@test "json_read: reads a nested field using dot-path notation" {
  echo '{"git": {"branch": "main", "tag": "v1"}}' > test.json
  run json_read test.json '.git.branch'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "main" ]]
}

@test "json_read: reads an array element" {
  echo '{"sprints": [{"name": "first"}, {"name": "second"}]}' > test.json
  run json_read test.json '.sprints[0].name'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "first" ]]
}

@test "json_read: returns empty string for missing file" {
  run json_read nonexistent-file.json '.field'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "" ]]
}

@test "json_read: returns empty or null for missing field in valid JSON" {
  echo '{"name": "test"}' > test.json
  run json_read test.json '.nonexistent'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "null" || "$output" == "" ]]
}

@test "json_read: handles malformed JSON gracefully without crashing" {
  echo '{invalid json content}' > malformed.json
  run json_read malformed.json '.field'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "" ]]
}

# ---------------------------------------------------------------------------
# file_exists
# ---------------------------------------------------------------------------

@test "file_exists: returns true for a non-empty file" {
  echo "content" > testfile.txt
  run file_exists testfile.txt
  [[ "$status" -eq 0 ]]
}

@test "file_exists: returns false for a missing file" {
  run file_exists nonexistent-file.txt
  [[ "$status" -ne 0 ]]
}

@test "file_exists: returns false for an empty file" {
  touch empty-file.txt
  run file_exists empty-file.txt
  [[ "$status" -ne 0 ]]
}

@test "file_exists: returns false for a directory path" {
  mkdir -p testdir
  run file_exists testdir
  [[ "$status" -ne 0 ]]
}
