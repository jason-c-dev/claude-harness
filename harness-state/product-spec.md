# Product Specification: Comprehensive Bats-Core Test Suite

## Product Overview

This project delivers a standalone, comprehensive bats-core test suite for the Planner-Generator-Evaluator harness -- a bash-based multi-agent orchestrator that coordinates Claude Code agents through git branches, file contracts, and validation hooks. The test suite lives in `meta-tests/` and provides independent verification of every pure function, git operation, and hook validation rule in the harness.

The harness already has a `tests/` directory with layer-based coverage. This `meta-tests/` suite is structurally independent: its own fixtures, its own test helper, its own entry point (`meta-tests/run.sh`). It serves as both a regression safety net and as living documentation of every function's contract. When a developer changes `slugify()` or `git_merge_sprint()`, the meta-tests tell them exactly what broke and why.

The suite is designed to run fast (under 60 seconds), require no external services (no real Claude calls, no network), and produce clear, actionable output. Every test is isolated in a temporary directory that is cleaned up on teardown. Git tests use real git repos initialized in `/tmp`, not mocks -- because git behavior is the thing being tested.

## Target Users

### 1. Harness Developer
**Goal**: Modify harness internals (utils, git operations, hooks) with confidence that nothing regresses.
**Pain point**: The existing `tests/layer1/` suite covers the basics but is entangled with the mock-claude infrastructure. A developer fixing `update_handoff()` wants a focused test file they can run in isolation.

### 2. Harness Contributor
**Goal**: Understand function contracts before contributing a PR.
**Pain point**: Reading bash source code doesn't clearly communicate edge cases. Well-named test cases like `slugify: collapses consecutive special characters into single hyphen` serve as executable specifications.

### 3. CI Pipeline
**Goal**: Fast, deterministic gate that blocks broken PRs.
**Pain point**: Layer 2 and 3 tests cost money and are slow. This suite is free and fast -- suitable as a required check on every push.

## Feature Specification

### F1: Test Runner Entry Point (`meta-tests/run.sh`)
**Description**: A single executable script that discovers and runs all `.bats` files in the suite, with clear output and proper exit codes.

**Why it matters**: Developers and CI need one command to run everything. No hunting for individual test files.

**Key behaviors**:
- Checks for `bats` and `jq` prerequisites; prints install instructions if missing
- Discovers all `*.bats` files under `meta-tests/`
- Runs them via `bats` with `--tap` or pretty output based on TTY detection
- Exits with non-zero status if any test fails
- Supports `--filter` argument to run a subset of tests by name pattern
- Prints summary: total tests, passed, failed, duration

**Dependencies**: None (entry point for everything else)

### F2: Test Helper Library (`meta-tests/helpers/test-helper.bash`)
**Description**: Shared setup/teardown functions and utility helpers loaded by every `.bats` file.

**Why it matters**: Eliminates boilerplate in test files. Provides consistent isolation guarantees.

**Key behaviors**:
- `setup()`: Creates isolated temp directory, sets `HARNESS_STATE` env var, creates required subdirectories (`sprints/`, `regression/`)
- `teardown()`: Removes temp directory unconditionally
- `init_test_repo()`: Initializes a git repo in the temp dir with an initial commit, sets user.name/email for deterministic commits
- `source_harness_lib(LIB)`: Sources a harness lib file with correct `SCRIPT_DIR` so sibling imports resolve
- `install_fixture(NAME, DEST)`: Copies a fixture file from `meta-tests/helpers/fixtures/` to a destination path, creating parent directories
- `assert_json_field(FILE, PATH, EXPECTED)`: Shorthand for `jq` field assertion with clear error messages
- `run_hook(HOOK_NAME)`: Runs a hook script with empty stdin piped in, captures exit code

**Dependencies**: None (foundation for all tests)

### F3: Fixture Files (`meta-tests/helpers/fixtures/`)
**Description**: A curated set of JSON and Markdown fixture files representing valid and invalid harness state.

**Why it matters**: Tests need realistic but deterministic data. Fixtures decouple test logic from data construction.

**Key fixtures**:
- `config-valid.json`: Standard config with all fields populated
- `config-minimal.json`: Config with only required fields, defaults for rest
- `contract-3criteria.json`: Contract with 3 criteria (C1-01, C1-02, C1-03) for registry tests
- `contract-empty-criteria.json`: Contract with empty criteria array (edge case)
- `handoff-empty.json`: Freshly initialized handoff with no completed sprints
- `handoff-with-sprints.json`: Handoff after 2 completed sprints
- `eval-report-pass.json`: Passing eval report matching 3-criteria contract
- `eval-report-fail.json`: Failing eval report with blocking failures
- `eval-report-malformed.json`: JSON missing required fields (for hook validation tests)
- `contract-review-accepted.json`: Evaluator accepts contract proposal
- `contract-review-revise.json`: Evaluator requests revision
- `contract-review-no-decision.json`: Malformed review missing decision field
- `sprint-plan-3sprint.json`: Sprint plan with 3 sprints for progress/PR body tests
- `status-active.json`, `status-ready-for-eval.json`, `status-blocked.json`, `status-pass.json`: Status files for each lifecycle phase
- `registry-empty.json`: Fresh regression registry
- `registry-populated.json`: Registry with criteria from 2 sprints
- `generator-log.md`: Sample generator work log

**Dependencies**: None (static data)

### F4: Unit Tests for Pure Functions (`meta-tests/test-utils-pure.bats`)
**Description**: Exhaustive tests for all pure (no side effects, no file I/O) functions in `harness/lib/utils.sh`.

**Why it matters**: Pure functions are the easiest to test and the most likely to have subtle edge cases (e.g., slugify with Unicode, sprint_pad with large numbers).

**Functions tested**:
- **`slugify`**: lowercase conversion, special character removal, hyphen collapsing, leading/trailing hyphen stripping, 50-char truncation, empty string handling, already-slugified passthrough, spaces-and-tabs, mixed case with numbers
- **`sprint_pad`**: single digit (3 -> "03"), double digit (12 -> "12"), zero (0 -> "00"), large number (100 -> "100")
- **`sprint_dir`**: correct path construction for single and double digit sprint numbers, respects HARNESS_STATE override
- **`json_read`**: reads top-level field, reads nested field (`.git.branch`), reads array element (`.sprints[0].name`), returns empty string for missing file, returns empty/null for missing field, handles malformed JSON gracefully
- **`file_exists`**: true for non-empty file, false for missing file, false for empty file, false for directory

**Dependencies**: F2 (test helper)

### F5: Unit Tests for State Management Functions (`meta-tests/test-utils-state.bats`)
**Description**: Tests for utils.sh functions that read/write harness state files.

**Why it matters**: State management bugs are the hardest to debug in the harness because they cascade through sprints. Thorough tests catch corruption early.

**Functions tested**:
- **`init_harness_state`**: Creates all required files (config.json, cost-log.json, regression/registry.json, progress.md). Config contains correct prompt, project type, and defaults. Cost log starts with empty invocations array. Registry starts with empty sprints object. Progress.md contains project name and timestamp. Respects environment variables (MODEL, CONTEXT_STRATEGY, MAX_SPRINT_ATTEMPTS, etc.).
- **`log_cost`**: Appends entry to cost-log.json with correct role, sprint, and token counts. Handles missing usage fields gracefully (defaults to 0). Multiple calls accumulate entries.
- **`update_progress`**: Appends sprint entry to progress.md. Includes sprint name from sprint-plan.json. Includes status, attempt, timestamp. Includes merge SHA when provided. Omits merge SHA line when not provided.
- **`update_handoff`**: Creates handoff.json if missing. Adds sprint number to completedSprints. Updates currentSprint to N+1. Updates git.latestTag and git.latestMergeSha. Idempotent -- adding same sprint twice doesn't duplicate. Preserves existing fields when updating.
- **`update_regression_registry`**: Extracts criteria IDs from contract.json. Adds sprint entry to registry with criteria array and contract path. No-op when contract file is missing. No-op when contract file is empty. Handles contract with no criteria array.

**Dependencies**: F2 (test helper), F3 (fixtures)

### F6: Git Operation Tests (`meta-tests/test-git.bats`)
**Description**: Tests for all functions in `harness/lib/git.sh` using real git repositories created in temporary directories.

**Why it matters**: Git operations are the riskiest part of the harness. Branch creation, merging, tagging, and cleanup must be bulletproof. These tests use real git (not mocks) to catch actual git behavior.

**Functions tested**:
- **`git_create_harness_branch`**: Creates `harness/{slug}` branch from main. Idempotent -- re-running checks out existing branch. Returns branch name on stdout. Handles repos without remotes.
- **`git_create_sprint_branch`**: Creates `{harness-branch}-sprint-NN` from harness branch. Zero-pads sprint number. Deletes stale sprint branch from prior failed attempt. Returns branch name. Leaves repo on sprint branch.
- **`git_merge_sprint`**: Merges sprint branch to harness branch with `--no-ff`. Creates annotated tag `harness/sprint-NN/pass`. Deletes sprint branch after merge. Returns merge SHA. Commits any uncommitted changes before merging (evaluator artifacts).
- **`git_fail_sprint_attempt`**: Tags attempt as `harness/sprint-NN/attempt-N`. Returns to harness branch. Deletes sprint branch. Handles uncommitted changes via stash.
- **`git_commit_harness_state`**: Commits harness-state directory with given message. No-op when nothing changed. Handles both tracked and untracked files.
- **`generate_pr_body`**: Produces markdown table with sprint results. Includes PASS/FAIL status from eval reports. Includes configuration summary. Handles missing eval reports gracefully (shows "pending").

**Dependencies**: F2 (test helper), F3 (fixtures)

### F7: Hook Validation Tests (`meta-tests/test-hooks.bats`)
**Description**: Tests for all three hook scripts in `harness/hooks/`, verifying correct exit codes and error messages for every validation rule.

**Why it matters**: Hooks are the guardrails that prevent agents from completing prematurely. A broken hook means the harness can produce incomplete or invalid output without any warning.

**Scripts tested**:

- **`on-generator-stop.sh`**:
  - Allows (exit 0) when no active sprint exists
  - Allows when status is `ready-for-eval` and generator-log.md exists
  - Allows when status is `blocked`
  - Blocks (exit 2) when status is `active` (not yet ready)
  - Blocks when status is `ready-for-eval` but generator-log.md is missing
  - Allows during contract negotiation phase (proposal exists, no contract yet)
  - Correctly finds sprint in fix-* and refactor-* directories
  - Handles multiple sprint directories (picks the active one)

- **`on-evaluator-stop.sh`**:
  - Allows when no sprint is being evaluated
  - Allows valid eval report with overallResult and criteriaResults
  - Blocks when eval-report.json is missing
  - Blocks when overallResult field is missing
  - Blocks when criteriaResults field is missing
  - Blocks when criteria count in report < contract criteria count
  - Allows when criteria count in report >= contract criteria count
  - Allows valid contract review with decision field
  - Blocks contract review when contract-review.json is missing
  - Blocks contract review when decision field is missing

- **`on-stop.sh`**:
  - Allows when no sprint-plan.json exists (not a harness session)
  - Allows when all sprints have terminal status (pass/fail)
  - Blocks when any sprint has status `active`
  - Blocks when any sprint has status `negotiating`
  - Blocks when any sprint has status `ready-for-eval`
  - Allows when sprint directories exist but have no status.json

**Dependencies**: F2 (test helper), F3 (fixtures)

### F8: Edge Case and Error Handling Tests (`meta-tests/test-edge-cases.bats`)
**Description**: Targeted tests for boundary conditions, malformed input, and error recovery across all modules.

**Why it matters**: The harness runs autonomously for long periods. Silent failures or corrupted state can waste expensive Claude invocations. Edge case tests catch the bugs that only appear at 2 AM on sprint 7.

**Key scenarios**:
- `slugify` with empty string, string of only special characters, string of only spaces
- `json_read` with binary file, with truncated JSON, with extremely deeply nested path
- `init_harness_state` with prompt containing quotes, newlines, and special JSON characters
- `update_handoff` called before init (creates handoff from scratch)
- `update_regression_registry` with malformed contract JSON
- `git_create_sprint_branch` when harness branch doesn't exist
- `git_merge_sprint` with merge conflicts (should they arise)
- Hooks receiving empty stdin (they should still work -- hooks always cat stdin first)
- Multiple sprint directories with mixed statuses (hook picks correct one)
- HARNESS_STATE pointing to non-default path

**Dependencies**: F2 (test helper), F3 (fixtures), F4-F7

## Visual Design Language

Not applicable -- this is a CLI test suite. Output design focuses on:
- **Clarity**: Test names are self-documenting sentences (`slugify: collapses consecutive hyphens`)
- **Signal over noise**: Failed tests show expected vs. actual values, not stack traces
- **Grouping**: Tests are organized by module and function, making it easy to find coverage for any function
- **TAP output**: Machine-readable when piped, human-readable in terminal (via bats pretty formatter)

## Technical Architecture

### Stack
- **Test framework**: bats-core (Bash Automated Testing System)
- **JSON manipulation**: jq (required dependency, checked at startup)
- **Version control**: Real git repos in temp directories (no git mocks)
- **Shell**: Bash (same as harness itself)

### Directory Structure
```
meta-tests/
  run.sh                        # Entry point
  helpers/
    test-helper.bash            # Shared setup/teardown/utilities
    fixtures/                   # JSON and Markdown test data
      config-valid.json
      config-minimal.json
      contract-3criteria.json
      ...
  test-utils-pure.bats         # F4: Pure function tests
  test-utils-state.bats        # F5: State management tests
  test-git.bats                # F6: Git operation tests
  test-hooks.bats              # F7: Hook validation tests
  test-edge-cases.bats         # F8: Edge cases and error handling
```

### Key Design Decisions
- **Independent from `tests/`**: The meta-tests suite has its own helper and fixtures. It does not import from or depend on the existing `tests/` directory. This ensures it can serve as an independent verification layer.
- **Real git, not mocked**: Git tests create actual temporary repositories. Mock git would defeat the purpose -- we need to verify real branch creation, merging, and tagging behavior.
- **Fixture-driven**: All test data comes from fixture files, not inline JSON strings. This makes fixtures reusable and test code readable.
- **One bats file per module**: Mapping is straightforward: `test-utils-pure.bats` tests pure utils, `test-git.bats` tests git.sh, etc.
- **No network, no Claude**: The meta-tests never invoke Claude or touch the network. They test harness infrastructure code only.

## Sprint Decomposition

### Sprint 1: Test Infrastructure Foundation
Set up the `meta-tests/` directory, the test helper library, fixture files, and the `run.sh` entry point. After this sprint, `bash meta-tests/run.sh` executes successfully with zero tests.

### Sprint 2: Pure Function Unit Tests
Write exhaustive tests for all pure functions in utils.sh: `slugify`, `sprint_pad`, `sprint_dir`, `json_read`, `file_exists`. These have no dependencies on state files.

### Sprint 3: State Management Unit Tests
Write tests for state-mutating functions: `init_harness_state`, `log_cost`, `update_progress`, `update_handoff`, `update_regression_registry`. These create and modify files in the temporary harness-state directory.

### Sprint 4: Git Operation Tests
Write tests for all `git.sh` functions using isolated temporary git repositories. Covers branch creation, sprint branching, merging, failure tagging, state commits, and PR body generation.

### Sprint 5: Hook Validation Tests
Write tests for all three hook scripts (`on-generator-stop.sh`, `on-evaluator-stop.sh`, `on-stop.sh`), verifying correct exit codes and error messages for every validation path.

### Sprint 6: Edge Cases, Error Handling, and Polish
Add edge case tests across all modules, verify error recovery, test with malformed inputs, and ensure `run.sh` produces clean summary output. Final integration verification.
