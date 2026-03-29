#!/usr/bin/env bash
# Entry point for the meta-tests suite
# Discovers and runs all .bats files under meta-tests/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Prerequisite checks ---

if ! command -v bats &>/dev/null; then
  echo "ERROR: bats (Bash Automated Testing System) is not installed." >&2
  echo "" >&2
  echo "Install bats-core:" >&2
  echo "  macOS:   brew install bats-core" >&2
  echo "  Ubuntu:  sudo apt-get install bats" >&2
  echo "  Manual:  https://github.com/bats-core/bats-core#installation" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is not installed." >&2
  echo "" >&2
  echo "Install jq:" >&2
  echo "  macOS:   brew install jq" >&2
  echo "  Ubuntu:  sudo apt-get install jq" >&2
  echo "  Manual:  https://stedolan.github.io/jq/download/" >&2
  exit 1
fi

# --- Parse arguments ---

FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --filter)
      FILTER="$2"
      shift 2
      ;;
    --filter=*)
      FILTER="${1#--filter=}"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--filter PATTERN]" >&2
      exit 1
      ;;
  esac
done

# --- Discover .bats files ---

BATS_FILES=()
while IFS= read -r -d '' file; do
  BATS_FILES+=("$file")
done < <(find "$SCRIPT_DIR" -name '*.bats' -type f -print0 | sort -z)

if [[ ${#BATS_FILES[@]} -eq 0 ]]; then
  echo "No .bats test files found under $SCRIPT_DIR" >&2
  echo "Suite is ready but no test files exist yet." >&2
  exit 0
fi

# --- Build bats arguments ---

BATS_ARGS=()

# Detect TTY for output format
if [[ -t 1 ]]; then
  BATS_ARGS+=(--pretty)
else
  BATS_ARGS+=(--tap)
fi

# Apply filter if provided
if [[ -n "$FILTER" ]]; then
  BATS_ARGS+=(--filter "$FILTER")
fi

# --- Run tests ---

START_TIME=$(date +%s)

bats "${BATS_ARGS[@]}" "${BATS_FILES[@]}"
EXIT_CODE=$?

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

echo ""
echo "Meta-tests completed in ${DURATION}s (exit code: ${EXIT_CODE})"

exit "$EXIT_CODE"
