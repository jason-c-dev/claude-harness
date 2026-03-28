---
name: harness-test
description: >
  Run the harness test suite. Layer 1 (fast, free) runs unit and integration tests
  with mocked Claude. Layer 2 runs a real-Claude smoke test. Layer 3 is the meta
  self-test where the harness builds its own test suite.
argument-hint: "[layer1|layer2|layer3|all]"
allowed-tools: Read, Bash, Glob, Grep
---

Run the harness test suite: `bash tests/run-all.sh $ARGUMENTS`

## Layers

- **layer1** (default): Unit and integration tests with mocked Claude. Fast, free.
  Tests pure functions, git operations, hooks, and the full pipeline with fixtures.
- **layer2**: Smoke test with real Claude (~$10-20). Builds a trivial project
  end-to-end. Requires `HARNESS_SMOKE_TEST=1`.
- **layer3**: Meta test (~$50-100). The harness builds its own test suite.
  Requires `HARNESS_META_TEST=1` and Layer 1 to pass first.
- **all**: Run all three layers sequentially.

## Prerequisites

- `bats-core`: Install with `brew install bats-core` or `npm install -g bats`
- `jq`: Install with `brew install jq`

Report results to the user. If tests fail, read the failing test to understand
what went wrong and suggest fixes.
