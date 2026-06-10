#!/usr/bin/env bash
# test_generate.sh — Integration tests for generate.sh --dry-run.
# Sourced by run_tests.sh.

_GENERATOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_GENERATE="$_GENERATOR_ROOT/generate.sh"

# Minimal valid single-package discovery JSON
_BASE_JSON='{
  "agent_dir": ".claude",
  "context_filename": "CLAUDE.md",
  "context_file_location": "inside_agent_dir",
  "project_type": "single_package",
  "primary_language": "typescript",
  "app_description": "Test app for generator integration tests",
  "models": { "complex": "claude-opus-4-6", "standard": "claude-sonnet-4-6", "simple": "claude-haiku-4-5-20251001" },
  "test_runner": { "name": "vitest", "cmd": "pnpm vitest run" },
  "linters": [{ "name": "eslint", "cmd": "eslint src", "language": "typescript", "file_extensions": [".ts",".tsx"] }],
  "type_checkers": [{ "name": "tsc", "cmd": "tsc --noEmit", "language": "typescript", "file_extensions": [".ts",".tsx"] }],
  "package_managers": [{ "name": "pnpm", "install_cmd": "pnpm install" }],
  "dev_servers": {},
  "directories": { "project_root": "/tmp/gen-test-single" },
  "features": {
    "dev_command": false,
    "plan_build": false,
    "review": false,
    "verify_browser": false,
    "test": true,
    "audit_docs": false,
    "documentation_structure": false,
    "commit_workflow": true,
    "onboarding_skill": false,
    "post_tool_use_hooks": true
  },
  "env_files": { "found": [], "example_exists": false },
  "languages": ["typescript"]
}'

# Monorepo fixture
_MONOREPO_JSON='{
  "agent_dir": ".claude",
  "context_filename": "CLAUDE.md",
  "context_file_location": "inside_agent_dir",
  "project_type": "monorepo",
  "primary_language": "typescript",
  "app_description": "Monorepo test app",
  "models": { "complex": "claude-opus-4-6", "standard": "claude-sonnet-4-6", "simple": "claude-haiku-4-5-20251001" },
  "test_runner": { "name": "vitest", "cmd": "pnpm vitest run" },
  "linters": [{ "name": "eslint", "cmd": "eslint src", "language": "typescript", "file_extensions": [".ts"] }],
  "type_checkers": [{ "name": "tsc", "cmd": "tsc --noEmit", "language": "typescript", "file_extensions": [".ts"] }],
  "package_managers": [{ "name": "pnpm", "install_cmd": "pnpm install" }],
  "dev_servers": {},
  "directories": { "project_root": "/tmp/gen-test-mono" },
  "workspaces": [
    { "name": "api", "path": "packages/api", "language": "typescript", "test_runner": { "cmd": "pnpm vitest run" } },
    { "name": "web", "path": "packages/web", "language": "typescript", "test_runner": { "cmd": "pnpm vitest run" } }
  ],
  "features": {
    "dev_command": false,
    "plan_build": true,
    "review": false,
    "verify_browser": false,
    "test": true,
    "audit_docs": true,
    "documentation_structure": true,
    "commit_workflow": true,
    "onboarding_skill": false,
    "post_tool_use_hooks": true
  },
  "env_files": { "found": [], "example_exists": false },
  "languages": ["typescript"]
}'

# Wrap tests in a function so that `trap RETURN` fires correctly on exit.
_run_generate_tests() {
  local _tmpdir
  _tmpdir="$(mktemp -d /tmp/gen-test.XXXXXX)"
  # Expand $_tmpdir now (double quotes) so the trap string holds the literal path.
  # This avoids a bash -u "unbound variable" error when locals are popped on RETURN.
  # shellcheck disable=SC2064
  trap "rm -rf '${_tmpdir}'" RETURN

  local _fixture="$_tmpdir/single.json"
  printf '%s\n' "$_BASE_JSON" > "$_fixture"

  # Test: dry-run exits 0 for valid single-package JSON
  if bash "$_GENERATE" "$_fixture" --dry-run > "$_tmpdir/out.txt" 2>&1; then
    pass "generate: dry-run succeeds for single-package project"
  else
    fail "generate: dry-run succeeds for single-package project" "$(tail -5 "$_tmpdir/out.txt")"
  fi

  # Test: dry-run output mentions expected paths
  if grep -q "\.claude/" "$_tmpdir/out.txt" 2>/dev/null; then
    pass "generate: dry-run output lists .claude/ paths"
  else
    fail "generate: dry-run output lists .claude/ paths" "no .claude/ found in output"
  fi

  # Test: audit_docs=false does not generate audit-docs scripts
  if ! grep -q "audit-docs" "$_tmpdir/out.txt" 2>/dev/null; then
    pass "generate: audit_docs=false does not generate audit-docs scripts"
  else
    fail "generate: audit_docs=false does not generate audit-docs scripts" "found audit-docs in output"
  fi

  # Test: dry-run exits 0 for valid monorepo JSON
  local _mono_fixture="$_tmpdir/mono.json"
  printf '%s\n' "$_MONOREPO_JSON" > "$_mono_fixture"

  if bash "$_GENERATE" "$_mono_fixture" --dry-run > "$_tmpdir/mono-out.txt" 2>&1; then
    pass "generate: dry-run succeeds for monorepo project"
  else
    fail "generate: dry-run succeeds for monorepo project" "$(tail -5 "$_tmpdir/mono-out.txt")"
  fi

  # Test: audit_docs=true generates audit-docs scripts
  if grep -q "audit-docs" "$_tmpdir/mono-out.txt" 2>/dev/null; then
    pass "generate: audit_docs=true generates audit-docs scripts"
  else
    fail "generate: audit_docs=true generates audit-docs scripts" "no audit-docs in mono output"
  fi

  # Test: invalid JSON causes non-zero exit
  printf '%s\n' '{"agent_dir": ".claude"}' > "$_tmpdir/invalid.json"
  if bash "$_GENERATE" "$_tmpdir/invalid.json" --dry-run > /dev/null 2>&1; then
    fail "generate: rejects incomplete discovery JSON" "should have exited non-zero"
  else
    pass "generate: rejects incomplete discovery JSON"
  fi

  # Test: missing file arg shows usage
  local _usage_out
  _usage_out="$(bash "$_GENERATE" 2>&1 || true)"
  if echo "$_usage_out" | grep -q "Usage:"; then
    pass "generate: shows usage when no args given"
  else
    fail "generate: shows usage when no args given" "output: $_usage_out"
  fi

  # Test: nonexistent file arg shows error
  local _err_out
  _err_out="$(bash "$_GENERATE" "/nonexistent/path.json" 2>&1 || true)"
  if echo "$_err_out" | grep -q "ERROR"; then
    pass "generate: errors on nonexistent file"
  else
    fail "generate: errors on nonexistent file" "output: $_err_out"
  fi
}
_run_generate_tests
