# Sprint 03: State Management Unit Tests - Generator Log

## Summary

Implemented `meta-tests/test-utils-state.bats` with 24 tests covering all five state management functions in `harness/lib/utils.sh`.

## Functions Tested

### init_harness_state (7 tests)
- Creates config.json with correct userPrompt and projectType from arguments
- Creates all required files (config.json, cost-log.json, regression/registry.json, progress.md)
- cost-log.json starts with empty invocations array and totalCost of 0
- regression/registry.json starts with empty sprints object and lastFullRun as null
- progress.md contains the project prompt text and model name
- Respects environment variables (MODEL, CONTEXT_STRATEGY, MAX_SPRINT_ATTEMPTS, COST_CAP_PER_SPRINT, TOTAL_COST_CAP)
- Uses correct defaults when environment variables are not set

### log_cost (3 tests)
- Appends entry with correct role, sprint, and token counts
- Handles missing usage fields gracefully, defaulting token counts to 0
- Multiple calls accumulate entries in the invocations array

### update_progress (4 tests)
- Appends sprint entry with correct sprint name from sprint-plan.json
- Includes status and attempt number in the appended entry
- Includes merge SHA in the entry when provided
- Omits merge SHA line when merge_sha argument is empty or not provided

### update_handoff (6 tests)
- Creates handoff.json from scratch when the file does not exist
- Adds sprint number to completedSprints array
- Updates currentSprint to N+1
- Updates git.latestTag and git.latestMergeSha
- Idempotent -- calling with same sprint number twice does not duplicate
- Preserves existing fields (projectName, techStack, etc.) when updating

### update_regression_registry (4 tests)
- Extracts criteria IDs from contract.json and adds sprint entry to registry
- No-op when contract file is missing
- No-op when contract file is empty
- Handles contract with no criteria array gracefully

## Issues Encountered & Fixed

1. **Decimal values in cost caps**: The shell expansion `${COST_CAP_PER_SPRINT:-25.00}` preserves the `.00` suffix, so assertions needed to match `"50.00"` not `"50"`.
2. **Grep regex vs fixed strings**: `grep "**Status**"` fails because `*` is a regex metacharacter. Fixed by using `grep -F` for fixed-string matching.

## Test Results

All 58 tests pass (8 infrastructure + 26 pure functions + 24 state management):
```
bash meta-tests/run.sh -> exit code 0, 3 seconds
```

## Criteria Coverage

| Criterion | Status | Notes |
|-----------|--------|-------|
| C3-01 | PASS | File exists, loads test-helper |
| C3-02 | PASS | source_harness_lib 'utils.sh' in setup |
| C3-03 | PASS | init_harness_state userPrompt/projectType test |
| C3-04 | PASS | All four required files created |
| C3-05 | PASS | cost-log.json empty invocations, totalCost=0 |
| C3-06 | PASS | registry.json empty sprints, null lastFullRun |
| C3-07 | PASS | progress.md contains prompt and model |
| C3-08 | PASS | Environment variables respected |
| C3-09 | PASS | Defaults used when env vars unset |
| C3-10 | PASS | log_cost appends with correct fields |
| C3-11 | PASS | Missing usage fields default to 0 |
| C3-12 | PASS | Multiple calls accumulate entries |
| C3-13 | PASS | Sprint name from sprint-plan.json |
| C3-14 | PASS | Status and attempt in progress entry |
| C3-15 | PASS | Merge SHA included when provided |
| C3-16 | PASS | Merge SHA omitted when empty |
| C3-17 | PASS | handoff.json created from scratch |
| C3-18 | PASS | Sprint added to completedSprints |
| C3-19 | PASS | currentSprint = N+1 |
| C3-20 | PASS | git.latestTag and latestMergeSha |
| C3-21 | PASS | Idempotent, no duplicates |
| C3-22 | PASS | Preserves existing fields |
| C3-23 | PASS | Registry gets criteria and contractPath |
| C3-24 | PASS | No-op when contract missing |
| C3-25 | PASS | No-op when contract empty |
| C3-26 | PASS | Empty criteria array handled |
| C3-27 | PASS | All tests pass via run.sh |
| C3-28 | PASS | All test names follow 'function: behavior' convention |
| C3-29 | PASS | Sprint 1 infrastructure tests still pass |
| C3-30 | PASS | Sprint 2 pure function tests still pass |
