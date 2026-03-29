#!/usr/bin/env bats
# Tests for git operations in harness/lib/git.sh
# Covers: git_create_harness_branch, git_create_sprint_branch, git_merge_sprint,
#         git_fail_sprint_attempt, git_commit_harness_state, generate_pr_body

bats_require_minimum_version 1.5.0

load 'helpers/test-helper'

setup() {
  # Create isolated temp directory for each test
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR
  cd "$TEST_TEMP_DIR"
  export HARNESS_STATE="harness-state"
  mkdir -p "$HARNESS_STATE/sprints" "$HARNESS_STATE/regression"

  # Source utils.sh first -- git.sh conditionally skips it when HARNESS_STATE is set
  source_harness_lib 'utils.sh'
  source_harness_lib 'git.sh'
}

# ===========================================================================
# git_create_harness_branch
# ===========================================================================

@test "git_create_harness_branch: creates a harness/{slug} branch from main" {
  init_test_repo

  run --separate-stderr git_create_harness_branch "my-project"

  [[ "$status" -eq 0 ]]
  # Verify the branch exists
  git rev-parse --verify "harness/my-project" >/dev/null 2>&1
}

@test "git_create_harness_branch: returns branch name on stdout" {
  init_test_repo

  run --separate-stderr git_create_harness_branch "test-slug"

  [[ "$status" -eq 0 ]]
  [[ "$output" == "harness/test-slug" ]]
}

@test "git_create_harness_branch: is idempotent -- re-running checks out existing branch without error" {
  init_test_repo

  # First call creates the branch
  run --separate-stderr git_create_harness_branch "idempotent-test"
  [[ "$status" -eq 0 ]]

  # Switch to main
  git checkout main >/dev/null 2>&1

  # Second call should succeed (checkout existing)
  run --separate-stderr git_create_harness_branch "idempotent-test"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "harness/idempotent-test" ]]

  # Verify we're on the correct branch
  local current_branch
  current_branch=$(git branch --show-current)
  [[ "$current_branch" == "harness/idempotent-test" ]]
}

@test "git_create_harness_branch: leaves the repo on the harness branch" {
  init_test_repo

  git_create_harness_branch "checkout-test" >/dev/null 2>&1

  local current_branch
  current_branch=$(git branch --show-current)
  [[ "$current_branch" == "harness/checkout-test" ]]
}

# ===========================================================================
# git_create_sprint_branch
# ===========================================================================

@test "git_create_sprint_branch: creates branch with zero-padded sprint number" {
  init_test_repo
  git_create_harness_branch "my-project" >/dev/null 2>&1

  run --separate-stderr git_create_sprint_branch "harness/my-project" 3

  [[ "$status" -eq 0 ]]
  # Verify the branch name includes zero-padded sprint number
  git rev-parse --verify "harness/my-project-sprint-03" >/dev/null 2>&1
}

@test "git_create_sprint_branch: returns branch name on stdout and leaves repo on sprint branch" {
  init_test_repo
  git_create_harness_branch "my-project" >/dev/null 2>&1

  run --separate-stderr git_create_sprint_branch "harness/my-project" 5

  [[ "$status" -eq 0 ]]
  [[ "$output" == "harness/my-project-sprint-05" ]]

  # Verify we're on the sprint branch
  local current_branch
  current_branch=$(git branch --show-current)
  [[ "$current_branch" == "harness/my-project-sprint-05" ]]
}

@test "git_create_sprint_branch: deletes stale sprint branch from prior failed attempt before recreating" {
  init_test_repo
  git_create_harness_branch "my-project" >/dev/null 2>&1

  # Create the stale sprint branch with a commit
  git checkout -b "harness/my-project-sprint-02" >/dev/null 2>&1
  echo "stale content" > stale-file.txt
  git add stale-file.txt
  git commit -q -m "stale commit"

  # Go back to harness branch and add a new commit (advance HEAD)
  git checkout "harness/my-project" >/dev/null 2>&1
  echo "new content" > new-file.txt
  git add new-file.txt
  git commit -q -m "new commit on harness branch"
  local harness_head
  harness_head=$(git rev-parse HEAD)

  # Now create sprint branch -- should delete stale and recreate from harness HEAD
  run --separate-stderr git_create_sprint_branch "harness/my-project" 2

  [[ "$status" -eq 0 ]]

  # The new sprint branch should be based on the harness branch's HEAD, not the stale SHA
  local sprint_base
  sprint_base=$(git rev-parse HEAD)
  [[ "$sprint_base" == "$harness_head" ]]
}

@test "git_create_sprint_branch: handles double-digit sprint numbers correctly" {
  init_test_repo
  git_create_harness_branch "my-project" >/dev/null 2>&1

  run --separate-stderr git_create_sprint_branch "harness/my-project" 12

  [[ "$status" -eq 0 ]]
  [[ "$output" == "harness/my-project-sprint-12" ]]
  git rev-parse --verify "harness/my-project-sprint-12" >/dev/null 2>&1
}

# ===========================================================================
# git_merge_sprint
# ===========================================================================

@test "git_merge_sprint: performs a --no-ff merge of sprint branch into harness branch" {
  init_test_repo
  git_create_harness_branch "my-project" >/dev/null 2>&1
  git_create_sprint_branch "harness/my-project" 1 >/dev/null 2>&1

  # Make a commit on the sprint branch
  echo "sprint work" > sprint-file.txt
  git add sprint-file.txt
  git commit -q -m "sprint 1 work"

  run --separate-stderr git_merge_sprint "harness/my-project" 1 1

  [[ "$status" -eq 0 ]]

  # Verify we're on the harness branch
  local current_branch
  current_branch=$(git branch --show-current)
  [[ "$current_branch" == "harness/my-project" ]]

  # Verify the merge commit message exists
  git log --oneline -1 | grep -q "harness(sprint-01)"
}

@test "git_merge_sprint: creates annotated tag harness/sprint-NN/pass" {
  init_test_repo
  git_create_harness_branch "my-project" >/dev/null 2>&1
  git_create_sprint_branch "harness/my-project" 1 >/dev/null 2>&1

  echo "feature" > feature.txt
  git add feature.txt
  git commit -q -m "feature commit"

  git_merge_sprint "harness/my-project" 1 1 >/dev/null 2>&1

  # Verify the tag exists
  git rev-parse --verify "harness/sprint-01/pass" >/dev/null 2>&1

  # Verify the tag points to the merge commit (HEAD of harness branch)
  local tag_sha head_sha
  tag_sha=$(git rev-parse "harness/sprint-01/pass")
  head_sha=$(git rev-parse HEAD)
  [[ "$tag_sha" == "$head_sha" ]]
}

@test "git_merge_sprint: deletes the sprint branch after merging" {
  init_test_repo
  git_create_harness_branch "my-project" >/dev/null 2>&1
  git_create_sprint_branch "harness/my-project" 1 >/dev/null 2>&1

  echo "work" > work.txt
  git add work.txt
  git commit -q -m "some work"

  git_merge_sprint "harness/my-project" 1 1 >/dev/null 2>&1

  # Verify the sprint branch no longer exists
  run git rev-parse --verify "harness/my-project-sprint-01"
  [[ "$status" -ne 0 ]]
}

@test "git_merge_sprint: returns the merge SHA on stdout" {
  init_test_repo
  git_create_harness_branch "my-project" >/dev/null 2>&1
  git_create_sprint_branch "harness/my-project" 1 >/dev/null 2>&1

  echo "content" > content.txt
  git add content.txt
  git commit -q -m "content commit"

  run --separate-stderr git_merge_sprint "harness/my-project" 1 1

  [[ "$status" -eq 0 ]]

  # The output contains the merge SHA (git branch -d output may precede it)
  local head_sha
  head_sha=$(git rev-parse HEAD)
  [[ "$output" == *"$head_sha"* ]]
}

@test "git_merge_sprint: commits uncommitted changes on sprint branch before merging" {
  init_test_repo
  git_create_harness_branch "my-project" >/dev/null 2>&1
  git_create_sprint_branch "harness/my-project" 1 >/dev/null 2>&1

  # Create committed work
  echo "committed" > committed.txt
  git add committed.txt
  git commit -q -m "committed work"

  # Create uncommitted changes (simulating evaluator artifacts)
  echo "uncommitted content" > uncommitted.txt

  git_merge_sprint "harness/my-project" 1 1 >/dev/null 2>&1

  # Verify uncommitted changes are present in the harness branch after merge
  [[ -f "uncommitted.txt" ]]
  [[ "$(cat uncommitted.txt)" == "uncommitted content" ]]
}

@test "git_merge_sprint: merge commit message includes attempt number" {
  init_test_repo
  git_create_harness_branch "my-project" >/dev/null 2>&1
  git_create_sprint_branch "harness/my-project" 2 >/dev/null 2>&1

  echo "work" > work.txt
  git add work.txt
  git commit -q -m "work"

  git_merge_sprint "harness/my-project" 2 3 >/dev/null 2>&1

  # Verify the merge commit message includes attempt number
  git log --oneline -1 | grep -q "attempt 3"
}

# ===========================================================================
# git_fail_sprint_attempt
# ===========================================================================

@test "git_fail_sprint_attempt: creates a tag harness/sprint-NN/attempt-N" {
  init_test_repo
  git_create_harness_branch "my-project" >/dev/null 2>&1
  git_create_sprint_branch "harness/my-project" 1 >/dev/null 2>&1

  echo "failed work" > failed.txt
  git add failed.txt
  git commit -q -m "failed attempt"

  git_fail_sprint_attempt "harness/my-project" 1 2 >/dev/null 2>&1

  # Verify tag exists
  git rev-parse --verify "harness/sprint-01/attempt-2" >/dev/null 2>&1
}

@test "git_fail_sprint_attempt: returns to the harness branch and deletes the sprint branch" {
  init_test_repo
  git_create_harness_branch "my-project" >/dev/null 2>&1
  git_create_sprint_branch "harness/my-project" 1 >/dev/null 2>&1

  echo "work" > work.txt
  git add work.txt
  git commit -q -m "some work"

  git_fail_sprint_attempt "harness/my-project" 1 1 >/dev/null 2>&1

  # Verify on harness branch
  local current_branch
  current_branch=$(git branch --show-current)
  [[ "$current_branch" == "harness/my-project" ]]

  # Verify sprint branch is deleted
  run git rev-parse --verify "harness/my-project-sprint-01"
  [[ "$status" -ne 0 ]]
}

@test "git_fail_sprint_attempt: handles uncommitted changes via stash without failing" {
  init_test_repo
  git_create_harness_branch "my-project" >/dev/null 2>&1
  git_create_sprint_branch "harness/my-project" 1 >/dev/null 2>&1

  # Make a committed change so the branch has content
  echo "original" > tracked.txt
  git add tracked.txt
  git commit -q -m "add tracked file"

  # Create uncommitted modification to a tracked file (dirty working tree)
  echo "modified content" > tracked.txt

  run --separate-stderr git_fail_sprint_attempt "harness/my-project" 1 1

  [[ "$status" -eq 0 ]]

  # Verify working directory is clean after returning to harness branch
  local git_status
  git_status=$(git status --porcelain)
  [[ -z "$git_status" ]]
}

@test "git_fail_sprint_attempt: increments attempt counter in tag name correctly" {
  init_test_repo
  git_create_harness_branch "my-project" >/dev/null 2>&1

  # First failed attempt
  git_create_sprint_branch "harness/my-project" 3 >/dev/null 2>&1
  echo "attempt1" > attempt.txt
  git add attempt.txt
  git commit -q -m "attempt 1"
  git_fail_sprint_attempt "harness/my-project" 3 1 >/dev/null 2>&1

  # Second failed attempt
  git_create_sprint_branch "harness/my-project" 3 >/dev/null 2>&1
  echo "attempt2" > attempt.txt
  git add attempt.txt
  git commit -q -m "attempt 2"
  git_fail_sprint_attempt "harness/my-project" 3 2 >/dev/null 2>&1

  # Both tags should exist
  git rev-parse --verify "harness/sprint-03/attempt-1" >/dev/null 2>&1
  git rev-parse --verify "harness/sprint-03/attempt-2" >/dev/null 2>&1
}

# ===========================================================================
# git_commit_harness_state
# ===========================================================================

@test "git_commit_harness_state: commits harness-state directory changes with the given message" {
  init_test_repo

  # Modify a file in harness-state
  echo "updated config" > "$HARNESS_STATE/config.json"

  git_commit_harness_state "harness(sprint-01): update config"

  # Verify the commit message
  local last_message
  last_message=$(git log -1 --format="%s")
  [[ "$last_message" == "harness(sprint-01): update config" ]]
}

@test "git_commit_harness_state: is a no-op when nothing has changed in harness-state/" {
  init_test_repo

  local commit_count_before
  commit_count_before=$(git rev-list --count HEAD)

  git_commit_harness_state "should not commit"

  local commit_count_after
  commit_count_after=$(git rev-list --count HEAD)
  [[ "$commit_count_before" -eq "$commit_count_after" ]]
}

@test "git_commit_harness_state: handles both tracked modifications and untracked new files" {
  init_test_repo

  # Create an initial tracked file in harness-state and commit it
  echo '{"initial": true}' > "$HARNESS_STATE/config.json"
  git add "$HARNESS_STATE/config.json"
  git commit -q -m "add initial config"

  # Modify the existing tracked file
  echo '{"modified": true}' > "$HARNESS_STATE/config.json"

  # Add a new untracked file in harness-state
  echo '{"new": true}' > "$HARNESS_STATE/new-file.json"

  git_commit_harness_state "harness: mixed changes"

  # Verify both files are committed
  local changed_files
  changed_files=$(git diff-tree --no-commit-id --name-only -r HEAD)
  echo "$changed_files" | grep -q "harness-state/config.json"
  echo "$changed_files" | grep -q "harness-state/new-file.json"
}

# ===========================================================================
# generate_pr_body
# ===========================================================================

@test "generate_pr_body: produces markdown containing sprint results table with correct column headers" {
  init_test_repo

  # Install fixtures
  install_fixture "config-valid.json" "$HARNESS_STATE/config.json"
  install_fixture "sprint-plan-3sprint.json" "$HARNESS_STATE/sprint-plan.json"

  run --separate-stderr generate_pr_body

  [[ "$status" -eq 0 ]]
  # Check for table header columns
  echo "$output" | grep -q "| Sprint | Name | Status | Criteria | Pass | Fail | Attempts | Cost |"
}

@test "generate_pr_body: includes PASS status from eval reports when they exist" {
  init_test_repo

  install_fixture "config-valid.json" "$HARNESS_STATE/config.json"
  install_fixture "sprint-plan-3sprint.json" "$HARNESS_STATE/sprint-plan.json"

  # Install eval report for sprint 1
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "eval-report-pass.json" "$HARNESS_STATE/sprints/sprint-01/eval-report.json"

  run --separate-stderr generate_pr_body

  [[ "$status" -eq 0 ]]
  # Verify PASS appears in the output for sprint 1
  echo "$output" | grep -q "PASS"
}

@test "generate_pr_body: shows pending status for sprints without eval reports" {
  init_test_repo

  install_fixture "config-valid.json" "$HARNESS_STATE/config.json"
  install_fixture "sprint-plan-3sprint.json" "$HARNESS_STATE/sprint-plan.json"

  # Install eval report only for sprint 1
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  install_fixture "eval-report-pass.json" "$HARNESS_STATE/sprints/sprint-01/eval-report.json"

  run --separate-stderr generate_pr_body

  [[ "$status" -eq 0 ]]
  # Sprint 2 and 3 should show 'pending'
  echo "$output" | grep -q "pending"
}

@test "generate_pr_body: includes configuration summary with model, context strategy, and project type" {
  init_test_repo

  install_fixture "config-valid.json" "$HARNESS_STATE/config.json"
  install_fixture "sprint-plan-3sprint.json" "$HARNESS_STATE/sprint-plan.json"

  run --separate-stderr generate_pr_body

  [[ "$status" -eq 0 ]]
  # config-valid.json has model: opus, contextStrategy: reset, projectType: web-app
  echo "$output" | grep -q "opus"
  echo "$output" | grep -q "reset"
  echo "$output" | grep -q "web-app"
}
