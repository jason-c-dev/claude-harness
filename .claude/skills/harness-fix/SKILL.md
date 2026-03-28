---
name: harness-fix
description: >
  Fix a specific bug in a harness-built project. Creates a GitHub issue, generates a
  surgical fix contract, implements the fix, and verifies with regression testing.
argument-hint: "[bug description]"
---

Fix bug: $ARGUMENTS

## Steps

1. Create a GitHub issue: `gh issue create --title "Bug: $ARGUMENTS" --label "harness-fix,bug"`
2. Determine the fix sprint ID (fix-001, fix-002, etc.)
3. Generate a fix contract:
   - Criteria that verify the bug is fixed
   - Regression criteria from related sprints
   Write to `harness-state/sprints/{fix-id}/contract.json`
4. Create a fix branch from the harness branch
5. Delegate to @"generator (agent)": fix the bug against the contract
6. Delegate to @"evaluator (agent)": verify the fix + regression
7. On PASS: merge, tag, update regression registry
8. The PR should reference the GitHub issue: `Fixes #N`

The fix contract should be narrow and surgical -- just enough criteria to verify the fix
and ensure nothing else broke.
