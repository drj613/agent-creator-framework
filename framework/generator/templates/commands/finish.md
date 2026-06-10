---
description: Finish a development branch — verify tests, then merge{{#if discovery.features.github_flow}}/PR{{/if}}/keep/discard with worktree cleanup
argument-hint: ""
---

# Finish Branch

Complete the current development branch by verifying tests and executing the chosen completion option.

## Workflow

### 1. Verify Tests

Run the full test suite:

```bash
{{discovery.test_runner.cmd}}
```

If any tests fail, stop and report the failures. Do NOT proceed to Step 2 until all tests pass.

### 2. Determine Base Branch

Find the base branch this feature branch was created from (use the repository's default branch as the default base):

```bash
git merge-base --fork-point <default-branch> HEAD 2>/dev/null || git merge-base <default-branch> HEAD
```

If the branch appears to have diverged from a different base, ask the user to confirm.

### 3. Present Options

Present exactly these 4 options — no elaboration, keep it concise:

```
Tests pass. What would you like to do?

1. Merge back to <base-branch> locally
{{#if discovery.features.github_flow}}2. Flip draft PR to ready-for-review
{{/if}}3. Keep the branch as-is (I'll handle it later)
4. Discard this work
```

Wait for the user's choice before proceeding.

### 4. Execute Choice

#### Option 1: Merge Locally

```bash
git checkout <base-branch>
git pull
git merge <feature-branch>
{{discovery.test_runner.cmd}}   # verify tests on merged result
git branch -d <feature-branch>
```

If tests fail after merge, stop and report. Do not delete the feature branch until tests pass on the merged result.

Then: clean up worktree (Step 5).

{{#if discovery.features.github_flow}}
#### Option 2: Flip Draft PR to Ready-for-Review

Find the PR for the current branch:
```bash
gh pr view --json number,isDraft
```

If no PR is found: tell the user "No draft PR found — run `/ship` first to open a draft PR" and stop.

If a PR exists but `isDraft` is false: tell the user "PR #<number> is already marked ready-for-review" and stop.

If a PR exists and `isDraft` is true:
```bash
gh pr ready <pr-number>
```

Report the PR URL to the user.

Then: clean up worktree (Step 5).
{{/if}}

#### Option 3: Keep As-Is

Report: "Keeping branch `<name>`. Worktree at `<path>`."

Do NOT clean up the worktree.

#### Option 4: Discard

Confirm before acting:

```
This will permanently delete:
- Branch: <name>
- Commits: <list recent commits on this branch>
- Worktree at: <path>

Type 'discard' to confirm.
```

Wait for the exact word "discard" before proceeding. If the user says anything else, abort.

```bash
git checkout <base-branch>
git branch -D <feature-branch>
```

Then: clean up worktree (Step 5).

### 5. Clean Up Worktree

For Options 1, 2, and 4 — check if the current working directory is a worktree:

```bash
git worktree list
```

If the feature branch has an associated worktree, remove it:

```bash
git worktree remove <worktree-path>
```

For Option 3, keep the worktree.
