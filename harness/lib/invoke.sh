#!/usr/bin/env bash
# Wrapper for claude -p invocations with real-time progress display
#
# Usage: invoke_claude --agent NAME --max-turns N [--mcp-config FILE] PROMPT

set -euo pipefail

invoke_claude() {
  local agent="" max_turns="50" mcp_config="" prompt=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent) agent="$2"; shift 2 ;;
      --max-turns) max_turns="$2"; shift 2 ;;
      --mcp-config) mcp_config="$2"; shift 2 ;;
      *) prompt="$1"; shift ;;
    esac
  done

  # Use --permission-mode dontAsk (auto-approves but still runs hooks)
  # NOT --dangerously-skip-permissions (which skips hooks entirely)
  local -a cmd=(claude -p "$prompt"
    --agent "$agent"
    --max-turns "$max_turns"
    --permission-mode dontAsk
    --output-format stream-json
    --verbose
  )

  if [[ -n "$mcp_config" ]]; then
    cmd+=(--mcp-config "$mcp_config")
  fi

  # Stream NDJSON, filter for progress lines on stderr, propagate exit code
  local output_file
  output_file=$(mktemp)
  local exit_code=0

  "${cmd[@]}" > "$output_file" 2>&1 || exit_code=$?

  # Parse the stream for progress display
  while IFS= read -r line; do
    local msg_type
    msg_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null) || continue

    case "$msg_type" in
      assistant)
        local tool_name
        tool_name=$(echo "$line" | jq -r '
          .message.content[]? | select(.type=="tool_use") | .name // empty
        ' 2>/dev/null) || true
        if [[ -n "$tool_name" ]]; then
          local preview
          preview=$(echo "$line" | jq -r '
            .message.content[]? | select(.type=="tool_use") | .input |
            if .command then .command[:80]
            elif .file_path then .file_path
            elif .pattern then .pattern
            else (tostring[:60])
            end
          ' 2>/dev/null) || true
          echo -e "  \033[0;90m▸ ${tool_name}: ${preview}\033[0m" >&2
        fi
        ;;
      result)
        local cost
        cost=$(echo "$line" | jq -r '.total_cost_usd // empty' 2>/dev/null) || true
        if [[ -n "$cost" && "$cost" != "null" ]]; then
          echo -e "  \033[0;90m  Cost: \$${cost}\033[0m" >&2
        fi
        ;;
    esac
  done < "$output_file"

  rm -f "$output_file"
  return "$exit_code"
}
