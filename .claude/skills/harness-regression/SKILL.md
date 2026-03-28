---
name: harness-regression
description: >
  Run all prior evaluations against the current codebase. Tests every blocking criterion
  from every completed sprint. Use to verify nothing has regressed.
context: fork
agent: evaluator
---

Run a full regression test sweep.

1. Read `harness-state/regression/registry.json` for all prior sprint criteria
2. For each sprint in the registry:
   a. Load its contract from the `contractPath`
   b. Test each blocking criterion listed in `criteria`
3. Start the dev server and test the running application
4. Write results to `harness-state/regression/last-run.json`:
   ```json
   {
     "timestamp": "ISO-8601",
     "sprintsChecked": [1, 2, 3],
     "criteriaChecked": 42,
     "pass": 41,
     "fail": 1,
     "failures": [
       {
         "originalSprint": 3,
         "criteriaId": "C3-07",
         "evidence": "Description of regression"
       }
     ]
   }
   ```
5. Report results clearly: how many passed, how many failed, which specific criteria regressed
