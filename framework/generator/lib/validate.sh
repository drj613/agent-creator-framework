#!/usr/bin/env bash
# validate.sh — JSON schema validation for the discovery context
# Sourced by generate.sh; do not run directly.

# Module-level variable: allowed command prefixes for linter/type_checker entries
safe_cmd_prefixes=(
  eslint biome ruff mypy pyright tsc rubocop credo clippy golangci-lint
  mix bundle pnpm npm npx yarn uv cargo python python3 node
)

_validate_tool_entries() {
  local arr_key="$1"  # e.g. ".linters"
  local count
  count="$(jq "${arr_key} | length" <<< "$DISCOVERY_JSON")"
  for (( idx=0; idx<count; idx++ )); do
    local entry_prefix="${arr_key}[${idx}]"
    for req_field in name cmd language; do
      local val
      val="$(jq_read "${entry_prefix}.${req_field}")"
      [[ -n "$val" ]] || die "${arr_key}[${idx}] missing required field: ${req_field}"
    done
    # Validate cmd starts with an allowed prefix
    local cmd
    cmd="$(jq_read "${entry_prefix}.cmd")"
    local first_word="${cmd%% *}"
    local allowed=false
    for prefix in "${safe_cmd_prefixes[@]}"; do
      [[ "$first_word" == "$prefix" ]] && { allowed=true; break; }
    done
    if [[ "$allowed" != "true" ]]; then
      die "${arr_key}[${idx}].cmd starts with '${first_word}', which is not in the allowed command list. Allowed: ${safe_cmd_prefixes[*]}"
    fi
    # a) Reject shell metacharacters in cmd
    if [[ "$cmd" =~ [';''&''|''`''$''()''{}''<''>'] ]] || [[ "$cmd" == *$'\n'* ]]; then
      die "${arr_key}[${idx}].cmd contains unsafe shell characters: ${cmd}"
    fi
    # b) Validate tool name characters (used in file paths and script content)
    local name
    name="$(jq_read "${entry_prefix}.name")"
    if ! [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      die "${arr_key}[${idx}].name contains unsafe characters: ${name}"
    fi
    # c) file_extensions must be non-empty (empty array causes bash case syntax error)
    local ext_count
    ext_count="$(jq "${entry_prefix}.file_extensions | length" <<< "$DISCOVERY_JSON")"
    (( ext_count > 0 )) || die "${arr_key}[${idx}].file_extensions must be non-empty"
    # d) Reject dangerous runtime flags that allow arbitrary inline code execution
    local dangerous_flags=(-c -e --eval --exec --require --import)
    for flag in "${dangerous_flags[@]}"; do
      if [[ " $cmd " == *" $flag "* ]] || \
         [[ "$cmd" == *" $flag" ]] || \
         [[ "$cmd" == *" ${flag}="* ]]; then
        die "${arr_key}[${idx}].cmd uses disallowed flag '${flag}'"
      fi
    done
  done
}

validate_discovery_json() {
  local missing=()

  # Required top-level fields
  local required_fields=(
    ".platform"
    ".app_description"
    ".agent_dir"
    ".context_filename"
    ".project_type"
    ".primary_language"
    ".test_runner.cmd"
    ".test_runner.name"
    ".models.complex"
    ".models.standard"
    ".models.simple"
  )

  for field in "${required_fields[@]}"; do
    local val
    val="$(jq_read "$field")"
    [[ -n "$val" ]] || missing+=("$field")
  done

  if (( ${#missing[@]} > 0 )); then
    die "Missing required fields in discovery context: ${missing[*]}"
  fi

  # Validate test_runner.cmd: no shell metacharacters
  local test_cmd_val
  test_cmd_val="$(jq_read '.test_runner.cmd')"
  if [[ "$test_cmd_val" =~ [';''&''|''`''$''()''{}''<''>'] ]] || [[ "$test_cmd_val" == *$'\n'* ]]; then
    die ".test_runner.cmd contains unsafe shell characters: ${test_cmd_val}"
  fi

  # Validate .platform value is one of the allowed set
  local platform_val
  platform_val="$(jq_read '.platform')"
  local allowed_platforms=("claude-code" "opencode")
  local platform_valid=false
  for p in "${allowed_platforms[@]}"; do
    [[ "$platform_val" == "$p" ]] && { platform_valid=true; break; }
  done
  [[ "$platform_valid" == "true" ]] || die ".platform must be one of: ${allowed_platforms[*]}. Got: ${platform_val}"

  # e) Validate agent_dir: safe path characters only, no path traversal
  local agent_dir_val
  agent_dir_val="$(jq_read '.agent_dir')"
  if ! [[ "$agent_dir_val" =~ ^[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)*$ ]] || [[ "$agent_dir_val" == *".."* ]]; then
    die ".agent_dir contains unsafe characters or path traversal: ${agent_dir_val}"
  fi

  # Conditional: hooks enabled requires at least one linter or type checker
  local hooks_enabled
  hooks_enabled="$(jq_read '.features.post_tool_use_hooks')"
  if [[ "$hooks_enabled" == "true" ]]; then
    local linter_count type_checker_count
    linter_count="$(jq '.linters | length' <<< "$DISCOVERY_JSON")"
    type_checker_count="$(jq '.type_checkers | length' <<< "$DISCOVERY_JSON")"
    if (( linter_count + type_checker_count == 0 )); then
      die "features.post_tool_use_hooks is true but no linters or type_checkers are defined"
    fi
  fi

  # Conditional: monorepo requires workspaces
  local project_type
  project_type="$(jq_read '.project_type')"
  if [[ "$project_type" == "monorepo" ]]; then
    local ws_count
    ws_count="$(jq '.workspaces | if . == null then 0 else length end' <<< "$DISCOVERY_JSON")"
    if (( ws_count == 0 )); then
      die "project_type is 'monorepo' but workspaces is empty or null"
    fi
    # f) Validate workspace paths: safe characters only, no path traversal
    for (( wi=0; wi<ws_count; wi++ )); do
      local ws_p
      ws_p="$(jq -r ".workspaces[$wi].path" <<< "$DISCOVERY_JSON")"
      if ! [[ "$ws_p" =~ ^[a-zA-Z0-9._/-]+$ ]] || [[ "$ws_p" == *".."* ]]; then
        die ".workspaces[$wi].path contains unsafe characters or path traversal: ${ws_p}"
      fi
    done
  fi

  # Conditional: audit_docs requires documentation_structure
  local audit_docs doc_structure
  audit_docs="$(jq_read '.features.audit_docs')"
  doc_structure="$(jq_read '.features.documentation_structure')"
  if [[ "$audit_docs" == "true" && "$doc_structure" != "true" ]]; then
    die "features.audit_docs requires features.documentation_structure to be true"
  fi

  # Validate deep_discovery is a boolean if present, and requires documentation_structure
  local deep_discovery
  deep_discovery="$(jq -r '.features.deep_discovery // "false"' <<< "$DISCOVERY_JSON")"
  if [[ "$deep_discovery" != "true" && "$deep_discovery" != "false" ]]; then
    die "features.deep_discovery must be true or false, got: ${deep_discovery}"
  fi
  if [[ "$deep_discovery" == "true" && "$doc_structure" != "true" ]]; then
    die "features.deep_discovery requires features.documentation_structure to be true"
  fi

  # Arrays must be arrays, not null
  for arr_field in ".linters" ".type_checkers"; do
    local arr_type
    arr_type="$(jq "$arr_field | type" <<< "$DISCOVERY_JSON" 2>/dev/null)" || arr_type="null"
    if [[ "$arr_type" != '"array"' ]]; then
      die "$arr_field must be an array (use [] for empty), got $arr_type"
    fi
  done

  _validate_tool_entries ".linters"
  _validate_tool_entries ".type_checkers"
}
