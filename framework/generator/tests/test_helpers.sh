#!/usr/bin/env bash
# test_helpers.sh — Unit tests for lib/helpers.sh functions.
# Sourced by run_tests.sh.

_GENERATOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

_MINIMAL_JSON='{
  "agent_dir": ".claude",
  "context_filename": "CLAUDE.md",
  "directories": { "backend_lang": "python", "frontend_lang": "typescript", "backend_root": "backend", "frontend_root": "frontend" },
  "linters": [{ "file_extensions": [".ts", ".tsx"] }]
}'

# Load helpers with minimal env
_load_helpers() {
  DISCOVERY_JSON="$_MINIMAL_JSON"
  DRY_RUN="${1:-false}"
  export DISCOVERY_JSON DRY_RUN
  CREATED_FILES=()
  source "$_GENERATOR_ROOT/lib/helpers.sh"
}

# Test: write_file in dry-run mode does not create file
(
  _tmpdir="$(mktemp -d /tmp/helpers-test.XXXXXX)"
  trap 'rm -rf "$_tmpdir"' EXIT
  _load_helpers "true"
  write_file "$_tmpdir/should-not-exist.txt" "content"
  if [[ ! -f "$_tmpdir/should-not-exist.txt" ]]; then
    pass "write_file: dry-run does not create file"
  else
    fail "write_file: dry-run does not create file" "file was created"
  fi
)

# Test: write_file in dry-run adds to CREATED_FILES
(
  _load_helpers "true"
  write_file "/tmp/fake/path.txt" "content"
  if [[ "${#CREATED_FILES[@]}" -eq 1 ]]; then
    pass "write_file: dry-run adds to CREATED_FILES"
  else
    fail "write_file: dry-run adds to CREATED_FILES" "CREATED_FILES has ${#CREATED_FILES[@]} entries"
  fi
)

# Test: write_file in normal mode creates file
(
  _tmpdir="$(mktemp -d /tmp/helpers-test.XXXXXX)"
  trap 'rm -rf "$_tmpdir"' EXIT
  _load_helpers "false"
  write_file "$_tmpdir/output.txt" "hello world"
  if [[ -f "$_tmpdir/output.txt" ]]; then
    pass "write_file: normal mode creates file"
  else
    fail "write_file: normal mode creates file" "file not found"
  fi
)

# Test: write_file content is correct
(
  _tmpdir="$(mktemp -d /tmp/helpers-test.XXXXXX)"
  trap 'rm -rf "$_tmpdir"' EXIT
  _load_helpers "false"
  write_file "$_tmpdir/out.txt" "expected content"
  _got="$(cat "$_tmpdir/out.txt")"
  if [[ "$_got" == "expected content" ]]; then
    pass "write_file: written content matches"
  else
    fail "write_file: written content matches" "got: $_got"
  fi
)

# Test: write_executable sets +x
(
  _tmpdir="$(mktemp -d /tmp/helpers-test.XXXXXX)"
  trap 'rm -rf "$_tmpdir"' EXIT
  _load_helpers "false"
  write_executable "$_tmpdir/script.sh" "#!/bin/bash\necho hi"
  if [[ -x "$_tmpdir/script.sh" ]]; then
    pass "write_executable: sets executable bit"
  else
    fail "write_executable: sets executable bit" "file not executable"
  fi
)

# Test: compute_fallback_depth
(
  _load_helpers "false"
  _result="$(compute_fallback_depth ".claude" "hooks/validators")"
  if [[ "$_result" == "../../.." ]]; then
    pass "compute_fallback_depth: .claude/hooks/validators -> ../../.."
  else
    fail "compute_fallback_depth: .claude/hooks/validators -> ../../.." "got: $_result"
  fi
)

# Test: compute_fallback_depth — 1-level agent_dir
(
  _load_helpers "false"
  _result="$(compute_fallback_depth "agents" "hooks")"
  if [[ "$_result" == "../.." ]]; then
    pass "compute_fallback_depth: agents/hooks -> ../.."
  else
    fail "compute_fallback_depth: agents/hooks -> ../.." "got: $_result"
  fi
)

# Test: compute_fallback_depth — 2-level agent_dir
(
  _load_helpers "false"
  _result="$(compute_fallback_depth "config/agents" "hooks/validators")"
  if [[ "$_result" == "../../../.." ]]; then
    pass "compute_fallback_depth: config/agents/hooks/validators -> ../../../.."
  else
    fail "compute_fallback_depth: config/agents/hooks/validators -> ../../../.." "got: $_result"
  fi
)

# Test: compute_fallback_depth — hooks subpath (1-level agent_dir)
(
  _load_helpers "false"
  _result="$(compute_fallback_depth ".claude" "hooks")"
  if [[ "$_result" == "../.." ]]; then
    pass "compute_fallback_depth: .claude/hooks -> ../.."
  else
    fail "compute_fallback_depth: .claude/hooks -> ../.." "got: $_result"
  fi
)

# Test: compute_fallback_depth — hooks subpath (2-level agent_dir)
(
  _load_helpers "false"
  _result="$(compute_fallback_depth "config/agents" "hooks")"
  if [[ "$_result" == "../../.." ]]; then
    pass "compute_fallback_depth: config/agents/hooks -> ../../.."
  else
    fail "compute_fallback_depth: config/agents/hooks -> ../../.." "got: $_result"
  fi
)

# Test: resolve_target_dir backend
(
  _load_helpers "false"
  _result="$(resolve_target_dir "python")"
  if [[ "$_result" == "backend" ]]; then
    pass "resolve_target_dir: python -> backend"
  else
    fail "resolve_target_dir: python -> backend" "got: $_result"
  fi
)

# Test: resolve_target_dir frontend
(
  _load_helpers "false"
  _result="$(resolve_target_dir "typescript")"
  if [[ "$_result" == "frontend" ]]; then
    pass "resolve_target_dir: typescript -> frontend"
  else
    fail "resolve_target_dir: typescript -> frontend" "got: $_result"
  fi
)
