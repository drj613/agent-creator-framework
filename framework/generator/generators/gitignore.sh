#!/usr/bin/env bash
# gitignore.sh — Append validator log patterns to .gitignore
# Sourced by generate.sh; do not run directly.

generate_gitignore_entries() {
  local agent_dir
  agent_dir="$(jq_read '.agent_dir')"
  local gitignore_path="${PROJECT_DIR}/.gitignore"
  local pattern="${agent_dir}/hooks/validators/*_validator.log"

  if [[ -f "$gitignore_path" ]]; then
    if grep -qF "$pattern" "$gitignore_path"; then
      info ".gitignore: validator log pattern already present (skipped)"
      return
    fi
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Would append to .gitignore: $pattern"
    return
  fi

  {
    echo ""
    echo "# Validator hook logs"
    echo "$pattern"
  } >> "$gitignore_path"

  info ".gitignore: appended validator log pattern"
}
