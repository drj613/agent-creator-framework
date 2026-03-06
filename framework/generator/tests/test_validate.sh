#!/usr/bin/env bash
# test_validate.sh — Unit tests for lib/validate.sh schema validation.
# Sourced by run_tests.sh.

_GENERATOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Minimal valid discovery JSON fixture
_VALID_JSON='{
  "platform": "claude-code",
  "agent_dir": ".claude",
  "context_filename": "CLAUDE.md",
  "context_file_location": "inside_agent_dir",
  "project_type": "single_package",
  "primary_language": "typescript",
  "app_description": "TaskFlow — task management REST API",
  "models": { "complex": "claude-opus-4-6", "standard": "claude-sonnet-4-6", "simple": "claude-haiku-4-5-20251001" },
  "test_runner": { "name": "vitest", "cmd": "pnpm vitest run" },
  "linters": [{ "name": "eslint", "cmd": "eslint src", "language": "typescript", "file_extensions": [".ts",".tsx"] }],
  "type_checkers": [{ "name": "tsc", "cmd": "tsc --noEmit", "language": "typescript", "file_extensions": [".ts",".tsx"] }],
  "package_managers": [{ "name": "pnpm", "install_cmd": "pnpm install" }],
  "dev_servers": {},
  "directories": { "project_root": "/tmp/test-project" },
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

# Helper: run validate against a JSON string, return exit code
_run_validate() {
  local json="$1"
  (
    DISCOVERY_JSON="$json"
    DRY_RUN="false"
    export DISCOVERY_JSON DRY_RUN
    source "$_GENERATOR_ROOT/lib/helpers.sh"
    source "$_GENERATOR_ROOT/lib/validate.sh"
    validate_discovery_json
  ) 2>/dev/null
  return $?
}

# Test: valid JSON passes
if _run_validate "$_VALID_JSON"; then
  pass "validate: accepts valid discovery JSON"
else
  fail "validate: accepts valid discovery JSON" "returned non-zero for valid input"
fi

# Test: missing .platform fails
_json_no_platform="$(echo "$_VALID_JSON" | jq 'del(.platform)')"
if _run_validate "$_json_no_platform"; then
  fail "validate: rejects missing .platform" "should have failed but passed"
else
  pass "validate: rejects missing .platform"
fi

# Test: missing .test_runner.cmd fails
_json_no_cmd="$(echo "$_VALID_JSON" | jq 'del(.test_runner.cmd)')"
if _run_validate "$_json_no_cmd"; then
  fail "validate: rejects missing .test_runner.cmd" "should have failed but passed"
else
  pass "validate: rejects missing .test_runner.cmd"
fi

# Test: monorepo without workspaces fails
_json_monorepo_no_ws="$(echo "$_VALID_JSON" | jq '.project_type = "monorepo" | .workspaces = []')"
if _run_validate "$_json_monorepo_no_ws"; then
  fail "validate: rejects monorepo without workspaces" "should have failed but passed"
else
  pass "validate: rejects monorepo without workspaces"
fi

# Test: audit_docs=true without documentation_structure fails
_json_audit_no_docs="$(echo "$_VALID_JSON" | jq '.features.audit_docs = true | .features.documentation_structure = false')"
if _run_validate "$_json_audit_no_docs"; then
  fail "validate: rejects audit_docs without documentation_structure" "should have failed but passed"
else
  pass "validate: rejects audit_docs without documentation_structure"
fi

# Test: linters as null (not array) fails
_json_null_linters="$(echo "$_VALID_JSON" | jq '.linters = null')"
if _run_validate "$_json_null_linters"; then
  fail "validate: rejects linters=null" "should have failed but passed"
else
  pass "validate: rejects linters=null"
fi

# Test: linter with disallowed cmd prefix fails
_json_bad_cmd="$(echo "$_VALID_JSON" | jq '.linters[0].cmd = "rm -rf src"')"
if _run_validate "$_json_bad_cmd"; then
  fail "validate: rejects linter with disallowed cmd prefix" "should have failed but passed"
else
  pass "validate: rejects linter with disallowed cmd prefix"
fi

# Test: hooks=true with no linters or type_checkers fails
_json_hooks_no_tools="$(echo "$_VALID_JSON" | jq '.features.post_tool_use_hooks = true | .linters = [] | .type_checkers = []')"
if _run_validate "$_json_hooks_no_tools"; then
  fail "validate: rejects hooks=true with no linters/type_checkers" "should have failed but passed"
else
  pass "validate: rejects hooks=true with no linters/type_checkers"
fi

# Test: shell metacharacter in cmd is rejected
_json_cmd_metachar="$(echo "$_VALID_JSON" | jq '.linters[0].cmd = "pnpm eslint; rm -rf /"')"
if _run_validate "$_json_cmd_metachar"; then
  fail "validate: rejects cmd with shell metacharacter" "should have failed but passed"
else
  pass "validate: rejects cmd with shell metacharacter"
fi

# Test: tool name with special chars is rejected
_json_bad_name="$(echo "$_VALID_JSON" | jq '.linters[0].name = "my linter!"')"
if _run_validate "$_json_bad_name"; then
  fail "validate: rejects tool name with special characters" "should have failed but passed"
else
  pass "validate: rejects tool name with special characters"
fi

# Test: empty file_extensions array is rejected
_json_empty_exts="$(echo "$_VALID_JSON" | jq '.linters[0].file_extensions = []')"
if _run_validate "$_json_empty_exts"; then
  fail "validate: rejects empty file_extensions array" "should have failed but passed"
else
  pass "validate: rejects empty file_extensions array"
fi

# Test: agent_dir with path traversal is rejected
_json_bad_agent_dir="$(echo "$_VALID_JSON" | jq '.agent_dir = "../../etc"')"
if _run_validate "$_json_bad_agent_dir"; then
  fail "validate: rejects agent_dir with path traversal" "should have failed but passed"
else
  pass "validate: rejects agent_dir with path traversal"
fi

# Test: workspace path with shell metacharacter is rejected (monorepo fixture)
_json_ws_bad_path="$(echo "$_VALID_JSON" | jq '
  .project_type = "monorepo" |
  .workspaces = [{"name": "api", "path": "packages/api; rm -rf /", "language": "typescript"}]
')"
if _run_validate "$_json_ws_bad_path"; then
  fail "validate: rejects workspace path with shell metacharacter" "should have failed but passed"
else
  pass "validate: rejects workspace path with shell metacharacter"
fi

# Test: dangerous flag in node cmd is rejected
_json_node_e="$(echo "$_VALID_JSON" | jq '.linters[0].cmd = "node -e '\''console.log(1)'\''"')"
if _run_validate "$_json_node_e"; then
  fail "validate: rejects node cmd with -e flag" "should have failed but passed"
else
  pass "validate: rejects node cmd with -e flag"
fi

# Test: workspace path with path traversal is rejected
_json_ws_traversal="$(echo "$_VALID_JSON" | jq '
  .project_type = "monorepo" |
  .workspaces = [{"name":"api","path":"../etc/passwd","language":"typescript","test_runner":{"cmd":"pnpm test","name":"vitest"}}]
')"
if _run_validate "$_json_ws_traversal"; then
  fail "validate: rejects workspace path with path traversal" "should have failed but passed"
else
  pass "validate: rejects workspace path with path traversal"
fi

# Test: missing .app_description is rejected
_json_no_app="$(echo "$_VALID_JSON" | jq 'del(.app_description)')"
if _run_validate "$_json_no_app"; then
  fail "validate: rejects missing .app_description" "should have failed but passed"
else
  pass "validate: rejects missing .app_description"
fi

# Test: --flag=value form of dangerous flag is rejected
_json_require_eq="$(echo "$_VALID_JSON" | jq '.linters[0].cmd = "node --require=./evil.js"')"
if _run_validate "$_json_require_eq"; then
  fail "validate: rejects --flag=value form of dangerous flag" "should have failed but passed"
else
  pass "validate: rejects --flag=value form of dangerous flag"
fi
