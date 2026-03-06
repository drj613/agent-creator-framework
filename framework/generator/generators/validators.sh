#!/usr/bin/env bash
# validators.sh — Generate per-tool validator hook scripts
# Sourced by generate.sh; do not run directly.

generate_validators() {
  local agent_dir
  agent_dir="$(jq_read '.agent_dir')"

  local hooks_enabled
  hooks_enabled="$(jq_read '.features.post_tool_use_hooks')"
  if [[ "$hooks_enabled" != "true" ]]; then
    info "validators: post_tool_use_hooks disabled, skipping"
    return
  fi

  local linter_count type_checker_count
  linter_count="$(jq '.linters | length' <<< "$DISCOVERY_JSON")"
  type_checker_count="$(jq '.type_checkers | length' <<< "$DISCOVERY_JSON")"

  for (( i=0; i<linter_count; i++ )); do
    local name cmd language
    name="$(jq_read ".linters[$i].name")"
    cmd="$(jq_read ".linters[$i].cmd")"
    language="$(jq_read ".linters[$i].language")"
    generate_single_validator "$agent_dir" "$name" "$cmd" "$language" ".linters[$i].file_extensions"
  done

  for (( i=0; i<type_checker_count; i++ )); do
    local name cmd language
    name="$(jq_read ".type_checkers[$i].name")"
    cmd="$(jq_read ".type_checkers[$i].cmd")"
    language="$(jq_read ".type_checkers[$i].language")"
    generate_single_validator "$agent_dir" "$name" "$cmd" "$language" ".type_checkers[$i].file_extensions"
  done
}

generate_single_validator() {
  local agent_dir="$1"
  local tool_name="$2"
  local tool_cmd="$3"
  local tool_language="$4"
  local extensions_jq_path="$5"

  local lc_name
  lc_name="$(lowercase_name "$tool_name")"

  local case_pattern
  case_pattern="$(extensions_to_case_pattern "$extensions_jq_path")"

  local is_monorepo
  is_monorepo="$(jq_read '.project_type')"

  # Determine whole-project vs per-file
  local whole_project=false
  is_whole_project_checker "$tool_name" "$tool_cmd" && whole_project=true || true

  # Build match_workspace function block (monorepo only)
  local workspace_block=""
  local static_target_dir_line=""
  local post_case_target_dir_line=""

  if [[ "$is_monorepo" == "monorepo" ]]; then
    local ws_count
    ws_count="$(jq '.workspaces | length' <<< "$DISCOVERY_JSON")"
    local ws_json_sorted
    ws_json_sorted="$(jq '[.workspaces[] | {name, path, language}] | sort_by(.path | length) | reverse' <<< "$DISCOVERY_JSON")"
    local match_lines=""
    for (( wi=0; wi<ws_count; wi++ )); do
      local ws_path
      ws_path="$(echo "$ws_json_sorted" | jq -r ".[$wi].path")"
      match_lines+="  [[ \"\$rel\" == \"${ws_path}\"* ]] && { echo \"\$PROJECT_DIR/${ws_path}\"; return; }"$'\n'
    done
    workspace_block="$(printf 'match_workspace() {\n  local fp="$1"\n  local rel="${fp#"$PROJECT_DIR/"}"\n%s  echo "$PROJECT_DIR"\n}' "$match_lines")"
    post_case_target_dir_line='TARGET_DIR="$(match_workspace "$file_path")"'
  else
    local target_subdir
    target_subdir="$(resolve_target_dir "$tool_language")"
    if [[ -n "$target_subdir" ]]; then
      static_target_dir_line="TARGET_DIR=\"\$PROJECT_DIR/${target_subdir}\""
    else
      static_target_dir_line='TARGET_DIR="$PROJECT_DIR"'
    fi
  fi

  # Build the run section.
  # NOTE (per-file branch): tool cmd must NOT include a target path — this template appends
  # '-- "$file_path"' automatically. Use e.g. 'pnpm eslint' not 'pnpm eslint src'.
  local run_section
  if [[ "$whole_project" == "true" ]]; then
    run_section='log "INFO" "Validating: $file_path (whole-project check)"
output=""
if output=$(cd "$TARGET_DIR" && run_with_timeout 120 '"${tool_cmd}"' 2>&1); then
  log "INFO" "PASS"
  echo '"'"'{}'"'"'
else
  output="${output:0:500}"
  log "WARN" "FAIL: $output"
  jq -n --arg reason "$(printf '"'"'%s failed:\n%s'"'"' '"'"''"${tool_name}"''"'"' "$output")" '"'"'{"decision": "block", "reason": $reason}'"'"'
fi'
  else
    run_section='log "INFO" "Validating: $file_path"
output=""
if output=$(cd "$TARGET_DIR" && run_with_timeout 120 '"${tool_cmd}"' -- "$file_path" 2>&1); then
  log "INFO" "PASS: $file_path"
  echo '"'"'{}'"'"'
else
  output="${output:0:500}"
  log "WARN" "FAIL: $file_path -- $output"
  jq -n --arg reason "$(printf '"'"'%s failed:\n%s'"'"' '"'"''"${tool_name}"''"'"' "$output")" '"'"'{"decision": "block", "reason": $reason}'"'"'
fi'
  fi

  # Assemble the script using string concatenation to keep each part clearly quoted
  local nl=$'\n'
  local content=""
  content+="#!/usr/bin/env bash${nl}"
  content+="# Validator: ${tool_name}${nl}"
  content+="# Runs ${tool_cmd} on files matching ${case_pattern}${nl}"
  content+="${nl}"
  content+="set -euo pipefail${nl}"
  content+="${nl}"
  content+='SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"'"${nl}"
  local fallback_depth
  fallback_depth="$(compute_fallback_depth "$agent_dir" "hooks/validators")"
  content+='PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || { cd "$SCRIPT_DIR/'"${fallback_depth}"'" && pwd; })"'"${nl}"
  content+="${nl}"
  if [[ -n "$workspace_block" ]]; then
    content+="${workspace_block}${nl}"
    content+="${nl}"
  fi
  if [[ -n "$static_target_dir_line" ]]; then
    content+="${static_target_dir_line}${nl}"
    content+="${nl}"
  fi
  content+='LOG_FILE="$SCRIPT_DIR/'"${lc_name}"'_validator.log"'"${nl}"
  content+="${nl}"
  content+='if command -v timeout > /dev/null 2>&1; then'"${nl}"
  content+='  run_with_timeout() { timeout "$@"; }'"${nl}"
  content+='else'"${nl}"
  content+='  run_with_timeout() {'"${nl}"
  content+='    local secs="$1"; shift'"${nl}"
  content+='    "$@" &'"${nl}"
  content+='    local pid=$!'"${nl}"
  content+='    ( sleep "$secs" && kill "$pid" 2>/dev/null ) &'"${nl}"
  content+='    local watchdog=$!'"${nl}"
  content+='    wait "$pid" 2>/dev/null'"${nl}"
  content+='    local rc=$?'"${nl}"
  content+='    kill "$watchdog" 2>/dev/null || true; wait "$watchdog" 2>/dev/null || true'"${nl}"
  content+='    return $rc'"${nl}"
  content+='  }'"${nl}"
  content+='fi'"${nl}"
  content+="${nl}"
  content+='log() {'"${nl}"
  content+='  local msg="$2"'"${nl}"
  content+='  local SQ="'"'"'"'"${nl}"
  content+='  msg="$(echo "$msg" | sed -E '"'"'s/"[^"]{20,}"/[REDACTED]/g'"'"' | sed -E "s/${SQ}[^${SQ}]{20,}${SQ}/[REDACTED]/g")"'"${nl}"
  content+='  echo "$(date '"'"'+%Y-%m-%dT%H:%M:%S'"'"') $1: $msg" >> "$LOG_FILE"'"${nl}"
  content+='}'"${nl}"
  content+="${nl}"
  content+='input="$(head -c 65536)"'"${nl}"
  content+='file_path="$(echo "$input" | jq -r '"'"'.tool_input.file_path // ""'"'"' 2>/dev/null)" || {'"${nl}"
  content+='  echo '"'"'{}'"'"'; exit 0'"${nl}"
  content+='}'"${nl}"
  content+="${nl}"
  content+='case "$file_path" in'"${nl}"
  content+="  ${case_pattern}) ;;${nl}"
  content+="  *) echo '{}'; exit 0 ;;${nl}"
  content+='esac'"${nl}"
  if [[ -n "$post_case_target_dir_line" ]]; then
    content+="${nl}"
    content+="${post_case_target_dir_line}${nl}"
  fi
  content+="${nl}"
  content+="${run_section}${nl}"

  write_executable "${PROJECT_DIR}/${agent_dir}/hooks/validators/${lc_name}_validator.sh" "$content"
  info "${lc_name}_validator.sh"
}
