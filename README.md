# Claude Harness

A multi-agent harness for [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) that implements Anthropic's [Planner-Generator-Evaluator architecture](https://www.anthropic.com/engineering/harness-design-long-running-apps) for building software through structured sprint cycles.

Three agents coordinate via files and git branches to produce working software from a brief prompt:

- **Planner** expands 1-4 sentences into a comprehensive product spec with sprint decomposition
- **Generator** implements one sprint at a time against negotiated contracts
- **Evaluator** tests the running application with structural skepticism and produces actionable failure reports

The evaluator is the key insight from Anthropic's research: models can identify problems in their own work but then rationalise them away (the "self-evaluation trap"). A structurally separate evaluator, tuned for skepticism, cannot be talked out of its findings.

## Why This Exists

A solo Claude Code session can build an application in 20 minutes for $9. It will look plausible. The UI will exist. But the wiring will be broken -- a film set, all facade. The harness takes longer and costs more, but the core thing works.

| Approach | Time | Output |
|----------|------|--------|
| Solo agent | ~20 min | Looks plausible, fundamentally broken |
| With harness | 2-6 hours | Working product with tested functionality |

Every component in the harness encodes an assumption about what the model can't do on its own. As models improve, audit which components are still load-bearing. The evaluator has remained essential across every model generation tested.

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) on a **Pro or Max plan**
- `git` and `jq` installed
- `gh` CLI (optional, for PR/issue creation)
- Node.js (for Playwright MCP on web-frontend projects)

## Quick Start

### Option 1: Embed in Your Project

Copy the harness into an existing repository:

```bash
# From your project root
git clone https://github.com/jason-c-dev/claude-harness.git /tmp/claude-harness

# Copy harness files into your project
cp -r /tmp/claude-harness/harness ./harness
cp -r /tmp/claude-harness/.claude ./  # merges with existing .claude/
cp /tmp/claude-harness/.mcp.json ./   # or merge with existing
cp /tmp/claude-harness/CLAUDE.md ./CLAUDE-HARNESS.md  # avoid overwriting yours

# Add to gitignore
echo "harness-state/sprints/*/screenshots/" >> .gitignore
echo ".claude/worktrees/" >> .gitignore

# Make scripts executable
chmod +x harness/orchestrate.sh harness/lib/*.sh harness/hooks/*.sh
```

Then run the harness from your project root:

```bash
# Automated
bash harness/orchestrate.sh "Add user authentication with OAuth" \
  --project-type backend-api

# Interactive
claude --agent orchestrator
```

### Option 2: Standalone (Harness IS the Repo)

Use this repo directly as the project. The harness and the code it builds live together:

```bash
git clone https://github.com/jason-c-dev/claude-harness.git my-project
cd my-project

# Automated mode
bash harness/orchestrate.sh "Build a kanban board with drag-and-drop" \
  --project-type web-frontend

# Or interactive mode
claude
> /harness-run Build a kanban board with drag-and-drop
```

### Option 3: External Harness, Separate Target Repo

Run the harness from outside your target repo. Useful when you don't want harness files in your project:

```bash
# Clone the harness
git clone https://github.com/jason-c-dev/claude-harness.git ~/claude-harness

# From your target project
cd /path/to/my-project

# Point the harness at your project
bash ~/claude-harness/harness/orchestrate.sh "Build REST API for user management" \
  --project-type backend-api

# Or symlink the .claude/ directory for interactive mode
ln -s ~/claude-harness/.claude/agents .claude/agents
ln -s ~/claude-harness/.claude/skills .claude/skills
claude
> /harness-run Build REST API for user management
```

## Usage

### Automated Mode (Fire and Forget)

The shell script orchestrator runs the full pipeline unattended. Each agent gets a fresh context (context reset) -- no conversation history carries over between sprints, only structured files.

```bash
# Full build
bash harness/orchestrate.sh "Build a retro game maker with sprite editor and level builder" \
  --project-type web-frontend \
  --model opus \
  --max-cost 200

# With all options
bash harness/orchestrate.sh "Build a CLI tool for managing Docker containers" \
  --project-type cli-tool \
  --context-strategy reset \
  --model opus \
  --max-cost 150 \
  --from-sprint 1
```

**What happens:**

```
1. PLAN       Planner expands prompt → product-spec.md + sprint-plan.json
2. CONTRACT   Generator proposes criteria, Evaluator reviews (per sprint)
3. BUILD      Generator implements on a sprint branch
4. EVALUATE   Evaluator tests the running app, scores against contract
5. MERGE      On PASS: merge sprint branch, tag, update handoff
              On FAIL: tag for forensics, delete branch, retry (max 3)
6. REPEAT     Next sprint with fresh context + handoff.json
7. PR         Create pull request with full evaluation summary
```

### Interactive Mode (Slash Commands)

Run Claude Code in the project and use skills for fine-grained control:

```bash
claude
```

#### Initial Build

```
> /harness-plan Build a real-time collaborative whiteboard

  Planner produces product-spec.md with 8 sprints...

> /harness-sprint 1

  Contract negotiation: 22 criteria agreed...
  Generator implementing...
  Evaluator testing...
  Sprint 1 PASSED (attempt 1)

> /harness-sprint 2

  ...

> /harness-status

  Sprint | Name              | Status | Criteria | Pass | Fail | Attempts
  -------|-------------------|--------|----------|------|------|--------
  01     | Data Model        | pass   | 22       | 22   | 0    | 1
  02     | Canvas Core       | pass   | 18       | 18   | 0    | 1
  03     | Drawing Tools     | fail   | 25       | 20   | 5    | 1
  04     | Collaboration     | pending| -        | -    | -    | -
```

#### Post-Build Lifecycle

```bash
# Add features to an existing project
> /harness-extend Add version history with undo/redo and timeline scrubbing

# Fix a bug (creates GitHub issue, runs targeted fix + regression)
> /harness-fix Shapes disappear when two users draw simultaneously on the same area

# Refactor without changing behavior (full regression against ALL prior sprints)
> /harness-refactor Extract rendering into a WebGL pipeline, replace Canvas 2D calls

# Run all prior evaluations against current code
> /harness-regression

# Create PR from current state
> /harness-pr
```

#### Using the Orchestrator Agent

For a guided experience where Claude manages the full flow interactively:

```bash
claude --agent orchestrator
```

The orchestrator delegates to planner, generator, and evaluator subagents while managing git branches, merges, and tags. You can intervene between phases.

## Architecture

### Git Branching Model

Git is the coordination layer, not an afterthought.

```
main ──────────────────────────────────────────────────────>
  │
  └── harness/kanban-board                  ← harness run branch
        │
        ├── harness/kanban-board/sprint-01  ← generator worktree
        │     └── (merged on PASS, deleted)
        │
        ├── harness/kanban-board/sprint-02
        │     └── (merged on PASS, deleted)
        │
        ├── harness/kanban-board/sprint-03
        │     ├── attempt-1 (FAIL → tagged, branch deleted)
        │     └── attempt-2 (PASS → merged, branch deleted)
        │
        └── final PR → main
```

- `main` is never touched during a harness run
- Failed sprint attempts are branches that get **deleted** -- no broken code in history
- Each PASS creates a merge commit + tag (rollback point)
- One PR at the end with full evaluation summary

### Commit Convention

```
harness(sprint-03): implement drag-fill tool [C3-02]
harness(sprint-03): fix route ordering [C3-03] [eval-fix]
harness(eval): sprint-03 evaluation report (PASS)
harness(plan): product spec and sprint plan
harness(contract): sprint-03 contract agreed (27 criteria)
```

### Tags

```
harness/plan                        ← after planning phase
harness/sprint-01/pass              ← sprint milestone (rollback point)
harness/sprint-03/attempt-1         ← forensics for failed attempt
harness/v1.0                        ← full harness run complete
```

### File Communication Protocol

Agents never share conversation context. They communicate exclusively through files:

```
harness-state/
  config.json           ← project settings (prompt, type, cost caps)
  product-spec.md       ← planner output
  sprint-plan.json      ← sprint decomposition
  handoff.json          ← structured state for context resets
  progress.md           ← narrative log with git commit links
  cost-log.json         ← token/cost tracking
  regression/
    registry.json       ← blocking criteria from all passed sprints
  sprints/
    sprint-01/
      contract.json     ← agreed criteria (15-30 testable items)
      generator-log.md  ← what was built and why
      eval-report.json  ← pass/fail per criterion + scores
      status.json       ← pending|active|ready-for-eval|pass|fail
      git-meta.json     ← branch, merge SHA, tag
```

### Context Resets

Each agent invocation starts with a **fresh context window**. The only state that carries over is in files:

```
Sprint 1 Generator → writes code + generator-log.md
                   → context discarded

Sprint 2 Generator → reads handoff.json (what was built)
                   → reads progress.md (what happened)
                   → reads contract.json (what to build)
                   → fresh context, no memory of Sprint 1's conversation
```

This prevents context anxiety (the model rushing as its context fills) and ensures each sprint gets the model's full attention.

## Project Types

The evaluation criteria adapt to the project type specified in `config.json`:

### `web-frontend`

Uses Playwright MCP for browser interaction and screenshots.

| Criterion | Weight | Threshold |
|-----------|--------|-----------|
| Design Quality | 30% | 6/10 |
| Originality | 25% | 5/10 |
| Craft | 20% | 7/10 |
| Functionality | 25% | 7/10 |

### `backend-api`

Uses curl/httpie via Bash for API testing.

| Criterion | Weight | Threshold |
|-----------|--------|-----------|
| API Correctness | 35% | 7/10 |
| Architecture | 25% | 6/10 |
| Robustness | 20% | 7/10 |
| Performance | 20% | 5/10 |

### `cli-tool`

Uses direct command execution and output comparison.

| Criterion | Weight | Threshold |
|-----------|--------|-----------|
| Correctness | 35% | 7/10 |
| UX | 25% | 6/10 |
| Robustness | 20% | 7/10 |
| Architecture | 20% | 5/10 |

### `general`

Uses Bash commands and file inspection.

| Criterion | Weight | Threshold |
|-----------|--------|-----------|
| Correctness | 35% | 7/10 |
| Quality | 25% | 6/10 |
| Completeness | 20% | 7/10 |
| Robustness | 20% | 5/10 |

## Sprint Contracts

Before implementation begins, the Generator and Evaluator negotiate a **contract**: an explicit agreement on what "done" looks like, with testable criteria.

```json
{
  "sprintNumber": 3,
  "sprintName": "Drag & Drop",
  "criteria": [
    {
      "id": "C3-01",
      "category": "interaction",
      "description": "Drag-to-fill places tiles in the entire dragged region",
      "testMethod": "interaction",
      "testSteps": "Select fill tool. Click-drag a 3x3 area. Verify all 9 tiles filled.",
      "threshold": "pass/fail"
    }
  ],
  "outOfScope": ["Undo/redo", "Multi-layer support"],
  "regressionSprints": [1, 2]
}
```

The evaluator's failure reports are specific enough to act on without investigation:

```
FAIL — C3-02: fillRectangle function exists at editor.js:142 but is not
triggered on mouseUp. The handler at editor.js:87 calls placeTile()
instead of fillRectangle().
```

Not:

```
FAIL — C3-02: The fill tool doesn't work perfectly.
```

## Regression Testing

Every sprint that passes has its blocking criteria added to the regression registry. Future sprints automatically re-test these criteria to catch regressions.

| Mode | Regression Scope |
|------|-----------------|
| `/harness-run` | None (initial build) |
| `/harness-sprint N` | Prior sprints listed in contract |
| `/harness-extend` | All prior sprints |
| `/harness-fix` | Related sprints |
| `/harness-refactor` | ALL sprints (full sweep) |
| `/harness-regression` | ALL sprints (explicit) |

A regression failure is always blocking. New code must not break old functionality.

## Cost Control

On Pro/Max plans, you don't pay per-token, but the harness tracks invocations for monitoring:

```bash
# Set cost caps (heuristic on Pro/Max, enforced on API)
bash harness/orchestrate.sh "..." --max-cost 200

# Check current spend
> /harness-status
```

Configuration in `harness-state/config.json`:
```json
{
  "costCapPerSprint": 25.00,
  "totalCostCap": 200.00
}
```

Typical costs (from Anthropic's benchmarks on API pricing):
- Planner: ~$1, ~5 minutes
- Generator per sprint: $20-70, 30-120 minutes
- Evaluator per sprint: $3-5, ~10 minutes
- Full project (5-10 sprints): $100-200, 2-6 hours

## Lifecycle Examples

### Example 1: Build a Kanban Board from Scratch

```bash
bash harness/orchestrate.sh "Build a kanban board with drag-and-drop columns, \
  card creation/editing, and label filtering" \
  --project-type web-frontend \
  --max-cost 200
```

The planner produces a 5-sprint plan:
1. Data Model & Board Shell
2. Card Management
3. Drag & Drop
4. Filtering & Search
5. Polish & Animations

Each sprint goes through contract negotiation, implementation, and evaluation. Failed sprints retry up to 3 times. A PR is created at the end.

### Example 2: Add Features to an Existing Project

```bash
# Two weeks later...
bash harness/orchestrate.sh --extend "Add real-time collaboration: \
  multiple users see each other's cursors, changes sync instantly, \
  presence indicators show who's viewing each board"
```

The planner reads the existing spec and designs 3 additive sprints. Each sprint includes regression testing against all 5 prior sprints.

### Example 3: Fix a Bug

```bash
bash harness/orchestrate.sh --fix "Cards vanish when dragged rapidly \
  between columns. The card DOM element is removed from the source column \
  before the drop handler fires in the target column."
```

Creates a GitHub issue, generates a surgical fix contract, implements the fix, and runs regression against the Drag & Drop sprint.

### Example 4: Refactor with Confidence

```bash
bash harness/orchestrate.sh --refactor "Extract all board state into a \
  Zustand store. Currently scattered across 6 useState hooks in App.tsx \
  with 4 levels of prop drilling."
```

Runs a pre-refactor regression baseline, implements the refactor, then runs a **full** regression against every prior sprint's criteria.

### Example 5: Interactive Sprint-by-Sprint

```bash
claude

> /harness-plan Build a markdown-based knowledge base with full-text search

  # Review the spec...
  # The planner proposed 7 sprints. Sprint 4 looks too ambitious.
  # Edit harness-state/sprint-plan.json to split it.

> /harness-sprint 1
  Sprint 1 PASSED (attempt 1, 18/18 criteria)

> /harness-sprint 2
  Sprint 2 FAILED (attempt 1)
  Blocking: C2-03 — search index not updated on document edit
  Retry? yes

  Sprint 2 PASSED (attempt 2, 22/22 criteria)

> /harness-status
  # Review progress...

> /harness-sprint 3
  ...
```

### Example 6: Embed in CI/CD

Use the harness in a GitHub Action to auto-build from issues:

```yaml
name: Harness Build
on:
  issues:
    types: [labeled]
jobs:
  build:
    if: contains(github.event.label.name, 'harness-build')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: anthropics/claude-code-action@v1
        with:
          prompt: |
            Run the harness for this issue:
            ${{ github.event.issue.title }}
            ${{ github.event.issue.body }}
```

## Directory Structure

```
your-project/
  CLAUDE.md                              # Project instructions
  .mcp.json                              # Playwright MCP config
  .claude/
    agents/
      planner.md                         # Planner agent definition
      generator.md                       # Generator agent definition
      evaluator.md                       # Evaluator agent definition
      orchestrator.md                    # Interactive orchestrator
    skills/
      harness-plan/SKILL.md              # /harness-plan
      harness-sprint/SKILL.md            # /harness-sprint N
      harness-eval/SKILL.md              # /harness-eval N
      harness-run/SKILL.md               # /harness-run
      harness-extend/SKILL.md            # /harness-extend
      harness-fix/SKILL.md               # /harness-fix
      harness-refactor/SKILL.md          # /harness-refactor
      harness-regression/SKILL.md        # /harness-regression
      harness-status/SKILL.md            # /harness-status
      harness-pr/SKILL.md                # /harness-pr
    settings.json                        # Hooks config

  harness/
    orchestrate.sh                       # Shell script orchestrator
    lib/
      utils.sh                           # Logging, cost tracking, helpers
      git.sh                             # Branch, merge, tag, PR operations
      planner.sh                         # Planner invocation
      generator.sh                       # Generator invocation
      evaluator.sh                       # Evaluator invocation
      contract.sh                        # Contract negotiation
    hooks/
      on-generator-stop.sh               # Verify generator outputs
      on-evaluator-stop.sh               # Verify eval report validity
      on-stop.sh                         # Prevent premature session end
    prompts/
      planner-system.md                  # Full planner system prompt
      generator-system.md                # Full generator system prompt
      evaluator-system.md                # Full evaluator system prompt
    templates/
      config.json                        # Default config
      sprint-contract.json               # Contract template
      eval-report.json                   # Report template
      pr-body.md                         # PR description template

  harness-state/                         # Runtime state (created during runs)
    config.json
    product-spec.md
    sprint-plan.json
    handoff.json
    progress.md
    cost-log.json
    regression/
      registry.json
    sprints/
      sprint-01/
        contract.json
        generator-log.md
        eval-report.json
        status.json
```

## The Expiry Date Principle

> "Every component in a harness encodes an assumption about what the model can't do on its own."
> — Anthropic, Harness Design for Long-Running Application Development

| Component | Assumption | How to test |
|-----------|-----------|-------------|
| Sprint decomposition | Can't maintain coherence over long builds | Let generator build multiple sprints without reset |
| Context resets | Panics as context fills | Use compaction instead, compare quality |
| Contract negotiation | Under-scopes without explicit agreement | Skip contracts, let generator self-scope |
| **Separate evaluator** | Can't honestly self-assess | Let generator self-evaluate, compare results |

Anthropic found the **evaluator remains load-bearing even with their most capable model**. The self-evaluation trap persists across model generations. Sprint decomposition and context resets may become optional as models improve. Audit periodically.

## Configuration Reference

### `harness-state/config.json`

```json
{
  "userPrompt": "Build a ...",
  "projectType": "general",
  "contextStrategy": "reset",
  "model": "opus",
  "maxSprintAttempts": 3,
  "maxContractRounds": 3,
  "costCapPerSprint": 25.00,
  "totalCostCap": 200.00
}
```

| Field | Values | Description |
|-------|--------|-------------|
| `projectType` | `web-frontend`, `backend-api`, `cli-tool`, `general` | Controls evaluation criteria and testing tools |
| `contextStrategy` | `reset`, `compact` | `reset` = fresh instance per sprint (recommended). `compact` = reuse session with `/compact` |
| `model` | `opus`, `sonnet` | Model for agent invocations |
| `maxSprintAttempts` | 1-5 | Retries per sprint on evaluation failure |
| `maxContractRounds` | 1-5 | Negotiation rounds for contracts |

### `orchestrate.sh` Flags

```
bash harness/orchestrate.sh [PROMPT] [OPTIONS]

Modes:
  [PROMPT]              New build from prompt
  --extend PROMPT       Add features to existing project
  --fix DESCRIPTION     Fix a specific bug
  --refactor DESC       Restructure without behavior change
  --resume              Resume interrupted run
  --regression          Run all prior evaluations

Options:
  --project-type TYPE   web-frontend|backend-api|cli-tool|general
  --context-strategy S  reset|compact
  --model MODEL         opus|sonnet
  --max-cost DOLLARS    Total cost cap
  --from-sprint N       Start from sprint N
  --dry-run             Show plan without executing
```

## Credits

Based on Anthropic's research: [Harness Design for Long-Running Application Development](https://www.anthropic.com/engineering/harness-design-long-running-apps) by Prithvi Rajasekaran and team.

Inspired by Jason Croucher's [practitioner analysis](https://medium.com/@jason.croucher) of applying these patterns to real-world agent systems.

## License

MIT
