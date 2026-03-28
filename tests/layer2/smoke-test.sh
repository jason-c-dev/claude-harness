#!/usr/bin/env bash
# Layer 2: Smoke test with real Claude
# Builds a trivial project to verify end-to-end harness functionality.
#
# Guard: Set HARNESS_SMOKE_TEST=1 to run (costs Claude usage ~$10-20)
# Timeout: 30 minutes

set -euo pipefail

if [[ "${HARNESS_SMOKE_TEST:-}" != "1" ]]; then
  echo "Set HARNESS_SMOKE_TEST=1 to run the smoke test."
  exit 0
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SMOKE_DIR="$(mktemp -d)"
trap "echo 'Smoke test dir: $SMOKE_DIR (not cleaned for inspection)'" EXIT

echo "=== Smoke Test: Build a Hello World CLI ==="
echo "Working directory: $SMOKE_DIR"
echo ""

# Set up isolated project
cd "$SMOKE_DIR"
git init -q
git config user.email "test@test.com"
git config user.name "Smoke Test"
echo "# Smoke Test" > README.md
git add README.md
git commit -q -m "initial"

# Copy harness
cp -r "$PROJECT_DIR/harness" ./harness
cp -r "$PROJECT_DIR/.claude" ./.claude
cp "$PROJECT_DIR/.mcp.json" ./.mcp.json 2>/dev/null || true
cp "$PROJECT_DIR/CLAUDE.md" ./CLAUDE.md
chmod +x harness/orchestrate.sh harness/lib/*.sh harness/hooks/*.sh

# Run the harness
echo "Starting harness (this may take 10-30 minutes)..."
START_TIME=$(date +%s)

# Use gtimeout on macOS, timeout on Linux
TIMEOUT_CMD=$(command -v gtimeout || command -v timeout || echo "")
${TIMEOUT_CMD:+$TIMEOUT_CMD 1800} bash harness/orchestrate.sh \
  "Build a hello world CLI tool in bash that prints 'Hello, NAME' when given a name argument and 'Hello, World' with no arguments" \
  --project-type cli-tool \
  --max-cost 50 \
  2>&1 | tee smoke-output.log || true

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
echo ""
echo "Elapsed: $(( ELAPSED / 60 ))m $(( ELAPSED % 60 ))s"

# Assertions
echo ""
echo "=== Assertions ==="
PASS=0
FAIL=0

assert() {
  local desc="$1"
  shift
  if "$@" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $desc"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert "product-spec.md exists and is >100 bytes" \
  test -f harness-state/product-spec.md -a "$(wc -c < harness-state/product-spec.md)" -gt 100

assert "sprint-plan.json is valid JSON with sprints" \
  jq -e '.sprints | length > 0' harness-state/sprint-plan.json

assert "At least one eval report exists" \
  test -n "$(find harness-state/sprints -name 'eval-report.json' 2>/dev/null | head -1)"

assert "At least one sprint PASS in eval reports" \
  bash -c "jq -r '.overallResult' harness-state/sprints/*/eval-report.json 2>/dev/null | grep -q PASS"

assert "Harness git tag exists" \
  bash -c "git tag | grep -q 'harness/'"

assert "Harness branch exists" \
  bash -c "git branch | grep -q 'harness/'"

assert "handoff.json has completedSprints" \
  jq -e '.completedSprints | length > 0' harness-state/handoff.json

assert "cost-log.json has invocations" \
  jq -e '.invocations | length >= 3' harness-state/cost-log.json

assert "progress.md contains PASS" \
  grep -q "PASS" harness-state/progress.md

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [[ "$FAIL" -gt 0 ]]; then
  echo "Smoke test output saved to: $SMOKE_DIR/smoke-output.log"
  exit 1
fi
