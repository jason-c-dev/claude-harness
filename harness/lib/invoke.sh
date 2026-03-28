#!/usr/bin/env bash
# Wrapper for claude -p invocations with real-time progress display
#
# Usage: invoke_claude --agent NAME --max-turns N [--mcp-config FILE] PROMPT
#
# Streams NDJSON from claude, shows tool calls and progress on stderr,
# and returns the exit code.

set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

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

  local mcp_flag=""
  if [[ -n "$mcp_config" ]]; then
    mcp_flag="--mcp-config $mcp_config"
  fi

  # Run claude with stream-json and filter for progress
  claude -p "$prompt" \
    --agent "$agent" \
    --max-turns "$max_turns" \
    --dangerously-skip-permissions \
    --output-format stream-json \
    --verbose \
    ${mcp_flag} \
    2>&1 | while IFS= read -r line; do
      # Parse each NDJSON line for progress info
      local msg_type
      msg_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null) || continue

      case "$msg_type" in
        system)
          # Session start info
          local session_id
          session_id=$(echo "$line" | jq -r '.session_id // empty' 2>/dev/null)
          if [[ -n "$session_id" ]]; then
            log_info "  Session: ${session_id:0:12}..." >&2 2>/dev/null || true
          fi
          ;;
        assistant)
          # Tool calls show what the agent is doing
          local tool_name
          tool_name=$(echo "$line" | jq -r '.message.content[]? | select(.type=="tool_use") | .name // empty' 2>/dev/null) || true
          if [[ -n "$tool_name" ]]; then
            local tool_input_preview
            tool_input_preview=$(echo "$line" | jq -r '.message.content[]? | select(.type=="tool_use") | .input | if .command then .command[:80] elif .file_path then .file_path elif .pattern then .pattern else (tostring[:80]) end' 2>/dev/null) || true
            echo -e "  \033[0;90m▸ ${tool_name}: ${tool_input_preview}\033[0m" >&2
          fi
          ;;
        result)
          # Final result
          local cost
          cost=$(echo "$line" | jq -r '.total_cost_usd // empty' 2>/dev/null) || true
          if [[ -n "$cost" && "$cost" != "null" ]]; then
            echo -e "  \033[0;90m  Cost: \$${cost}\033[0m" >&2
          fi
          # Check for errors
          local is_error
          is_error=$(echo "$line" | jq -r '.is_error // false' 2>/dev/null) || true
          if [[ "$is_error" == "true" ]]; then
            return 1
          fi
          ;;
      esac
    done

  # Return the pipe's exit status
  return "${PIPESTATUS[0]}"
}
