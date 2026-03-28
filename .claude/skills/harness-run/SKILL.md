---
name: harness-run
description: >
  Run the full Planner-Generator-Evaluator harness pipeline. Fire and forget: plans the
  project, runs all sprints, creates a PR. Use for initial builds.
argument-hint: "[project description]"
---

Execute the full harness pipeline for: $ARGUMENTS

## Steps

1. Initialize `harness-state/config.json` with the user's prompt
2. Create a harness git branch from main
3. Delegate to @"planner (agent)" to produce `product-spec.md` and `sprint-plan.json`
4. Commit the plan and tag `harness/plan`
5. For each sprint in the plan:
   a. Run contract negotiation: @"generator (agent)" proposes, @"evaluator (agent)" reviews (max 3 rounds)
   b. Create a sprint branch
   c. @"generator (agent)" implements against the contract
   d. @"evaluator (agent)" tests against the contract + regression criteria
   e. On PASS: merge sprint branch, tag `harness/sprint-NN/pass`
   f. On FAIL: tag attempt for forensics, delete branch, retry (max 3 attempts)
   g. Update `handoff.json`, `progress.md`, regression registry
6. Create PR from harness branch to main with evaluation summaries

Before starting, ask the user for `projectType` if not obvious from the prompt
(web-frontend, backend-api, cli-tool, or general).
