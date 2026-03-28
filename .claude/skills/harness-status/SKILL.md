---
name: harness-status
description: >
  Show the current state of the harness: which sprints are done, in progress, or pending.
  Displays progress table, blocking issues, cost, and git state.
allowed-tools: Read, Glob, Bash
---

Show the harness status by reading harness-state files:

1. Read `harness-state/sprint-plan.json` for the full plan
2. Read `harness-state/progress.md` for the narrative log
3. For each sprint directory in `harness-state/sprints/`:
   - Read `status.json` for current status
   - If `eval-report.json` exists, get pass/fail counts and scores
   - If `git-meta.json` exists, get branch/tag info
4. Read `harness-state/cost-log.json` for spend tracking
5. Read `harness-state/handoff.json` for current git state

Display a formatted table:

```
Sprint | Name              | Status | Criteria | Pass | Fail | Attempts | Tag
-------|-------------------|--------|----------|------|------|----------|----
01     | Data Model        | pass   | 23       | 23   | 0    | 1        | harness/sprint-01/pass
02     | Card Management   | pass   | 19       | 19   | 0    | 1        | harness/sprint-02/pass
03     | Drag & Drop       | pass   | 25       | 25   | 0    | 2        | harness/sprint-03/pass
04     | Real-time         | active | 21       | -    | -    | 1        | -
05     | Power Features    | pending| -        | -    | -    | -        | -
```

Also show:
- Current git branch and latest tag
- Any blocking issues from the most recent failed sprint
- Total invocation count from cost-log.json
