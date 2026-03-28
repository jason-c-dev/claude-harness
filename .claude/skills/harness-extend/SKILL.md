---
name: harness-extend
description: >
  Add new features to an existing harness-built project. The planner reads the existing
  spec and designs additive sprints. Includes regression testing against prior sprints.
argument-hint: "[feature description]"
---

Extend the existing project with: $ARGUMENTS

## Steps

1. Verify `harness-state/product-spec.md` exists (project must have been built already)
2. Update `harness-state/config.json` with the new feature request
3. Delegate to @"planner (agent)" in **extend mode**: read existing spec, handoff, and
   sprint plan. Design new sprints that build on the existing architecture. APPEND to
   product-spec.md and ADD sprints to sprint-plan.json.
4. Commit: `harness(plan): extend with new features`
5. Run the new sprints (same flow as /harness-sprint for each)
6. Each new sprint includes regression testing against prior sprint criteria
7. On completion, create PR with the new features
