#!/usr/bin/env bash
# Usage: wait-for-copilot.sh <pr-number> [timeout-seconds]
# Exits 0 when a review from github-copilot[bot] appears on the PR; exits 1 on timeout.

set -euo pipefail
pr="${1:?pr number required}"
timeout="${2:-480}"  # 8 min default
interval=30
elapsed=0

while (( elapsed < timeout )); do
  reviews=$(gh api "repos/{owner}/{repo}/pulls/${pr}/reviews" --jq '.[].user.login' 2>/dev/null || true)
  if echo "$reviews" | grep -Eq 'copilot|Copilot'; then
    echo "copilot-review-ready"
    exit 0
  fi
  sleep "$interval"
  elapsed=$((elapsed + interval))
done

echo "copilot-review-timeout"
exit 1
