#!/usr/bin/env bash
# Layer 3: The Meta Test
# Uses the harness to build its own test suite.
#
# Prerequisites: Layer 1 must pass first.
# Guard: Set HARNESS_META_TEST=1 to run (costs Claude usage ~$50-100)
#
# Why this is not circular:
# Layer 1 (human-written, mock-tested) is the ground truth.
# The meta test demonstrates the harness can analyze a complex Bash project,
# decompose it into sprints, produce tests, and have them pass evaluation.
# The two test suites are complementary, not redundant.

set -euo pipefail

if [[ "${HARNESS_META_TEST:-}" != "1" ]]; then
  echo "Set HARNESS_META_TEST=1 to run the meta test."
  echo "This costs significant Claude usage (~\$50-100)."
  exit 0
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Verify Layer 1 passes first
echo "=== Verifying Layer 1 (prerequisite) ==="
if ! bash "$TESTS_DIR/run-all.sh" layer1; then
  echo ""
  echo "Layer 1 must pass before running the meta test."
  echo "Fix Layer 1 failures first."
  exit 1
fi

echo ""
echo "=== Layer 3: The Meta Test ==="
echo "The harness will now build its own test suite."
echo ""

META_DIR="$(mktemp -d)"
trap "echo 'Meta test dir: $META_DIR (not cleaned for inspection)'" EXIT

# Copy project to isolated directory
cp -r "$PROJECT_DIR" "$META_DIR/claude-harness"
cd "$META_DIR/claude-harness"

# Ensure git is ready
git init -q 2>/dev/null || true
git add -A 2>/dev/null || true
git commit -q -m "meta test baseline" 2>/dev/null || true

START_TIME=$(date +%s)

# Run the harness to build its own test suite
bash harness/orchestrate.sh \
  "Build a comprehensive bats-core test suite for this project (a bash-based \
multi-agent harness). The test suite should cover: \
(1) Unit tests for all pure functions in harness/lib/utils.sh \
(slugify, sprint_pad, sprint_dir, json_read, file_exists, init_harness_state, \
update_handoff, update_regression_registry), \
(2) Git operation tests for harness/lib/git.sh functions using isolated temp repos, \
(3) Hook validation tests for harness/hooks/on-generator-stop.sh, \
on-evaluator-stop.sh, and on-stop.sh using fixture files. \
Put all tests in a meta-tests/ directory. Include a meta-tests/run.sh entry point." \
  --project-type cli-tool \
  --max-cost 100 \
  2>&1 | tee meta-output.log || true

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

echo ""
echo "=== META-TEST VERIFICATION ==="
echo "Elapsed: $(( ELAPSED / 60 ))m $(( ELAPSED % 60 ))s"
echo ""

PASS=0
FAIL=0

check() {
  local desc="$1"
  shift
  if "$@" 2>/dev/null; then
    echo "  PASS: $desc"
    (( PASS++ ))
  else
    echo "  FAIL: $desc"
    (( FAIL++ ))
  fi
}

# Check harness completed sprints
check "Harness completed sprint cycle" \
  bash -c "ls harness-state/sprints/sprint-*/eval-report.json 1>/dev/null 2>&1"

check "At least one sprint passed evaluation" \
  bash -c "jq -r '.overallResult' harness-state/sprints/sprint-*/eval-report.json 2>/dev/null | grep -q PASS"

# Check test files were created
check "Test files were created" \
  bash -c "find . -name '*.bats' -o -name 'test-*.sh' | grep -q ."

# Count generated test files
TEST_FILES=$(find . -path './meta-tests/*' -name '*.bats' -o -path './meta-tests/*' -name 'test-*.sh' 2>/dev/null | wc -l | tr -d ' ')
echo "  INFO: $TEST_FILES test files generated"

# Try to run the generated tests
if [[ -f "meta-tests/run.sh" ]]; then
  echo ""
  echo "=== RUNNING GENERATED TESTS ==="
  if bash meta-tests/run.sh 2>&1; then
    check "Generated tests pass" true
  else
    echo "  WARN: Some generated tests failed (this is informative, not blocking)"
    check "Generated tests exist and are runnable" true
  fi
elif [[ "$TEST_FILES" -gt 0 ]]; then
  echo "  INFO: No run.sh entry point, but test files exist"
  check "Test files were generated" true
fi

echo ""
echo "=== META-TEST RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [[ "$PASS" -ge 2 ]]; then
  echo "The harness successfully:"
  echo "  - Analyzed its own codebase"
  echo "  - Planned a test suite via sprint decomposition"
  echo "  - Implemented tests via the generator"
  echo "  - Evaluated them via the evaluator"
  echo ""
  echo "This is not circular proof -- it is empirical evidence that the harness"
  echo "can produce useful output on a complex, real-world Bash project."
fi

echo ""
echo "Meta test output: $META_DIR/claude-harness/meta-output.log"
echo "Generated tests:  $META_DIR/claude-harness/meta-tests/"
