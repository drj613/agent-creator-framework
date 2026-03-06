#!/usr/bin/env bash
# helpers.sh — Shared utility functions for the generator
# Sourced by generate.sh; do not run directly.

# --- Globals (set by generate.sh before sourcing) ---
# DISCOVERY_JSON: full JSON string from .discovery-context.json
# DRY_RUN: "true" or "false"
# PROJECT_DIR: absolute path to the project root

CREATED_FILES=()

# --- JSON helpers ---

# Read a value from the discovery JSON. Returns empty string for null/missing.
jq_read() {
  jq -r "$1 // empty" <<< "$DISCOVERY_JSON"
}

# Read a raw JSON value (preserves types, arrays, objects).
jq_raw() {
  jq "$1" <<< "$DISCOVERY_JSON"
}

# --- Output helpers ---

die() {
  echo "ERROR: $1" >&2
  exit 1
}

info() {
  echo "  $1"
}

# Write content to a file, creating parent directories as needed.
write_file() {
  local path="$1"
  local content="$2"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Would create: $path"
    CREATED_FILES+=("$path")
    return
  fi

  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
  CREATED_FILES+=("$path")
}

# Write content to a file and set executable permission.
write_executable() {
  write_file "$1" "$2"
  [[ "$DRY_RUN" == "true" ]] || chmod +x "$1"
}

# --- Conversion helpers ---

# Convert a JSON array of file extensions to a bash case pattern.
# Usage: extensions_to_case_pattern '.linters[0].file_extensions'
# Input:  [".ts", ".tsx"]
# Output: *.ts|*.tsx
extensions_to_case_pattern() {
  jq -r "$1 | map(\"*\" + .) | join(\"|\")" <<< "$DISCOVERY_JSON"
}

# Lowercase a tool name for filename use (ESLint -> eslint, tsc -> tsc).
lowercase_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Determine the target directory for a linter/type-checker based on its language.
# Matches against directories.backend_lang / frontend_lang.
# Returns path relative to project root (empty string = project root).
resolve_target_dir() {
  local tool_language="$1"
  local backend_lang frontend_lang backend_root frontend_root

  backend_lang="$(jq_read '.directories.backend_lang')"
  frontend_lang="$(jq_read '.directories.frontend_lang')"
  backend_root="$(jq_read '.directories.backend_root')"
  frontend_root="$(jq_read '.directories.frontend_root')"

  if [[ -n "$backend_lang" && "$tool_language" == "$backend_lang" && -n "$backend_root" ]]; then
    echo "$backend_root"
  elif [[ -n "$frontend_lang" && "$tool_language" == "$frontend_lang" && -n "$frontend_root" ]]; then
    echo "$frontend_root"
  else
    echo ""
  fi
}

# Check if a type checker runs on the whole project (no per-file argument).
is_whole_project_checker() {
  local name="$1"
  local cmd="$2"
  local lc_name
  lc_name="$(lowercase_name "$name")"

  case "$lc_name" in
    tsc) return 0 ;;
  esac
  [[ "$cmd" == *"--noEmit"* ]] && return 0
  return 1
}

# Compute the fallback depth (../ chain) for scripts at a given subpath.
# E.g., agent_dir=".claude", subpath="hooks/validators" -> depth 3 -> "../../.."
compute_fallback_depth() {
  local agent_dir="$1"
  local subpath="$2"
  local full_path="${agent_dir}/${subpath}"
  local depth
  depth="$(echo "$full_path" | tr '/' '\n' | grep -c .)"
  local result=""
  for (( i=0; i<depth; i++ )); do
    [[ -n "$result" ]] && result+="/"
    result+=".."
  done
  echo "$result"
}
