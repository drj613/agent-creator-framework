---
description: Archive the plan, commit, push{{#if discovery.features.github_flow}}, and open a draft PR{{/if}}
argument-hint: "[plan-path]"
---

# Ship

## Variables

PLAN_PATH: $ARGUMENTS

## Workflow

### 1. Resolve Plan

If PLAN_PATH is provided, verify the file exists at that path under `specs/` (and is NOT inside `specs/archive/`). If the file is missing or already archived, stop with a clear error.

If PLAN_PATH is empty, list files in `specs/` excluding `specs/archive/`:

```bash
find specs -maxdepth 1 -name '*.md' -type f 2>/dev/null
```

- If exactly one plan, use it.
- If multiple, print the list and prompt the user to pick one.
- If none, stop with: `No plan to ship. Nothing in specs/ outside archive/.`

### 2. Verify Tests

Run the full test suite:

```bash
{{discovery.test_runner.cmd}}
```

If any test fails, stop and report the failures. Do NOT proceed.

{{#if discovery.features.beads_tickets}}
### 3. Beads Check (Warn-Only)

Parse the resolved plan's `## Beads Tickets` table. If the plan has no such section, skip this step.

For each ticket ID listed in the table, run:

```bash
br show <ticket-id>
```

Collect any tickets whose status is not `closed`. If the list is non-empty, print:

```
Some Beads tickets for this plan are still open:
  <ticket-id> [status] — <title>
  ...

Continue anyway? (yes)
```

Wait for confirmation. Do not block — proceed on "yes."

If `br show` errors for a particular ticket (missing, network failure, malformed ID), treat that ticket as `unknown` and include it in the warning list. Do not abort the workflow on a single `br show` failure — this is a warn-only step.
{{/if}}

### 4. Archive the Plan

```bash
mkdir -p specs/archive
git mv <PLAN_PATH> specs/archive/<basename>
```

Where `<basename>` is the filename (e.g. `my-feature.md`).

### 5. Commit if Dirty

Check the working tree:

```bash
git status --porcelain
```

If the output is non-empty, commit the staged move (and any other intentionally-staged changes) with:

```bash
git commit -m "chore: ship <plan-name> — archive plan"
```

Where `<plan-name>` is the basename without the `.md` extension.

Do NOT use `git add -A`. The plan move from Step 4 is already staged by `git mv`. If the user wants to ship other tracked changes, they must have staged them before invoking `/ship`.

After the commit succeeds, run `git status --porcelain` again. If the output contains any tracked modified or deleted files (ignore untracked `??` lines), stop with:

```
Working tree still has unstaged tracked changes after commit:
  <git status output>

Stage them manually and re-run /ship, or stash them if they should not be included.
```

### 6. Push

Check if the current branch has an upstream:

```bash
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null
```

If no upstream exists: `git push -u origin <current-branch>`. Otherwise: `git push`.

If push is rejected (non-fast-forward, auth failure, hook failure), stop and surface the error. The user should resolve the underlying issue (`git pull --rebase`, fix auth, etc.) and re-run `/ship`.

{{#if discovery.features.github_flow}}
### 7. Open Draft PR

Detect an existing PR:

```bash
gh pr view --json number,url,isDraft 2>/dev/null
```

If a PR exists, capture its number, URL, and `isDraft` state, then skip creation.

If no PR exists, create one. Derive the title from the plan filename (kebab-case → Title Case). Derive the body from the plan's Objective and Solution Approach sections:

```bash
gh pr create --draft --title "<title>" --body "$(cat <<'EOF'
## Summary
<2–3 bullets from the plan's Objective and Solution Approach>

## Test Plan
- [ ] Run /team_review on the PR
- [ ] Address Dev Decision fix-marked findings via /fix
EOF
)"
```

Capture the PR number and URL from the create output.

{{/if}}

### 8. Report

{{#if discovery.features.github_flow}}
`<state>` is `draft` if `isDraft` is true (or the PR was just created with `--draft`), otherwise `ready`.

```
Shipped: <plan-name>
Plan archived: specs/archive/<plan-name>.md
PR: <pr-url> (<state>)

Next: /team_review
```
{{/if}}

If there is no PR flow, report the archived plan path and pushed branch instead of a PR line.
