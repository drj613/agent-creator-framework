#!/usr/bin/env bash
# test_syntax.sh — Verify all generator .sh files have valid bash syntax.
# Sourced by run_tests.sh.

_GENERATOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

_sh_files=(
  "$_GENERATOR_ROOT/generate.sh"
  "$_GENERATOR_ROOT/lib/helpers.sh"
  "$_GENERATOR_ROOT/lib/validate.sh"
  "$_GENERATOR_ROOT/generators/agents.sh"
  "$_GENERATOR_ROOT/generators/hooks.sh"
  "$_GENERATOR_ROOT/generators/validators.sh"
  "$_GENERATOR_ROOT/generators/gitignore.sh"
  "$_GENERATOR_ROOT/tests/run_tests.sh"
)

for _f in "${_sh_files[@]}"; do
  _name="syntax: $(basename "$_f")"
  if [[ ! -f "$_f" ]]; then
    fail "$_name" "file not found: $_f"
  elif bash -n "$_f" 2>/dev/null; then
    pass "$_name"
  else
    fail "$_name" "$(bash -n "$_f" 2>&1 | head -3)"
  fi
done
