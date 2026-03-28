#!/usr/bin/env bats

load '../helpers/test-helper'

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR
  cd "$TEST_TEMP_DIR"
  export HARNESS_STATE="harness-state"
  mkdir -p "$HARNESS_STATE/sprints" "$HARNESS_STATE/regression"

  PROJECT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  FIXTURE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../helpers/fixtures" && pwd)"

  init_test_repo
  source_harness_lib utils.sh
  source_harness_lib git.sh
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

# Helper to source libs
source_harness_lib() {
  local lib="$1"
  SCRIPT_DIR="$PROJECT_DIR/harness/lib"
  source "$PROJECT_DIR/harness/lib/$lib"
}

# === git_create_harness_branch ===

@test "git_create_harness_branch: creates branch" {
  result=$(git_create_harness_branch "test-project")
  [[ "$result" == "harness/test-project" ]]

  current=$(git branch --show-current)
  [[ "$current" == "harness/test-project" ]]
}

@test "git_create_harness_branch: idempotent" {
  git_create_harness_branch "test-project"
  git checkout main
  run git_create_harness_branch "test-project"
  [[ "$status" -eq 0 ]]
}

# === git_create_sprint_branch ===

@test "git_create_sprint_branch: creates sprint branch" {
  git_create_harness_branch "test-project"

  result=$(git_create_sprint_branch "harness/test-project" 1)
  [[ "$result" == "harness/test-project-sprint-01" ]]

  current=$(git branch --show-current)
  [[ "$current" == "harness/test-project-sprint-01" ]]
}

@test "git_create_sprint_branch: cleans up existing branch" {
  git_create_harness_branch "test-project"
  git checkout -b "harness/test-project-sprint-01"
  echo "old work" > old.txt
  git add old.txt && git commit -q -m "old"
  git checkout "harness/test-project"

  result=$(git_create_sprint_branch "harness/test-project" 1)
  [[ "$result" == "harness/test-project-sprint-01" ]]

  # Old file should NOT be present (fresh branch from harness)
  [[ ! -f old.txt ]]
}

# === git_merge_sprint ===

@test "git_merge_sprint: creates merge commit" {
  git_create_harness_branch "test-project"
  git checkout -b "harness/test-project-sprint-01"
  echo "sprint work" > sprint.txt
  git add sprint.txt && git commit -q -m "harness(sprint-01): add feature [C1-01]"

  merge_sha=$(git_merge_sprint "harness/test-project" 1 1)

  # Should be on harness branch
  current=$(git branch --show-current)
  [[ "$current" == "harness/test-project" ]]

  # Merge commit should exist
  local log_output
  log_output=$(git --no-pager log --oneline)
  echo "$log_output" | grep -q "merge"

  # SHA should be valid
  [[ -n "$merge_sha" ]]
}

@test "git_merge_sprint: creates tag" {
  git_create_harness_branch "test-project"
  git checkout -b "harness/test-project-sprint-01"
  echo "work" > f.txt
  git add f.txt && git commit -q -m "work"

  git_merge_sprint "harness/test-project" 1 1

  # Tag should exist
  git tag | grep -q "harness/sprint-01/pass"
}

@test "git_merge_sprint: deletes sprint branch" {
  git_create_harness_branch "test-project"
  git checkout -b "harness/test-project-sprint-01"
  echo "work" > f.txt
  git add f.txt && git commit -q -m "work"

  git_merge_sprint "harness/test-project" 1 1

  # Sprint branch should be gone
  run git rev-parse --verify "harness/test-project-sprint-01"
  [[ "$status" -ne 0 ]]
}

# === git_fail_sprint_attempt ===

@test "git_fail_sprint_attempt: tags the attempt" {
  git_create_harness_branch "test-project"
  git checkout -b "harness/test-project-sprint-01"
  echo "failed work" > f.txt
  git add f.txt && git commit -q -m "failed attempt"

  git_fail_sprint_attempt "harness/test-project" 1 1

  git tag | grep -q "harness/sprint-01/attempt-1"
}

@test "git_fail_sprint_attempt: deletes sprint branch" {
  git_create_harness_branch "test-project"
  git checkout -b "harness/test-project-sprint-01"
  echo "failed" > f.txt
  git add f.txt && git commit -q -m "failed"

  git_fail_sprint_attempt "harness/test-project" 1 1

  run git rev-parse --verify "harness/test-project-sprint-01"
  [[ "$status" -ne 0 ]]
}

@test "git_fail_sprint_attempt: returns to harness branch" {
  git_create_harness_branch "test-project"
  git checkout -b "harness/test-project-sprint-01"
  echo "failed" > f.txt
  git add f.txt && git commit -q -m "failed"

  git_fail_sprint_attempt "harness/test-project" 1 1

  current=$(git branch --show-current)
  [[ "$current" == "harness/test-project" ]]
}

# === git_commit_harness_state ===

@test "git_commit_harness_state: commits changes" {
  echo "state data" > "$HARNESS_STATE/progress.md"

  git_commit_harness_state "harness: test commit"

  git log --oneline -1 | grep -q "harness: test commit"
}

@test "git_commit_harness_state: no-op when clean" {
  run git_commit_harness_state "harness: nothing to commit"
  [[ "$status" -eq 0 ]]
}

# === generate_pr_body ===

@test "generate_pr_body: contains sprint table" {
  install_fixture config-general.json "$HARNESS_STATE/config.json"
  install_fixture sprint-plan-2sprint.json "$HARNESS_STATE/sprint-plan.json"
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture eval-report-pass.json "$HARNESS_STATE/sprints/sprint-01/eval-report.json"

  result=$(generate_pr_body)
  echo "$result" | grep -q "Sprint"
  echo "$result" | grep -q "PASS"
}
