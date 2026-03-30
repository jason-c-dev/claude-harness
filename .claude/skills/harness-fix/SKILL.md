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
7. On PASS:
   - Tag `harness/{fix-id}/pass` on the fix branch
   - Update regression registry
   - Commit harness state
   - Push the fix branch: `git push -u origin {fix-branch}`
   - Create a PR: `gh pr create --base {harness-branch-or-main} --head {fix-branch} --title "harness({fix-id}): {description}" --body "..."`
   - The PR body must include `Fixes #{issue-number}` to auto-close the GitHub issue
8. Do NOT merge locally. The fix goes through a PR for review.

The fix contract should be narrow and surgical -- just enough criteria to verify the fix
and ensure nothing else broke.
