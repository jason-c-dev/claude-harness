#!/usr/bin/env bash
# Run the harness test suite
#
# Usage:
#   bash tests/run-all.sh              # Layer 1 only (default, fast, free)
#   bash tests/run-all.sh layer1       # Layer 1 explicitly
#   bash tests/run-all.sh layer2       # Layer 2 smoke test (real Claude, costs usage)
#   bash tests/run-all.sh layer3       # Layer 3 meta test (real Claude, costs more)
#   bash tests/run-all.sh all          # All three layers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LAYER="${1:-layer1}"

# Check for bats
if ! command -v bats &>/dev/null; then
  echo "bats-core not found."
  echo "Install with:"
  echo "  brew install bats-core"
  echo "  npm install -g bats"
  exit 1
fi

# Check for jq
if ! command -v jq &>/dev/null; then
  echo "jq not found. Install with: brew install jq"
  exit 1
fi

run_layer1() {
  echo "=== Layer 1: Unit & Integration Tests (mocked Claude) ==="
  echo ""
  bats "$SCRIPT_DIR/layer1/"*.bats
}

run_layer2() {
  echo "=== Layer 2: Smoke Test (Real Claude) ==="
  echo ""
  if [[ "${HARNESS_SMOKE_TEST:-}" != "1" ]]; then
    echo "Skipped. Set HARNESS_SMOKE_TEST=1 to run (costs Claude usage)."
    return 0
  fi
  bash "$SCRIPT_DIR/layer2/smoke-test.sh"
}

run_layer3() {
  echo "=== Layer 3: Meta Test (Self-Referential) ==="
  echo ""
  if [[ "${HARNESS_META_TEST:-}" != "1" ]]; then
    echo "Skipped. Set HARNESS_META_TEST=1 to run (costs significant Claude usage)."
    return 0
  fi
  bash "$SCRIPT_DIR/layer3/meta-test.sh"
}

case "$LAYER" in
  layer1|--layer1-only)
    run_layer1
    ;;
  layer2)
    run_layer2
    ;;
  layer3)
    run_layer3
    ;;
  all)
    run_layer1
    echo ""
    run_layer2
    echo ""
    run_layer3
    ;;
  *)
    echo "Unknown layer: $LAYER"
    echo "Usage: bash tests/run-all.sh [layer1|layer2|layer3|all]"
    exit 1
    ;;
esac

echo ""
echo "=== COMPLETE ==="
