# Planner-Generator-Evaluator Harness

This project implements a multi-agent harness for Claude Code CLI, based on Anthropic's
"Harness Design for Long-Running Application Development" research.

## Architecture

Three agents coordinate via files and git branches:

- **Planner**: Expands brief prompts into product specs and sprint plans
- **Generator**: Implements one sprint at a time against negotiated contracts
- **Evaluator**: Tests implementations with skepticism, produces actionable failure reports

## Modes

- **Automated**: `bash harness/orchestrate.sh "Build a ..."` -- fire and forget
- **Interactive**: Use `/harness-run`, `/harness-sprint N`, etc. from within Claude Code

## Key Principles

- Git is the coordination layer: branches isolate sprints, tags mark rollback points, PRs are the review surface
- Context resets between sprints: each agent invocation starts fresh, reads state from files
- The evaluator is structurally separate and cannot rationalize away its own findings
- Every harness component encodes an assumption about model limitations -- audit when models change

## File Protocol

Agents communicate exclusively through files in `harness-state/`:
- `config.json` -- project configuration
- `product-spec.md` -- planner output
- `sprint-plan.json` -- sprint decomposition
- `handoff.json` -- structured state for context resets
- `progress.md` -- narrative log with git links
- `sprints/sprint-NN/` -- per-sprint contracts, logs, and eval reports

## Commit Convention

```
harness(sprint-NN): description [C-ID]
harness(eval): sprint-NN result
harness(plan): product spec and sprint plan
harness(contract): sprint-NN agreed
```

## Cost Control

- Configure caps in `harness-state/config.json`: `costCapPerSprint` and `totalCostCap`
- Track spend in `harness-state/cost-log.json`
- Use `--max-cost` flag with orchestrate.sh
