#!/usr/bin/env bash
# hooks.sh — Generate check-env.sh, audit-docs-hook.sh, audit-docs.sh
# Sourced by generate.sh; do not run directly.

generate_hooks() {
  local agent_dir
  agent_dir="$(jq_read '.agent_dir')"

  generate_check_env "$agent_dir"

  local audit_docs
  audit_docs="$(jq_read '.features.audit_docs')"
  if [[ "$audit_docs" == "true" ]]; then
    generate_audit_docs_hook "$agent_dir"
    generate_audit_docs "$agent_dir"
  fi
}

generate_check_env() {
  local agent_dir="$1"

  # Build ENV_CANDIDATES array from discovery JSON
  local env_found_count
  env_found_count="$(jq '.env_files.found | if . == null then 0 else length end' <<< "$DISCOVERY_JSON")"
  local env_array_bash="("
  if (( env_found_count > 0 )); then
    for (( i=0; i<env_found_count; i++ )); do
      local ef
      ef="$(jq_read ".env_files.found[$i]")"
      # Sanitize: reject entries with shell-unsafe characters or embedded newlines
      if [[ "$ef" =~ [\"$\`\\] ]] || [[ "$ef" == *$'\n'* ]] || [[ -z "$ef" ]]; then
        continue
      fi
      env_array_bash+="\"$ef\" "
    done
  else
    env_array_bash+='".env" ".env.local" ".env.development" '
  fi
  env_array_bash+=")"

  # Use split-heredoc pattern: quoted heredocs for static parts ($ and ` are literal),
  # direct variable interpolation only for the dynamic $env_array_bash and $fallback_depth.
  # NOTE: delimiter must not appear as a prefix of any variable name in the body
  # (e.g. 'SCRIPT' would match 'SCRIPT_DIR'). Using 'GENEOF' avoids this.
  local fallback_depth
  fallback_depth="$(compute_fallback_depth "$agent_dir" "hooks")"

  # shellcheck disable=SC2016  # single-quoted heredoc — $ intentionally unexpanded
  local header footer project_dir_line
  header="$(cat <<'GENEOF'
#!/usr/bin/env bash
set -euo pipefail

cat > /dev/null

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GENEOF
)"
  project_dir_line='PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || { cd "$SCRIPT_DIR/'"${fallback_depth}"'" && pwd; })"'

  # shellcheck disable=SC2016  # single-quoted heredoc — $ intentionally unexpanded
  footer="$(cat <<'GENEOF'

for f in "${ENV_CANDIDATES[@]}"; do
  if [[ -f "$PROJECT_DIR/$f" ]]; then
    jq -n --arg reason "$(printf '\xe2\x9c\x93 %s found' "$f")" \
      '{reason: $reason}'
    exit 0
  fi
done

hint=""
[[ -f "$PROJECT_DIR/.env.example" ]] && hint=" (copy from .env.example)"
candidates_str="$(printf '%s, ' "${ENV_CANDIDATES[@]}" | sed 's/, $//')"
jq -n --arg reason "$(printf '\xe2\x9a\xa0 No environment file found%s. The app may not start correctly. Looked for: %s' "$hint" "$candidates_str")" \
  '{reason: $reason}'
GENEOF
)"

  local content="${header}"$'\n'"${project_dir_line}"$'\n'"ENV_CANDIDATES=${env_array_bash}${footer}"

  write_executable "${PROJECT_DIR}/${agent_dir}/hooks/check-env.sh" "$content"
  info "check-env.sh"
}

generate_audit_docs_hook() {
  local agent_dir="$1"

  # Use split-heredoc pattern: quoted heredocs for static parts, interpolation for fallback_depth.
  # NOTE: delimiter 'GENEOF' chosen so it does not prefix any variable name in the body.
  local fallback_depth
  fallback_depth="$(compute_fallback_depth "$agent_dir" "hooks")"

  # shellcheck disable=SC2016  # single-quoted heredoc — $ intentionally unexpanded
  local content_pre content_post project_dir_line
  content_pre="$(cat <<'GENEOF'
#!/usr/bin/env bash
set -euo pipefail

# Read hook input from stdin (size-limited for safety)
input="$(head -c 65536)"
command="$(echo "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)" || {
  echo '{}'; exit 0
}

# Only run on git commit
[[ "$command" == *"git commit"* ]] || { echo '{}'; exit 0; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GENEOF
)"
  project_dir_line='PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || { cd "$SCRIPT_DIR/'"${fallback_depth}"'" && pwd; })"'

  # shellcheck disable=SC2016  # single-quoted heredoc — $ intentionally unexpanded
  content_post="$(cat <<'GENEOF'
DOCS_DIR="$PROJECT_DIR/docs"

[[ -d "$DOCS_DIR" ]] || { echo '{}'; exit 0; }

# Filename patterns indicating temporary docs
TEMP_PATTERN='_(SUMMARY|ANALYSIS|RESULTS?|CHECKLIST|MEETING|NOTES?|v[0-9]+|[0-9]{4}-[0-9]{2}-[0-9]{2}).*\.md$'

flagged=()
while IFS= read -r f; do
  name="$(basename "$f")"
  if echo "$name" | grep -qEi "$TEMP_PATTERN"; then
    # Compute path relative to project root
    flagged+=("${f#"$PROJECT_DIR/"}")
  fi
done < <(find "$DOCS_DIR" -name "*.md" -type f 2>/dev/null)

if (( ${#flagged[@]} > 0 )); then
  file_list="$(printf '  - %s\n' "${flagged[@]}")"
  jq -n --arg reason "$(printf '\xe2\x9a\xa0 Temporary docs detected in docs/:\n%s\nConsider running /audit-docs to clean these up.' "$file_list")" \
    '{reason: $reason}'
else
  echo '{}'
fi
GENEOF
)"

  local content="${content_pre}"$'\n'"${project_dir_line}"$'\n'"${content_post}"

  write_executable "${PROJECT_DIR}/${agent_dir}/hooks/audit-docs-hook.sh" "$content"
  info "audit-docs-hook.sh"
}

generate_audit_docs() {
  local agent_dir="$1"

  # Use a quoted heredoc so bash does not expand $ or ` inside the script body.
  # NOTE: delimiter 'GENEOF' chosen so it does not prefix any variable name in the body.
  # shellcheck disable=SC2016  # single-quoted heredoc — $ intentionally unexpanded
  local content
  content="$(cat <<'GENEOF'
#!/usr/bin/env bash
# audit-docs.sh — Collect documentation health signals as JSON
# Requires: bash 3.2+, jq, git

set -euo pipefail

# --- Defaults ---
DOCS_DIR="docs"
SPECS_DIR="specs"
INDEX_FILE="docs/README.md"
DAYS_HIGH=90
DAYS_MEDIUM=60
SPECS_MAX_AGE=30

# --- Argument parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --docs-dir)      DOCS_DIR="$2";      shift 2 ;;
    --specs-dir)     SPECS_DIR="$2";     shift 2 ;;
    --index-file)    INDEX_FILE="$2";    shift 2 ;;
    --days-high)     DAYS_HIGH="$2";     shift 2 ;;
    --days-medium)   DAYS_MEDIUM="$2";   shift 2 ;;
    --specs-max-age) SPECS_MAX_AGE="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# --- Dependency check ---
for cmd in jq git; do
  command -v "$cmd" > /dev/null 2>&1 || {
    echo "ERROR: $cmd is required but not found." >&2
    [[ "$cmd" == "jq" ]] && echo "Install: brew install jq (macOS) or apt-get install jq (Linux)" >&2
    exit 1
  }
done

NOW="$(date +%s)"
GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# Temp pattern for detecting temporary docs (matches audit-docs-hook.sh)
TEMP_PATTERN='_(SUMMARY|ANALYSIS|RESULTS?|CHECKLIST|MEETING|NOTES?|v[0-9]+|[0-9]{4}-[0-9]{2}-[0-9]{2}).*\.md$'

# Version/date reference pattern for content scanning
STALE_VERSION_PATTERN='(v[0-9]+\.[0-9]+\.[0-9]+|20[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])|Q[1-4] 20[0-9]{2}|Sprint [0-9]+)'

# --- Helper: read index file into a string for grep ---
INDEX_CONTENT=""
[[ -f "$INDEX_FILE" ]] && INDEX_CONTENT="$(cat "$INDEX_FILE")"

# ================================================================
# AUDIT DOC FILES
# ================================================================

audit_doc_file() {
  local file="$1"
  local basename_file
  basename_file="$(basename "$file")"

  # Last edit: epoch and days ago
  local last_edit_epoch
  last_edit_epoch="$(git log -1 --format=%at -- "$file" 2>/dev/null || echo 0)"
  local last_edit_days=0
  local last_edit_date="unknown"
  if (( last_edit_epoch > 0 )); then
    last_edit_days=$(( (NOW - last_edit_epoch) / 86400 ))
    last_edit_date="$(date -r "$last_edit_epoch" '+%Y-%m-%d' 2>/dev/null || date -d "@$last_edit_epoch" '+%Y-%m-%d' 2>/dev/null || echo 'unknown')"
  fi

  # Commit count in lookback window
  local commits_90d
  commits_90d="$(git log --since="${DAYS_HIGH} days ago" --oneline -- "$file" 2>/dev/null | wc -l | tr -d ' ')"

  # Temporary file detection
  local is_temporary=false
  local temp_pattern_matched="null"
  if echo "$basename_file" | grep -qEi "$TEMP_PATTERN"; then
    is_temporary=true
    temp_pattern_matched="$(echo "$basename_file" | grep -oEi '_(SUMMARY|ANALYSIS|RESULTS?|CHECKLIST|MEETING|NOTES?|v[0-9]+|[0-9]{4}-[0-9]{2}-[0-9]{2})' | head -1)"
  fi

  # Index check
  local in_index=false
  if [[ -n "$INDEX_CONTENT" ]] && echo "$INDEX_CONTENT" | grep -qF "$basename_file"; then
    in_index=true
  fi

  # Co-change analysis
  local co_change_json="[]"
  if (( last_edit_epoch > 0 )); then
    local last_doc_commit
    last_doc_commit="$(git log -1 --format=%H -- "$file" 2>/dev/null || echo '')"
    if [[ -n "$last_doc_commit" ]]; then
      co_change_json="$(
        git log "$last_doc_commit"..HEAD --name-only --pretty=format: 2>/dev/null \
        | grep -v '^\s*$' \
        | grep -v '\.md$' \
        | sort | uniq -c | sort -rn | head -10 \
        | while read -r count path; do
            [[ -n "$path" ]] && jq -n --arg p "$path" --argjson c "$count" '{path: $p, commits_since_doc_edit: $c}'
          done \
        | jq -s '.'
      )"
      [[ -z "$co_change_json" || "$co_change_json" == "null" ]] && co_change_json="[]"
    fi
  fi

  # TODO count
  local todo_count
  todo_count="$(grep -ciE '\bTODO\b' "$file" 2>/dev/null || echo 0)"

  # Stale version/date references
  local has_stale_versions=false
  if grep -qE "$STALE_VERSION_PATTERN" "$file" 2>/dev/null; then
    has_stale_versions=true
  fi

  # Risk level assignment
  local risk_level="low"
  if [[ "$is_temporary" == "true" ]] || { (( last_edit_days > DAYS_HIGH )) && (( commits_90d == 0 )); }; then
    risk_level="high"
  elif (( last_edit_days > DAYS_MEDIUM )) || [[ "$in_index" == "false" ]] || (( todo_count > 0 )); then
    risk_level="medium"
  fi

  jq -n \
    --arg path "$file" \
    --argjson last_edit_days "$last_edit_days" \
    --arg last_edit_date "$last_edit_date" \
    --argjson commits_90d "$commits_90d" \
    --argjson is_temporary "$is_temporary" \
    --arg temp_pattern_matched "$temp_pattern_matched" \
    --argjson in_index "$in_index" \
    --argjson co_change_files "$co_change_json" \
    --argjson todo_count "$todo_count" \
    --argjson has_stale_versions "$has_stale_versions" \
    --arg risk_level "$risk_level" \
    '{
      path: $path,
      last_edit_days: $last_edit_days,
      last_edit_date: $last_edit_date,
      commits_90d: $commits_90d,
      is_temporary: $is_temporary,
      temp_pattern_matched: (if $temp_pattern_matched == "null" then null else $temp_pattern_matched end),
      in_index: $in_index,
      co_change_files: $co_change_files,
      todo_count: $todo_count,
      has_stale_versions: $has_stale_versions,
      risk_level: $risk_level
    }'
}

# ================================================================
# AUDIT SPEC FILES
# ================================================================

audit_spec_file() {
  local file="$1"
  local basename_file
  basename_file="$(basename "$file")"

  # Age in days
  local created_epoch
  created_epoch="$(git log --follow --diff-filter=A --format=%at -- "$file" 2>/dev/null | tail -1)"
  [[ -z "$created_epoch" ]] && created_epoch="$(git log -1 --format=%at -- "$file" 2>/dev/null || echo "$NOW")"
  local age_days=$(( (NOW - created_epoch) / 86400 ))

  # Git evidence: commits mentioning this spec's name
  local spec_name="${basename_file%.md}"
  local git_evidence_commits
  git_evidence_commits="$(git log --all --oneline --fixed-strings --grep="$spec_name" 2>/dev/null | wc -l | tr -d ' ')"

  # Check if files listed in the spec exist
  local listed_files_exist=false
  if [[ -f "$file" ]]; then
    local listed_paths
    listed_paths="$(grep -E '^\s*[-*]\s+`[^`]+`' "$file" 2>/dev/null | grep -oE '`[^`]+\.[a-z]+`' | tr -d '`' || true)"
    if [[ -n "$listed_paths" ]]; then
      local all_exist=true
      while IFS= read -r p; do
        [[ -f "$p" ]] || { all_exist=false; break; }
      done <<< "$listed_paths"
      [[ "$all_exist" == "true" ]] && listed_files_exist=true
    fi
  fi

  # Classification
  local classification="never_built_recent"
  if (( git_evidence_commits > 0 )) && [[ "$listed_files_exist" == "true" ]]; then
    classification="built_complete"
  elif (( git_evidence_commits > 0 )); then
    classification="built_partial"
  elif (( age_days > SPECS_MAX_AGE )); then
    classification="never_built_old"
  fi

  jq -n \
    --arg path "$file" \
    --argjson age_days "$age_days" \
    --argjson git_evidence_commits "$git_evidence_commits" \
    --argjson listed_files_exist "$listed_files_exist" \
    --arg classification "$classification" \
    '{
      path: $path,
      age_days: $age_days,
      git_evidence_commits: $git_evidence_commits,
      listed_files_exist: $listed_files_exist,
      classification: $classification
    }'
}

# ================================================================
# MAIN: Collect all signals
# ================================================================

# Collect doc files
doc_files=()
if [[ -d "$DOCS_DIR" ]]; then
  while IFS= read -r f; do
    doc_files+=("$f")
  done < <(find "$DOCS_DIR" -name "*.md" -type f 2>/dev/null | sort)
fi
# Also audit root-level doc files
for root_doc in CHANGELOG.md README.md; do
  [[ -f "$root_doc" ]] && doc_files+=("$root_doc")
done

doc_entries_file=""
spec_entries_file=""
trap 'rm -f "$doc_entries_file" "$spec_entries_file"' EXIT
doc_entries_file="$(mktemp /tmp/audit_docs.XXXXXX)"
spec_entries_file="$(mktemp /tmp/audit_specs.XXXXXX)"
for f in "${doc_files[@]}"; do
  audit_doc_file "$f" >> "$doc_entries_file"
done
docs_json="$(jq -s '.' "$doc_entries_file")"

# Collect spec files
if [[ -d "$SPECS_DIR" ]]; then
  while IFS= read -r f; do
    audit_spec_file "$f" >> "$spec_entries_file"
  done < <(find "$SPECS_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null | sort)
fi
specs_json="$(jq -s '.' "$spec_entries_file")"

# Find untracked files (in docs/ but not in index)
untracked_json="[]"
if [[ -n "$INDEX_CONTENT" ]]; then
  untracked_json="$(echo "$docs_json" | jq '[.[] | select(.in_index == false) | .path]')"
fi

# Summary statistics
summary_json="$(echo "$docs_json" "$specs_json" | jq -s '
  {
    total_docs: (.[0] | length),
    high_risk: ([.[0][] | select(.risk_level == "high")] | length),
    medium_risk: ([.[0][] | select(.risk_level == "medium")] | length),
    low_risk: ([.[0][] | select(.risk_level == "low")] | length),
    total_specs: (.[1] | length),
    specs_built: ([.[1][] | select(.classification == "built_complete" or .classification == "built_partial")] | length),
    specs_abandoned: ([.[1][] | select(.classification == "never_built_old")] | length),
    specs_recent: ([.[1][] | select(.classification == "never_built_recent")] | length)
  }
')"

# Assemble final output
jq -n \
  --arg generated_at "$GENERATED_AT" \
  --arg docs_dir "$DOCS_DIR" \
  --arg specs_dir "$SPECS_DIR" \
  --arg index_file "$INDEX_FILE" \
  --argjson days_high "$DAYS_HIGH" \
  --argjson days_medium "$DAYS_MEDIUM" \
  --argjson specs_max_age "$SPECS_MAX_AGE" \
  --argjson docs "$docs_json" \
  --argjson specs "$specs_json" \
  --argjson untracked "$untracked_json" \
  --argjson summary "$summary_json" \
  '{
    generated_at: $generated_at,
    params: {
      docs_dir: $docs_dir,
      specs_dir: $specs_dir,
      index_file: $index_file,
      days_high: $days_high,
      days_medium: $days_medium,
      specs_max_age: $specs_max_age
    },
    docs: $docs,
    specs: $specs,
    untracked: $untracked,
    summary: $summary
  }'
GENEOF
)"

  write_executable "${PROJECT_DIR}/${agent_dir}/hooks/audit-docs.sh" "$content"
  info "audit-docs.sh"
}
