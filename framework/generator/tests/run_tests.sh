#!/usr/bin/env bash
# run_tests.sh — Sources every test_*.sh in the same directory and prints a
#                summary of pass/fail counts.
# Usage: bash framework/generator/tests/run_tests.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------------------------------------------------------------------------
# Global counters — sourced test files increment these.
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0
FAIL_MESSAGES=()

# ---------------------------------------------------------------------------
# Shared helpers (available to every sourced test file).
# ---------------------------------------------------------------------------
pass() {
  local name="$1"
  PASS_COUNT=$(( PASS_COUNT + 1 ))
  printf '  PASS  %s\n' "$name"
}

fail() {
  local name="$1"
  local reason="${2:-}"
  FAIL_COUNT=$(( FAIL_COUNT + 1 ))
  FAIL_MESSAGES+=("$name${reason:+: $reason}")
  printf '  FAIL  %s%s\n' "$name" "${reason:+: $reason}"
}

# ---------------------------------------------------------------------------
# Collect test files.
# ---------------------------------------------------------------------------
TEST_FILES=()
for f in "$TESTS_DIR"/test_*.sh; do
  [[ -f "$f" ]] && TEST_FILES+=("$f")
done

if (( ${#TEST_FILES[@]} == 0 )); then
  echo "No test files found in $TESTS_DIR" >&2
  exit 1
fi

OVERALL_EXIT=0

for test_file in "${TEST_FILES[@]}"; do
  echo ""
  echo "--- $(basename "$test_file") ---"
  # Each test file is sourced so that the pass/fail helpers and global
  # counters are shared within the same shell process.
  # shellcheck disable=SC1090
  source "$test_file"
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
TOTAL=$(( PASS_COUNT + FAIL_COUNT ))
echo ""
echo "========================================"
printf 'Results: %d passed, %d failed  (%d total)\n' \
  "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
echo "========================================"

if (( FAIL_COUNT > 0 )); then
  echo ""
  echo "Failures:"
  for msg in "${FAIL_MESSAGES[@]}"; do
    echo "  FAIL  $msg"
  done
  OVERALL_EXIT=1
fi

exit $OVERALL_EXIT
