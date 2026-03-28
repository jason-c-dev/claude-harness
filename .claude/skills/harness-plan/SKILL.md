---
name: harness-plan
description: >
  Generate a product specification and sprint plan from a brief prompt using the Planner
  agent. Use when starting a new project or reviewing what the planner would produce.
argument-hint: "[project description]"
context: fork
agent: planner
---

Initialize `harness-state/config.json` with:
- `userPrompt`: $ARGUMENTS
- `projectType`: Ask the user or infer from the prompt

Then follow your system prompt to produce:
- `harness-state/product-spec.md` -- full product specification
- `harness-state/sprint-plan.json` -- sprint decomposition

Be ambitious. The development system can handle complexity.
