---
name: harness-refactor
description: >
  Refactor code without changing behavior. Runs full regression against ALL prior sprint
  criteria to verify nothing broke. Use for technical debt, architecture changes.
argument-hint: "[refactor description]"
---

Refactor: $ARGUMENTS

## Steps

1. Run pre-refactor regression baseline (full sweep of all prior sprint criteria)
2. Generate a refactor contract:
   - Code quality criteria for the refactor goals
   - ALL prior sprint criteria as regression tests
   Write to `harness-state/sprints/refactor-NNN/contract.json`
3. Create a refactor branch
4. Delegate to @"generator (agent)": implement the refactor. Behavior MUST NOT change.
5. Delegate to @"evaluator (agent)": verify refactor criteria + FULL regression
6. On PASS: merge, tag `harness/refactor-NNN/pass`

This is the most expensive evaluation mode because every prior criterion gets re-tested.
That's intentional -- refactors must not break anything.
