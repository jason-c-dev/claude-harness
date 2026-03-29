# Sprint 04: Git Operation Tests - Generator Log

## Summary

Implemented `meta-tests/test-git.bats` with 25 tests covering all 6 git.sh functions. All tests pass, and the full suite (83 tests) has no regressions.

## Criteria Coverage

| Criterion | Status | Notes |
|-----------|--------|-------|
| C4-01 | PASS | File exists, valid bats shebang, loads test-helper |
| C4-02 | PASS | All 25 tests pass with exit code 0 |
| C4-03 | PASS | Full suite (83 tests) passes via `bash meta-tests/run.sh` |
| C4-04 | PASS | 25 @test blocks covering all 6 functions (>= 20 required) |
| C4-05 | PASS | Test verifies branch creation from main |
| C4-06 | PASS | Test captures and asserts stdout output matches branch name |
| C4-07 | PASS | Test calls function twice, verifies idempotent behavior |
| C4-08 | PASS | Test verifies zero-padded sprint number in branch name |
| C4-09 | PASS | Test checks return value and current branch after call |
| C4-10 | PASS | Test pre-creates stale branch, verifies replacement from new HEAD |
| C4-11 | PASS | Test verifies --no-ff merge with correct commit message |
| C4-12 | PASS | Test verifies tag existence and points to merge commit |
| C4-13 | PASS | Test verifies sprint branch deleted after merge |
| C4-14 | PASS | Test captures output and verifies SHA matches HEAD |
| C4-15 | PASS | Test creates uncommitted file, verifies present after merge |
| C4-16 | PASS | Test verifies attempt tag creation |
| C4-17 | PASS | Test verifies return to harness branch and sprint branch deletion |
| C4-18 | PASS | Test uses tracked modification, verifies clean working tree |
| C4-19 | PASS | Test modifies harness-state file, verifies commit message |
| C4-20 | PASS | Test verifies no new commit when nothing changed |
| C4-21 | PASS | Test creates tracked mod + untracked file, verifies both committed |
| C4-22 | PASS | Test verifies table header columns in output |
| C4-23 | PASS | Test installs eval-report-pass.json fixture, verifies PASS in output |
| C4-24 | PASS | Test verifies "pending" for sprints without eval reports |
| C4-25 | PASS | Test verifies model, contextStrategy, projectType in output |
| C4-26 | PASS | All tests use init_test_repo for isolation |
| C4-27 | PASS | All test names follow "function_name: behavior description" |
| C4-28 | PASS | Uses source_harness_lib, no hardcoded paths |

## Key Decisions

1. **Source utils.sh before git.sh**: git.sh conditionally skips sourcing utils.sh when `HARNESS_STATE` is already set (which the test helper does). Explicitly sourcing utils.sh first ensures all utility functions (`log_info`, `sprint_pad`, `json_read`, etc.) are available.

2. **Use `run --separate-stderr`**: Bats 1.13.0 merges stdout and stderr in `$output` by default. Using `--separate-stderr` ensures clean stdout capture for tests that check return values (branch names, SHAs). Added `bats_require_minimum_version 1.5.0` to enable this feature.

3. **Tracked modifications for stash tests**: `git stash` (without `-u`) doesn't capture untracked files. Changed the dirty-working-tree test to use a tracked file modification instead of an untracked file, which correctly exercises the stash behavior.

4. **Glob match for merge SHA**: `git_merge_sprint` outputs both `git branch -d` text and the merge SHA to stdout. Used `[[ "$output" == *"$head_sha"* ]]` instead of negative array index (not supported in bash 3.2).

## Commits

- `f11c3d5` - harness(sprint-04): implement git operation tests [C4-01 through C4-28]
