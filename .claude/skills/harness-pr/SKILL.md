---
name: harness-pr
description: >
  Create a pull request from the current harness branch to main. Generates a structured
  PR body with sprint results, evaluation scores, and cost summary.
allowed-tools: Read, Glob, Bash
---

Create a PR from the harness branch:

1. Read `harness-state/handoff.json` for the harness branch name
2. Read `harness-state/sprint-plan.json` for sprint names
3. For each sprint, read `eval-report.json` for results and scores
4. Read `harness-state/cost-log.json` for cost summary
5. Read `harness-state/config.json` for configuration

Generate a structured PR body with:
- Summary of what was built
- Sprint results table (name, status, criteria pass/fail, attempts, cost)
- Evaluation scores per sprint
- Total cost
- Configuration used
- Link to Anthropic's harness design paper

Push the branch and create the PR:
```bash
git push -u origin <harness-branch>
gh pr create --base main --head <harness-branch> --title "harness: <project>" --body "$body"
```

Report the PR URL back to the user.
