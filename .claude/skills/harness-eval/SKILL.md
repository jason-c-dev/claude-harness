---
name: harness-eval
description: >
  Evaluate a sprint against its contract. Runs the evaluator agent to test the running
  application. Use to re-evaluate after manual changes or to verify a sprint.
argument-hint: "[sprint-number]"
context: fork
agent: evaluator
---

Evaluate sprint $ARGUMENTS.

1. Read the contract at `harness-state/sprints/sprint-$ARGUMENTS/contract.json`
2. Read `harness-state/handoff.json` for dev server info and git branch names
3. Use `git diff` to understand what changed in this sprint
4. Start the dev server
5. Test every criterion in the contract
6. Run regression tests if `regressionSprints` is specified
7. Score holistic dimensions based on the project type in `config.json`
8. Write report to `harness-state/sprints/sprint-$ARGUMENTS/eval-report.json`
9. Update `status.json`
