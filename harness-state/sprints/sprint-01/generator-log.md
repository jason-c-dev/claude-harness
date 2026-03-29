# Sprint 01 Generator Log: Test Infrastructure Foundation

## Summary
Implemented the complete test infrastructure foundation for the meta-tests suite. All 30 contract criteria verified passing.

## Features Implemented

### F1: Test Runner Entry Point (meta-tests/run.sh)
- Executable script with `chmod +x`
- Prerequisite checks for `bats` and `jq` with install instructions on stderr
- Discovers all `*.bats` files under `meta-tests/` via `find`
- TTY-aware output format (pretty vs TAP)
- `--filter` argument support, passed through to bats
- Prints summary with duration and exit code
- Exits with bats exit code (0 for all pass, non-zero for failures)

### F2: Test Helper Library (meta-tests/helpers/test-helper.bash)
- `setup()`: Creates isolated temp dir (`mktemp -d`), exports `TEST_TEMP_DIR`, `cd`s into it, sets `HARNESS_STATE`, creates `sprints/` and `regression/` subdirs
- `teardown()`: Unconditionally removes `TEST_TEMP_DIR` via `rm -rf`
- `init_test_repo()`: `git init`, sets `user.email` and `user.name`, creates initial commit
- `source_harness_lib(LIB)`: Sets `SCRIPT_DIR` to `harness/lib` and sources the requested lib
- `install_fixture(NAME, DEST)`: Creates parent dirs with `mkdir -p`, copies from fixtures dir
- `assert_json_field(FILE, PATH, EXPECTED)`: Uses `jq -r` to read field, compares to expected, prints diagnostic with Path/Expected/Actual on failure
- `run_hook(HOOK_NAME)`: Pipes empty stdin to hook script, captures exit code

### F3: Fixture Files (20 files)
- `config-valid.json`: All 8 config fields populated (userPrompt, projectType, contextStrategy, model, maxSprintAttempts, maxContractRounds, costCapPerSprint, totalCostCap)
- `config-minimal.json`: Only required fields (userPrompt, projectType)
- `contract-3criteria.json`: 3 criteria with IDs C1-01, C1-02, C1-03
- `contract-empty-criteria.json`: Empty criteria array `[]`
- `handoff-empty.json`: Empty completedSprints array
- `handoff-with-sprints.json`: 2 completed sprints
- `eval-report-pass.json`: overallResult=PASS
- `eval-report-fail.json`: overallResult=FAIL, blockingFailures=2
- `eval-report-malformed.json`: Missing overallResult and criteriaResults fields
- `contract-review-accepted.json`: decision=accepted
- `contract-review-revise.json`: decision=revise
- `contract-review-no-decision.json`: Missing decision field
- `sprint-plan-3sprint.json`: 3 sprints with number and name fields
- `status-active.json`: status=active
- `status-ready-for-eval.json`: status=ready-for-eval
- `status-blocked.json`: status=blocked
- `status-pass.json`: status=pass
- `registry-empty.json`: Empty sprints object `{}`
- `registry-populated.json`: 2 sprint entries with criteria arrays
- `generator-log.md`: Non-empty sample generator work log

### Bonus: test-infrastructure.bats
Sanity-check test file with 8 tests verifying the helper infrastructure works (temp dirs, HARNESS_STATE, fixtures, assert_json_field, init_test_repo, source_harness_lib).

## Criteria Verification

All 30 criteria self-tested and verified passing:
- C1-01 through C1-07: Directory structure, run.sh behavior, prerequisite checks, file discovery, exit codes, --filter
- C1-08 through C1-16: test-helper.bash sourceable, all helper functions verified via code inspection
- C1-17 through C1-27: All fixture files verified via jq parsing and field inspection
- C1-28: Zero references to tests/ directory in meta-tests/ (comment was fixed to avoid false positive)
- C1-29: `bash meta-tests/run.sh` exits 0 with no infrastructure errors
- C1-30: All JSON fixture files parse cleanly via jq

## Commits
1. `6edefb2` harness(sprint-01): test infrastructure foundation [C1-01 through C1-30]
2. `ec6b9a0` harness(sprint-01): fix comment to avoid false positive on independence check [C1-28]

## Issues Encountered
- Path resolution: Initial test-helper.bash had `META_DIR = PROJECT_DIR` which caused FIXTURE_DIR to point to project root instead of meta-tests/. Fixed by resolving META_DIR from `dirname $BATS_TEST_FILENAME` directly.
- False positive on C1-28: A comment containing "meta-tests/helpers/fixtures/" triggered the `tests/helpers` grep pattern. Fixed by rewording the comment.
