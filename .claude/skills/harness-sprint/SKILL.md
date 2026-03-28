---
name: harness-sprint
description: >
  Run a single sprint cycle: contract negotiation, implementation, and evaluation.
  Use for targeted sprint execution with oversight between phases.
argument-hint: "[sprint-number]"
---

Run sprint $ARGUMENTS of the harness:

## Pre-flight

1. Verify `harness-state/sprint-plan.json` exists
2. Verify the sprint number is valid
3. Check dependencies: verify all `dependsOn` sprints have status "pass"

## Contract Negotiation (if needed)

If `harness-state/sprints/sprint-$ARGUMENTS/contract.json` does not exist:
1. Delegate to @"generator (agent)": "Propose a contract for sprint $ARGUMENTS"
2. Delegate to @"evaluator (agent)": "Review the contract proposal for sprint $ARGUMENTS"
3. If revisions needed, iterate (max 3 rounds)
4. Commit: `harness(contract): sprint-$ARGUMENTS agreed`

## Implementation

1. Create sprint branch: `harness/{project}/sprint-$ARGUMENTS`
2. Delegate to @"generator (agent)": "Implement sprint $ARGUMENTS"
3. Wait for status.json = "ready-for-eval"

## Evaluation

1. Delegate to @"evaluator (agent)": "Evaluate sprint $ARGUMENTS"
2. Report results to the user

## On PASS
- Merge sprint branch, tag, update handoff + progress + regression registry

## On FAIL
- Show the user the blocking failures
- Ask if they want to retry (with optional additional guidance)
