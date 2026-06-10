---
description: Apply findings from a /team_review report — scope selection, builder dispatch{{#if discovery.features.github_flow}}, PR comment{{/if}}
argument-hint: "<path to .reviews/...md report>"
---

# Fix

## Variables

REPORT_PATH: $ARGUMENTS

## Workflow

### 1. Load Report

REPORT_PATH is required. If not provided, stop with:

```
Error: provide a report path — e.g. /fix .reviews/<date>-<branch>.md
```

**Important:** Do not accept raw-pasted review text — `/fix` requires a report file path. Reports are written to `.reviews/` by `/team_review`.

Read the file at REPORT_PATH. If the file has no `## Findings` section, tell the user and stop.

### 2. Parse Dev Decisions

Parse the report's `## Findings` section. For each finding card, read the `Dev Decision:` field. Collect every finding where `Dev Decision: fix`.

A **finding card** is the content between two `### <ID>` headings inside `## Findings`. The `Dev Decision:` and `Chosen option:` fields live in the metadata bullet list at the top of each card — before the `**Finding:**` paragraph. Match them tolerant of:

- markdown list/emphasis markers (`- **Dev Decision:** <value>`)
- surrounding whitespace
- case (`fix`, `Fix`, `FIX` all mean the same)

Do **not** match `Dev Decision: fix` strings that appear inside a card's body prose or code blocks — only the metadata bullet list at the top of each card counts.

If the resulting scope is empty, stop with:

```
No findings marked 'fix' in <REPORT_PATH>.
Annotate via /plannotator-annotate <REPORT_PATH> or edit the Dev Decision fields,
then re-run /fix.
```

For each `fix`-marked finding whose Category is `Clarify`, verify a `Chosen option:` line is present in the finding card. If not, stop with:

```
<ID> is a Clarify finding marked 'fix' but has no Chosen option recorded.
Re-open the report in plannotator and record an option from the Options block,
or change the Dev Decision to 'defer' / 'dismiss'.
```

Questioner (?) and Dismissed (X) findings have no Dev Decision and are skipped silently.

### 3. Confirm Scope

Print the resolved fix list:

```
Fix scope (N findings):
  S1 [Critical / Must Fix] — <summary from Index>
  ...

Proceed? (yes to continue)
```

Wait for confirmation before continuing.

### 4. Dispatch Builder

Deploy the builder agent (subagent_type: builder) with:

- The full finding cards for each selected ID, parsed verbatim from the `## Findings` section of the report
- Explicit scope restriction: "Only modify files mentioned in these finding cards. Do not touch any other files."
- Instruction to run `{{discovery.test_runner.cmd}}` and the project's lint command after each fix
- Tell the builder to make a single atomic commit for all fixes in the scope, rather than one commit per finding. This ensures a single SHA can be stamped on all resolution entries in Step 5.
- If the builder reports that a fix breaks tests, it should skip that finding (mark it `❌` in Resolutions with the test failure reason) and continue to the next finding in scope rather than aborting the entire run.

### 5. Append Resolutions to Report

After the builder completes, get the current short SHA (`git rev-parse --short HEAD`).

Append a `## Resolutions` section to the report file. One line per finding in the fix scope:

- `✅` — fix applied successfully
- `⏭` — deferred (explain why)
- `❌` — failed (explain why)

```markdown
## Resolutions

- S1 ✅ <sha> — <one-line description of what changed>
- R1 ⏭ deferred — <reason>
- H2 ❌ failed — <reason>
```

The Resolutions edit is local-only bookkeeping — it is **not** committed by `/fix`. {{#if discovery.features.github_flow}}The PR comment in Step 6 carries the same data to the PR. {{/if}}If you want the Resolutions persisted in git, stage and commit it manually after `/fix` returns.

{{#if discovery.features.github_flow}}
### 5.5. Auto-Push

The push happens before Step 6 so that the commit SHAs referenced in PR comments are reachable on the remote by the time the comments post.

If a PR exists for the current branch (`gh pr view --json number 2>/dev/null` succeeds), push:

```bash
git push
```

This also triggers any automated PR reviewer to re-review the fix.

If `git push` fails (non-fast-forward, auth, hook), stop the workflow — do NOT continue to Step 6. Local state at this point: the builder's atomic commit exists, the Resolutions section has been appended (uncommitted), but the PR has not been notified. Recover manually:
- Resolve the upstream divergence (`git pull --rebase`, or `git push --force-with-lease` if the upstream was intentionally rewritten).
- Once pushed, post the summary comment yourself: `gh pr comment <pr-number> --body-file <REPORT_PATH>`.
- Do **not** re-run `/fix` on this report — it would re-append the Resolutions section and re-dispatch the builder against the same fix scope.

### 6. Post PR Comments

Find the PR number (`gh pr view --json number -q .number`). If no PR is found, skip the rest of Step 6 and note 'No PR found — skipping comment' in the Step 7 results output.

#### 6a. Inline replies to PR review comments

For each finding in the fix scope whose card carries a `PR comment ID:` field, post a reply **directly on that comment's thread** so the resolution is visible inline next to the original comment:

```bash
gh api repos/{owner}/{repo}/pulls/<pr-number>/comments/<comment-id>/replies \
  -f body="**Resolution:** ✅ Fixed in <sha>. <one-line description>"
```

For deferred (`⏭`) or failed (`❌`) findings that map to a PR comment, still post a reply so the thread is resolved from our side — use `⏭ Deferred — <reason>` or `❌ Could not fix — <reason>` as the body.

If a reply call fails (e.g. 404 — comment was resolved or deleted upstream), log it and continue; do not abort the rest of Step 6.

#### 6b. Summary comment

Post a **new** comment every time — do not check for or update an existing one. Each `/fix` run produces its own comment so the full history of review rounds is preserved on the PR.

Build the comment body from the report: the Index table verbatim, then each fix-scope finding card followed immediately by its resolution line (Dismissed and Questioner findings are excluded). Post with `gh pr comment <pr-number> --body-file <tmp-file>`.
{{/if}}

### 7. Report Results

```
## Fix Results

Applied:
- S1: <what changed> (<file path>)

Deferred:
- A1: <reason>

Failed:
- H2: <reason>

Report updated: <REPORT_PATH>
{{#if discovery.features.github_flow}}PR comment: <url>
{{/if}}Tests: X/X passed

Next: /finish
```
