# Claude Harness

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Tests](https://github.com/jason-c-dev/claude-harness/actions/workflows/tests.yml/badge.svg)](https://github.com/jason-c-dev/claude-harness/actions/workflows/tests.yml)
[![Claude Code](https://img.shields.io/badge/Claude_Code-compatible-blue.svg)](https://docs.anthropic.com/en/docs/claude-code)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/jason-c-dev/claude-harness/pulls)

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

## Execution Modes: Script vs Interactive vs Hybrid

The harness can run in three modes. The right choice depends on project size, how much oversight you want, and how much time you have.

### How They Work Under the Hood

**Script mode** (`orchestrate.sh`) spawns a separate `claude -p` process for every agent call. Each process cold-starts, loads the system prompt and agent definition, does its work, exits. State passes between invocations entirely through files (`handoff.json`, contracts, eval reports).

```
orchestrate.sh
  ├─ claude -p (planner)        → cold start → work → exit
  ├─ claude -p (gen: contract)  → cold start → work → exit
  ├─ claude -p (eval: review)   → cold start → work → exit
  ├─ claude -p (generator)      → cold start → work → exit
  ├─ claude -p (evaluator)      → cold start → work → exit
  └─ ... repeat for each sprint
```

**Interactive mode** (`claude --agent orchestrator`) runs one persistent session. The orchestrator delegates to planner, generator, and evaluator as subagents that spawn within the same session. No cold starts -- subagents inherit the warm connection.

```
claude --agent orchestrator (one session, stays warm)
  ├─ @planner         → subagent, fast spawn
  ├─ @generator       → subagent, fast spawn
  ├─ @evaluator       → subagent, fast spawn
  ├─ @generator       → subagent (sprint 2)
  └─ @evaluator       → subagent (sprint 2)
```

**Hybrid**: Use interactive mode for planning and early sprints (fast feedback, you can correct course), then switch to script mode for the bulk build.

### Tradeoff Comparison

| Factor | Script (`orchestrate.sh`) | Interactive (`--agent orchestrator`) |
|--------|--------------------------|--------------------------------------|
| **Speed** | Slow. Each `claude -p` cold-starts (~1-3 min overhead per call). A 3-sprint hello-world took 39 min with ~13 calls. | Fast. Subagents spawn within the warm session. Same project would take ~10-15 min. |
| **Context isolation** | Perfect. Each call starts with a completely fresh context. No bleed between sprints. This is the paper's recommendation. | Degrades. The orchestrator's context grows as subagent results accumulate. After 5-8 sprints, context pressure builds. |
| **Context anxiety** | Eliminated. Fresh context every time. | Risk increases with sprint count. The model may rush later sprints. |
| **Unattended** | Yes. Fire and forget. Run overnight. | No. You're at the terminal. But you can intervene, which is sometimes what you want. |
| **Retry logic** | Deterministic. Shell script controls max attempts, round limits. | Orchestrator agent decides. Generally reliable but less predictable. |
| **Real-time visibility** | Claude's stderr streams to your terminal (tool calls, file edits, thinking). | Native. You see everything as it happens. |
| **Max project size** | Unlimited sprints. Context resets mean no degradation. | ~5-8 sprints before context pressure. Viable for small-to-medium projects. |
| **Permissions** | Uses `--dangerously-skip-permissions`. Safety comes from git isolation (sprint branches, merge-on-pass, PR review). | Uses `permissionMode: acceptEdits`. File operations auto-approved, Bash commands prompt you. |
| **Course correction** | Stop the script, edit files, resume with `--from-sprint N`. | Intervene between any phase. Tell the orchestrator to adjust scope, skip a sprint, add guidance. |
| **Cost tracking** | Per-invocation logging in `cost-log.json`. | Session-level only (`/cost`). |

### When to Use What

**Script mode** for:
- Large projects (5+ sprints)
- Overnight/unattended builds
- CI/CD pipelines
- When you trust the plan and just want results

**Interactive mode** for:
- Small projects (1-3 sprints)
- First-time exploration of a new project type
- When you want to review the plan before committing to a full build
- Debugging a specific sprint that keeps failing
- When you want to add context the agents don't have ("use Bun not npm", "the database is Postgres not SQLite")

**Hybrid** (recommended for most projects):
1. Start interactive: `/harness-plan Build a ...` -- review the spec, adjust sprint scope
2. Run first sprint interactive: `/harness-sprint 1` -- verify the harness understands your project
3. Switch to script for the rest: `bash harness/orchestrate.sh --resume --from-sprint 2`

### Why Script Mode Is Slow (and Why That's OK)

A 3-sprint project makes roughly 13 `claude -p` calls:
- 1 planner
- 3 contract proposals (generator)
- 3 contract reviews (evaluator)
- 3 implementations (generator)
- 3 evaluations (evaluator)

Each cold start takes 1-3 minutes even for trivial work. That's 13-39 minutes of overhead on top of actual work time.

For a hello-world CLI, this overhead dominates -- you spend 39 minutes building something you could write in 5 minutes. But for a real project (kanban board, game engine, DAW), the overhead is amortised. A 6-hour build with 30 agent calls spends maybe 45 minutes on cold starts -- acceptable.

The paper's architecture accepts this tradeoff deliberately: **context resets prevent quality degradation in later sprints**, which matters more than speed for complex builds.

## Usage

### Automated Mode (Fire and Forget)

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

Claude's progress (tool calls, file edits, reasoning) streams to stderr in real-time so you can watch what each agent is doing.

### Interactive Mode (Slash Commands)

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

#### Hybrid Workflow (Recommended)

Start interactive for planning and first-sprint validation, then switch to script for the bulk build:

```bash
# 1. Plan interactively -- review and adjust
claude
> /harness-plan Build a markdown knowledge base with full-text search
# Review product-spec.md, edit sprint-plan.json if needed

# 2. First sprint interactive -- verify the harness understands your project
> /harness-sprint 1
# Watch it work, provide guidance if needed

# 3. Switch to script for the rest -- fire and forget
# Exit claude, then:
bash harness/orchestrate.sh --resume --from-sprint 2
```

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

## Testing

The harness has a three-layer test suite. The `tests/` directory is for harness development only -- it is NOT copied when embedding the harness in a target project.

```bash
# Layer 1: Unit & integration tests with mock Claude (fast, free, ~10 seconds)
bash tests/run-all.sh

# Layer 2: Smoke test with real Claude (~30-40 min, uses Pro/Max plan)
HARNESS_SMOKE_TEST=1 bash tests/run-all.sh layer2

# Layer 3: Meta test -- harness builds its own test suite (~1-2 hours)
HARNESS_META_TEST=1 bash tests/run-all.sh layer3

# All layers
HARNESS_SMOKE_TEST=1 HARNESS_META_TEST=1 bash tests/run-all.sh all

# Or from within Claude Code
> /harness-test
> /harness-test layer2
```

### Layer 1: Mechanical (74 tests)

Tests the harness plumbing with a mock `claude` script that writes fixture files instead of calling the API. Covers pure functions (`slugify`, `sprint_pad`, `json_read`), file system operations (`init_harness_state`, `update_handoff`, `update_regression_registry`), git operations in temp repos (branch, merge, tag, fail-attempt cleanup), hook validation, and the full pipeline flow with mocked agent calls.

### Layer 2: Smoke Test

Runs the real harness on a trivial project ("Build a hello world CLI tool") to prove the end-to-end pipeline works with actual Claude. Verifies: product spec created, sprint plan valid, eval reports exist with PASS results, git tags created, handoff populated, cost log has invocations.

### Layer 3: Meta Test (Self-Referential)

Uses the harness to build its own test suite. The planner analyzes the harness codebase, the generator writes bats tests, the evaluator verifies they pass. This is not circular proof -- Layer 1 (human-written) is the ground truth. The meta test demonstrates the harness can produce useful output on a complex, real-world Bash project. If the meta-generated tests catch a bug Layer 1 missed, that's genuine value.

## Credits

Based on Anthropic's research: [Harness Design for Long-Running Application Development](https://www.anthropic.com/engineering/harness-design-long-running-apps) by Prithvi Rajasekaran and team.

Inspired by Jason Croucher's [practitioner analysis](https://medium.com/@jason.croucher) of applying these patterns to real-world agent systems.

## License

MIT
