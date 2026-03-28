#!/usr/bin/env bats

load '../helpers/test-helper'

HOOKS_DIR=""

setup() {
  # Call parent setup
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR
  cd "$TEST_TEMP_DIR"
  export HARNESS_STATE="harness-state"
  mkdir -p "$HARNESS_STATE/sprints" "$HARNESS_STATE/regression"

  HOOKS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/harness/hooks"
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

# === on-generator-stop.sh ===

@test "on-generator-stop: allows when status is ready-for-eval with log" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  echo '{"status":"ready-for-eval","attempt":1}' > "$HARNESS_STATE/sprints/sprint-01/status.json"
  echo "# Log" > "$HARNESS_STATE/sprints/sprint-01/generator-log.md"

  run echo "" | bash "$HOOKS_DIR/on-generator-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-generator-stop: blocks when ready-for-eval but log missing" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  echo '{"status":"ready-for-eval","attempt":1}' > "$HARNESS_STATE/sprints/sprint-01/status.json"

  run bash -c "echo '' | bash '$HOOKS_DIR/on-generator-stop.sh'"
  [[ "$status" -eq 2 ]]
}

@test "on-generator-stop: allows when status is blocked" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  echo '{"status":"blocked","attempt":1}' > "$HARNESS_STATE/sprints/sprint-01/status.json"

  run echo "" | bash "$HOOKS_DIR/on-generator-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-generator-stop: allows when no active sprint" {
  run echo "" | bash "$HOOKS_DIR/on-generator-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-generator-stop: blocks when status is active (not ready-for-eval)" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  echo '{"status":"active","attempt":1}' > "$HARNESS_STATE/sprints/sprint-01/status.json"

  run bash -c "echo '' | bash '$HOOKS_DIR/on-generator-stop.sh'"
  [[ "$status" -eq 2 ]]
}

# === on-evaluator-stop.sh ===

@test "on-evaluator-stop: allows valid eval report" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  echo '{"status":"ready-for-eval","attempt":1}' > "$HARNESS_STATE/sprints/sprint-01/status.json"
  cat > "$HARNESS_STATE/sprints/sprint-01/contract.json" <<'EOF'
{"criteria":[{"id":"C1-01"},{"id":"C1-02"},{"id":"C1-03"}]}
EOF
  cat > "$HARNESS_STATE/sprints/sprint-01/eval-report.json" <<'EOF'
{"overallResult":"PASS","criteriaResults":[{"id":"C1-01","result":"PASS"},{"id":"C1-02","result":"PASS"},{"id":"C1-03","result":"PASS"}]}
EOF

  run echo "" | bash "$HOOKS_DIR/on-evaluator-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-evaluator-stop: blocks when eval report missing" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  echo '{"status":"ready-for-eval","attempt":1}' > "$HARNESS_STATE/sprints/sprint-01/status.json"

  run bash -c "echo '' | bash '$HOOKS_DIR/on-evaluator-stop.sh'"
  [[ "$status" -eq 2 ]]
}

@test "on-evaluator-stop: blocks when overallResult missing" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  echo '{"status":"ready-for-eval","attempt":1}' > "$HARNESS_STATE/sprints/sprint-01/status.json"
  echo '{"criteriaResults":[]}' > "$HARNESS_STATE/sprints/sprint-01/eval-report.json"

  run bash -c "echo '' | bash '$HOOKS_DIR/on-evaluator-stop.sh'"
  [[ "$status" -eq 2 ]]
}

@test "on-evaluator-stop: blocks when criteriaResults missing" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  echo '{"status":"ready-for-eval","attempt":1}' > "$HARNESS_STATE/sprints/sprint-01/status.json"
  echo '{"overallResult":"PASS"}' > "$HARNESS_STATE/sprints/sprint-01/eval-report.json"

  run bash -c "echo '' | bash '$HOOKS_DIR/on-evaluator-stop.sh'"
  [[ "$status" -eq 2 ]]
}

@test "on-evaluator-stop: blocks when criteria count mismatch" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  echo '{"status":"ready-for-eval","attempt":1}' > "$HARNESS_STATE/sprints/sprint-01/status.json"
  echo '{"criteria":[{"id":"C1-01"},{"id":"C1-02"},{"id":"C1-03"}]}' > "$HARNESS_STATE/sprints/sprint-01/contract.json"
  echo '{"overallResult":"PASS","criteriaResults":[{"id":"C1-01","result":"PASS"}]}' > "$HARNESS_STATE/sprints/sprint-01/eval-report.json"

  run bash -c "echo '' | bash '$HOOKS_DIR/on-evaluator-stop.sh'"
  [[ "$status" -eq 2 ]]
}

@test "on-evaluator-stop: allows valid contract review" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  echo '{"criteria":[]}' > "$HARNESS_STATE/sprints/sprint-01/contract-proposal.json"
  echo '{"decision":"accepted","feedback":"OK"}' > "$HARNESS_STATE/sprints/sprint-01/contract-review.json"

  run echo "" | bash "$HOOKS_DIR/on-evaluator-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-evaluator-stop: blocks contract review without decision" {
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  echo '{"criteria":[]}' > "$HARNESS_STATE/sprints/sprint-01/contract-proposal.json"
  echo '{"feedback":"needs work"}' > "$HARNESS_STATE/sprints/sprint-01/contract-review.json"

  run bash -c "echo '' | bash '$HOOKS_DIR/on-evaluator-stop.sh'"
  [[ "$status" -eq 2 ]]
}

# === on-stop.sh ===

@test "on-stop: allows when no sprint plan exists" {
  run echo "" | bash "$HOOKS_DIR/on-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-stop: allows when no active sprints" {
  echo '{"sprints":[{"number":1}]}' > "$HARNESS_STATE/sprint-plan.json"
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  echo '{"status":"pass","attempt":1}' > "$HARNESS_STATE/sprints/sprint-01/status.json"

  run echo "" | bash "$HOOKS_DIR/on-stop.sh"
  [[ "$status" -eq 0 ]]
}

@test "on-stop: blocks when sprint is active" {
  echo '{"sprints":[{"number":1}]}' > "$HARNESS_STATE/sprint-plan.json"
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  echo '{"status":"active","attempt":1}' > "$HARNESS_STATE/sprints/sprint-01/status.json"

  run bash -c "echo '' | bash '$HOOKS_DIR/on-stop.sh'"
  [[ "$status" -eq 2 ]]
}

@test "on-stop: blocks when sprint is ready-for-eval" {
  echo '{"sprints":[{"number":1}]}' > "$HARNESS_STATE/sprint-plan.json"
  mkdir -p "$HARNESS_STATE/sprints/sprint-01"
  echo '{"status":"ready-for-eval","attempt":1}' > "$HARNESS_STATE/sprints/sprint-01/status.json"

  run bash -c "echo '' | bash '$HOOKS_DIR/on-stop.sh'"
  [[ "$status" -eq 2 ]]
}
