#!/usr/bin/env bash
# generate.sh — Generate project-specific agent workflow files from discovery context JSON
# Usage: bash framework/generator/generate.sh <discovery-context.json> [--dry-run] [--validate-output]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Argument parsing ---
DISCOVERY_FILE=""
DRY_RUN="false"
VALIDATE_OUTPUT="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN="true"; shift ;;
    --validate-output) VALIDATE_OUTPUT="true"; shift ;;
    --*) echo "Unknown option: $1" >&2; exit 1 ;;
    *)
      if [[ -z "$DISCOVERY_FILE" ]]; then
        DISCOVERY_FILE="$1"
      else
        echo "ERROR: Unexpected argument: $1" >&2; exit 1
      fi
      shift ;;
  esac
done

if [[ -z "$DISCOVERY_FILE" ]]; then
  echo "Usage: bash generate.sh <discovery-context.json> [--dry-run] [--validate-output]" >&2
  exit 1
fi

if [[ ! -f "$DISCOVERY_FILE" ]]; then
  echo "ERROR: File not found: $DISCOVERY_FILE" >&2
  exit 1
fi

# Dependency check
command -v jq > /dev/null 2>&1 || {
  echo "ERROR: jq is required but not found. Install: brew install jq (macOS) or apt-get install jq (Linux)" >&2
  exit 1
}

# Load discovery JSON
DISCOVERY_JSON="$(cat "$DISCOVERY_FILE")"
export DISCOVERY_JSON DRY_RUN VALIDATE_OUTPUT

# Determine project dir — use discovery.directories.project_root if set, else cwd
PROJECT_DIR="$(jq -r '.directories.project_root // empty' <<< "$DISCOVERY_JSON")"
if [[ -z "$PROJECT_DIR" ]]; then
  PROJECT_DIR="$(pwd)"
fi
export PROJECT_DIR

# Source libraries
# shellcheck source=lib/helpers.sh
source "$SCRIPT_DIR/lib/helpers.sh"
# shellcheck source=lib/validate.sh
source "$SCRIPT_DIR/lib/validate.sh"

# Source generators
# shellcheck source=generators/validators.sh
source "$SCRIPT_DIR/generators/validators.sh"
# shellcheck source=generators/hooks.sh
source "$SCRIPT_DIR/generators/hooks.sh"
# shellcheck source=generators/agents.sh
source "$SCRIPT_DIR/generators/agents.sh"
# shellcheck source=generators/gitignore.sh
source "$SCRIPT_DIR/generators/gitignore.sh"

# --- Validate ---
echo "Validating discovery context..."
validate_discovery_json
echo "  OK"

# --- Generate ---
echo ""
if [[ "$DRY_RUN" == "true" ]]; then
  echo "Dry run — showing files that would be created:"
else
  echo "Generating files..."
fi
echo ""

# Create directory structure first
agent_dir="$(jq_read '.agent_dir')"
if [[ "$DRY_RUN" != "true" ]]; then
  mkdir -p "${PROJECT_DIR}/${agent_dir}/hooks/validators"
  mkdir -p "${PROJECT_DIR}/${agent_dir}/agents/team"
  if [[ "$(jq -r '.features.plan_build // "false"' <<< "$DISCOVERY_JSON")" == "true" ]]; then
    mkdir -p "${PROJECT_DIR}/specs/archive"
  fi
  if [[ "$(jq -r '.features.documentation_structure // "false"' <<< "$DISCOVERY_JSON")" == "true" ]]; then
    mkdir -p "${PROJECT_DIR}/docs"
  fi
  if [[ "$(jq -r '.features.deep_discovery // "false"' <<< "$DISCOVERY_JSON")" == "true" ]]; then
    mkdir -p "${PROJECT_DIR}/${agent_dir}/discovery"
    mkdir -p "${PROJECT_DIR}/docs/modules"
  fi
fi

# Run each generator
generate_validators
generate_hooks
generate_agents

# Static scripts — copied as-is when their feature is enabled
if [[ "$(jq -r '.features.github_flow // "false"' <<< "$DISCOVERY_JSON")" == "true" ]]; then
  if [[ "$DRY_RUN" != "true" ]]; then
    mkdir -p "${PROJECT_DIR}/${agent_dir}/scripts"
  fi
  write_file "${PROJECT_DIR}/${agent_dir}/scripts/wait-for-copilot.sh" \
    "$(cat "$SCRIPT_DIR/templates/scripts/wait-for-copilot.sh")"
fi

generate_gitignore_entries

# --- Validate output ---
if [[ "$VALIDATE_OUTPUT" == "true" && "$DRY_RUN" != "true" ]]; then
  echo ""
  echo "Validating output for unresolved markers..."
  _marker_total=0
  _files_with_markers=0
  for _file in "${CREATED_FILES[@]}"; do
    [[ -f "$_file" ]] || continue
    _matches="$(grep -nE '\{\{[^}]*\}\}' "$_file" 2>/dev/null || true)"
    if [[ -n "$_matches" ]]; then
      (( _files_with_markers += 1 ))
      while IFS= read -r _line; do
        echo "  ${_file}:${_line}"
        (( _marker_total += 1 ))
      done <<< "$_matches"
    fi
  done
  if (( _marker_total > 0 )); then
    echo ""
    echo "Validate output: ${_marker_total} unresolved marker(s) found in ${_files_with_markers} file(s)" >&2
    exit 1
  else
    echo "Validate output: clean"
  fi
fi

# --- Summary ---
echo ""
if [[ "$DRY_RUN" == "true" ]]; then
  echo "Done. ${#CREATED_FILES[@]} file(s) would be created."
else
  echo "Done. ${#CREATED_FILES[@]} file(s) created."
fi

if (( ${#CREATED_FILES[@]} > 0 )) && [[ "$DRY_RUN" != "true" ]]; then
  echo ""
  echo "Next steps:"
  echo "  1. Verify generated files look correct"
  echo "  2. Continue with framework setup steps (Step 2+)"
  echo "  3. Remove .discovery-context.json after setup is complete"
fi
