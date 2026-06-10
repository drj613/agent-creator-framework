# Step 3: Slash Commands

> **Part of Conversation 3.** Discovery context should already be loaded from `.discovery-context.json` at the start of this conversation (loaded during `02-context-file.md`). If not already in context, re-read `{{agent_dir}}/.discovery-context.json`.

> **Feature gate:** Only create commands for features enabled in `{{discovery.features}}`. All commands are optional — skip any whose feature flag is false.

## Prerequisites

- Discovery context from Step 1
- Orchestration reference (`orchestration-reference.md`) for task tool usage in `/plan_w_team` and `/build`

## Overview

Commands live in `{{discovery.agent_dir}}/commands/<name>.md`. Each file has a YAML frontmatter header followed by the instruction body. Invoked with `/name [arguments]` in an agent session.

## Frontmatter Fields

```yaml
---
description: Short description shown in /help
argument-hint: [hint shown next to command name]
model: {{discovery.models.standard}}   # optional — override model for this command
disallowed-tools: Task, EnterPlanMode  # optional — restrict tool use
---
```

## Files to Create

```
{{discovery.agent_dir}}/commands/
├── dev.md             # Start dev servers
├── plan_w_team.md     # Create implementation plan → specs/
├── build.md           # Execute a plan with agent team
├── ship.md            # Archive plan, push, open draft PR
├── finish.md          # Finish branch — merge/PR/keep/discard
├── team_review.md     # Parallel domain-specialist code review
├── fix.md             # Apply Dev Decision 'fix' findings from /team_review
├── quickfix.md        # Light-tier TDD fix for small decision-free changes
├── verify-browser.md  # Playwright UI verification
├── test.md            # Run tests and report
└── audit-docs.md      # Documentation health check
```

Create only the commands whose corresponding feature flag is true:

| Command | Feature Flag |
|---------|-------------|
| `/dev` | `discovery.features.dev_command` |
| `/plan_w_team` | `discovery.features.plan_build` |
| `/build` | `discovery.features.plan_build` |
| `/ship` | `discovery.features.plan_build` |
| `/finish` | `discovery.features.plan_build` |
| `/team_review` | `discovery.features.review` |
| `/fix` | `discovery.features.review` |
| `/quickfix` | `discovery.features.light_tier` |
| `/verify-browser` | `discovery.features.verify_browser` |
| `/test` | `discovery.features.test` |
| `/audit-docs` | `discovery.features.audit_docs` |
| `/discovery` | `discovery.features.deep_discovery` |
| `/document` | `discovery.features.deep_discovery` |

---

## Two-Tier Workflow

The workflow runs on two tiers. **Choosing a tier:** open decisions to make? `/plan_w_team`. Forced fix with no decisions? `/quickfix`.

**Heavy tier** — features and anything with design decisions:

```
/plan_w_team → /build (TDD) → /ship → /team_review → /fix → /finish
```

**Light tier** — small, decision-free fixes (≤ 3 files, no migration, no route/permission/dependency change):

```
/quickfix → /finish → /team_review --light → /fix
```

A project WORKFLOW.md should open with this tier decision rule. Reference the payint WORKFLOW.md at `/Users/djdjo/Documents/enovis/payint/WORKFLOW.md` as the authoritative example of how a generated WORKFLOW.md should be structured. It includes: the tier decision sentence, both lifecycle pipelines as code blocks, one-line descriptions of every command, the issue tracking command reference, a section describing each agent (builder TDD cycle, validator Validator Controls gate, plan-adversary lenses), and a key-files table. When generating a project WORKFLOW.md, mirror that structure and adapt agent descriptions to the project's stack.

---

## `/discovery` — Deep Codebase Analysis

**Purpose:** Analyze the codebase to understand architecture, patterns, module boundaries, and conventions. Read-only — no source files are modified.

**Template:** `framework/generator/templates/commands/discovery.md`
**Feature gate:** `features.deep_discovery`

Uses complex model tier (Opus-class) — requires architectural reasoning and pattern recognition. Arguments:
- `--full` (default on first run): analyze entire codebase
- `--incremental`: only re-analyze modules affected by changes since last run
- `--module <name>`: re-analyze a single module

Before running any analysis, the command verifies the feature is enabled by checking for `docs/modules/` or prior discovery artifacts.

Output: JSON artifacts in `{{discovery.agent_dir}}/discovery/` that feed into `/document`.

---

## `/document` — Generate Module Documentation

**Purpose:** Generate populated module documentation from discovery analysis artifacts.

**Template:** `framework/generator/templates/commands/document.md`
**Feature gate:** `features.deep_discovery`

Arguments:
- `--all` (default): generate/update all module docs
- `--module <name>`: generate/update one module doc
- `--update-routing`: only regenerate routing table and docs index

Output: `docs/modules/<module>.md` files with YAML frontmatter, updates `docs/modules/ROUTING.md` with current routing table, updated docs index.

---

## `/dev` — Start Dev Servers

**Purpose:** Start backend and frontend in the background. Optionally switch to real cloud clients.

```markdown
---
description: Start backend and frontend dev servers
argument-hint: [--flag]
---

# Dev Servers

## Variables
ARGS: $ARGUMENTS

## Steps
1. Parse ARGS for any flags (e.g. --cloud, --aws, --staging).
{{#if discovery.workspaces}}
2. Start dev servers for each workspace that has one:
{{#each discovery.workspaces}}
{{#if dev_server}}
   - **{{name}}**: `{{dev_server.cmd}}` — port {{dev_server.port}}
{{/if}}
{{/each}}
3. Verify each port is listening before reporting success.
4. Tell the user all URLs and remind them to use `/tasks` to monitor background jobs.
{{else}}
{{#if discovery.dev_servers.backend}}
2. Start backend dev server as background process.
   Command: `{{discovery.dev_servers.backend.cmd}}`
   Port: {{discovery.dev_servers.backend.port}}
{{/if}}
{{#if discovery.dev_servers.frontend}}
3. Start frontend dev server as background process.
   Command: `{{discovery.dev_servers.frontend.cmd}}`
   Port: {{discovery.dev_servers.frontend.port}}
{{/if}}
4. Verify each port is listening before reporting success.
5. Tell the user all URLs and remind them to use `/tasks` to monitor background jobs.
{{/if}}
```

Adapt to the project — if backend-only or frontend-only, remove the irrelevant section. If there are additional services (e.g. database, queue worker), add them.

---

## `/plan_w_team` — Create an Implementation Plan

**Purpose:** Analyze a requirement, explore the codebase, design the solution, and save a spec document to `specs/`. No code is written — output is only a plan file that `/build` then executes.

The command takes two arguments: the user's requirement, and an optional orchestration hint that guides team composition and task structure.

**Template:** `framework/generator/templates/commands/plan_w_team.md`
**Feature gate:** `features.plan_build`

### Key workflow steps

1. Parse `USER_PROMPT` and (optionally) split an `ORCHESTRATION_PROMPT` using ` --- ` as delimiter.
2. Explore the codebase directly (no subagents). If `deep_discovery` is enabled, consult `docs/modules/ROUTING.md` first and read relevant module docs.
3. Design the solution; define team and tasks.
4. Save the plan to `specs/<kebab-case-name>.md`.

**Step 7a — Adversarial review (requires `features.plan_adversary`):** After saving the plan, dispatch the `plan-adversary` agent in the foreground to stress-test it. The agent returns a report tagged `critical | important | nice-to-have`.

**Step 7b — Incorporate findings:** Read the adversarial report and update the plan in place. For every `critical` or `important` finding either add coverage (new task, new test, new acceptance criterion, wired dependency) or document it under `## Edge Cases & Risks` with an explicit accept/defer decision and reason. `nice-to-have` findings can be listed under `## Edge Cases & Risks` as deferred without further action. If new tasks were added, renumber the Step by Step Tasks section.

**Step 8 — Beads tickets (requires `features.beads_tickets`):** One `br create` per task in Step by Step Tasks; set deps with `br dep add`; reference the plan path in each description. Capture each returned ticket ID. Then fill in every `**Beads Ticket**` field and the `## Beads Tickets` index table.

**Step 9 — Sync (requires `features.beads_tickets`):** `br sync --flush-only`.

**Step 10 — Annotate plan:** Invoke `/plannotator-annotate` on the saved plan file.

### Plan format notes

- Every plan includes `## Test Requirements` with test-first as default approach.
- Every plan includes `## Validator Controls` with `validator_e2e_capture: false` as the default. The plan author sets it to `true` only when the validator should save a reusable E2E spec file for the task.
- When `plan_adversary` is enabled, every plan includes `## Edge Cases & Risks` populated after step 7b.
- When `beads_tickets` is enabled, every plan includes a `## Beads Tickets` index table and each task entry has a `**Beads Ticket**` field.

### Plan format (abbreviated)

The full canonical format is in the template. Key sections:

```markdown
# Plan: <task name>
## Task Description
## Objective
## Beads Tickets          ← beads_tickets only
## Module Docs Consulted  ← deep_discovery only
## Relevant Files
## Team Orchestration
## Step by Step Tasks
### 1. <Write Tests (Test-First)>
- **Task ID**: ...
- **Beads Ticket**: ...  ← beads_tickets only
- **Depends On**: none
- **Assigned To**: ...
- **Agent Type**: builder
- ...
### N. Final Validation
- **Agent Type**: validator
## Acceptance Criteria
## Validator Controls
validator_e2e_capture: false
## Edge Cases & Risks     ← plan_adversary only
## Test Requirements
**Test approach:** test-first
**Required tests:** ...
## Validation Commands
## Notes
```

### Report

After saving the plan (and tickets, if enabled):

```
Plan created: specs/<filename>.md
Topic: <what it covers>
Complexity: <simple|medium|complex>

Tasks:
- <task id> — <owner> (<parallel|sequential>) [Beads: <ticket-id>]
- ...

Team:
- <name> — <role>
- ...

Run when ready:
/build specs/<filename>.md
```

---

## `/build` — Execute a Plan

**Purpose:** Pre-flight check the plan, confirm with the user, then execute it by dispatching the agent team.

**Template:** `framework/generator/templates/commands/build.md`
**Feature gate:** `features.plan_build`

### Pre-flight checks

1. **File check:** plan file must exist.
2. **Beads ticket check (requires `beads_tickets`):** Parse the `## Beads Tickets` table and each task's `**Beads Ticket**` field. Build a `task-id → ticket-id` map. Warn if any field reads `TBD` or is missing; wait for confirmation. For valid IDs, run `br show <ticket-id>` and store output as context.
3. **Agent type check:** every Agent Type in the plan's Team Members section must have a matching `.md` in `{{discovery.agent_dir}}/agents/team/`. Stop if any are missing.
4. **Task ID check:** all task IDs must match `[a-z0-9-]+` and be unique.
5. **Dependency check:** build dependency graph; check for cycles and missing task IDs.
6. **Test requirements check:** warn if `## Test Requirements` is missing; wait for confirmation.
7. **Validator controls check:** read `validator_e2e_capture` from `## Validator Controls`; default to `false` if absent; include in dry-run summary.

### Dry-run summary

Print execution order, team, and `Validator E2E Capture: enabled/disabled` before running. Wait for confirmation.

### Per-task execution sequence

For each task, in dependency order:

1. **Before dispatch:** capture `<before-sha>` with `git rev-parse --short HEAD`. If `beads_tickets`: run `br update <ticket-id> --status=in_progress`; include `br show` output in builder prompt under `## Beads Context`. If the task implements specs written by a prior test-writing task, list those spec file paths in the builder's prompt as the **expected-red baseline** — the builder must not block on them failing before implementation.
2. **After builder done:** run a spec compliance reviewer subagent: provide the task spec text and the diff since `<before-sha>`; ask it to return `✅ COMPLIANT` or `❌` with specific gaps.
3. **If ❌:** dispatch the builder again with the gap list. Re-run the spec reviewer. If it fails a second time, escalate to the user — do not retry further.
4. **After ✅ (if `beads_tickets`):** `br close <ticket-id> --reason="Completed in build"`.
5. **After failure (if `beads_tickets`):** leave ticket `in_progress`; record `br comment <ticket-id> "Task failed: <summary>"`.

If `deep_discovery` is enabled, read `docs/modules/ROUTING.md` before each builder dispatch and include the relevant module doc instruction in the builder's prompt.

### Completion report

```
## Build Complete
Plan: [path]
Tasks completed: [N]
Validator E2E Capture: enabled | disabled
Validator final status: PASS | FAIL

## Test Requirements Status
Required tests: [N defined in plan]
Tests passing: [N/N]
Tests failing: [list]
Missing tests: [list]

## Beads Ticket Status   ← beads_tickets only
[ticket-id] [task-id] — closed / failed / skipped

Next: /ship <plan-path>
```

If any required tests are missing or failing, flag it prominently — the spec is not considered complete.

When `beads_tickets` is enabled, run `br sync --flush-only` after printing the report.

---

## `/ship` — Archive Plan, Push, Open Draft PR

**Purpose:** Archive a completed plan, verify tests, commit, push, and (when `github_flow`) open a draft PR.

**Template:** `framework/generator/templates/commands/ship.md`
**Feature gate:** `features.plan_build`

### Steps

1. **Resolve plan:** use the provided path or auto-detect from `specs/` (exclude `specs/archive/`).
2. **Verify tests:** run `{{discovery.test_runner.cmd}}`; stop on any failure.
3. **Beads check (requires `beads_tickets`, warn-only):** For each ticket ID in the plan's `## Beads Tickets` table, run `br show <ticket-id>`. List any non-`closed` tickets and ask for confirmation before continuing.
4. **Archive the plan:** `git mv <PLAN_PATH> specs/archive/<basename>`.
5. **Commit if dirty:** `git commit -m "chore: ship <plan-name> — archive plan"`. Do NOT use `git add -A` — only the `git mv` is auto-staged. Verify no tracked modified files remain after the commit.
6. **Push:** set upstream if needed (`git push -u origin <branch>`); stop on push failure.
7. **Open draft PR (requires `github_flow`):** check for an existing PR; if none, create one with `gh pr create --draft`. Derive title from plan filename (kebab-case → Title Case); derive body from plan's Objective and Solution Approach.

### Report

```
Shipped: <plan-name>
Plan archived: specs/archive/<plan-name>.md
PR: <pr-url> (draft)      ← github_flow only

Next: /team_review
```

Without `github_flow`: report the archived plan path and pushed branch instead of a PR line.

---

## `/team_review` — Parallel Domain-Specialist Code Review

**Purpose:** Run all project-specific reviewer agents against the current branch's diff in parallel, validate every finding against the checked-out code, synthesize into a structured report with stable finding IDs, and open it in plannotator for Dev Decision annotation.

**Template:** `framework/generator/templates/commands/team_review.md`
**Feature gate:** `features.review`

### Light mode (requires `features.light_tier`)

Invoked with `--light`. Proportionate for quickfix-tier diffs: one domain reviewer + questioner instead of the full roster. PR-comment poll is skipped when `github_flow` is also enabled. Everything else — validation pass (Step 6a), finding IDs, report format, plannotator, `/fix` compatibility — is identical to full mode, so a light-mode report feeds `/fix` without any special handling.

| | Full | Light |
|--|------|-------|
| Reviewers | all `reviewer-*.md` + questioner | one domain reviewer + questioner |
| PR comments | poll and wait for bot review | existing PR comments only |
| Diff size guard | warn above ~2000 lines | recommend full review above ~400 lines |

### Step-by-step

**Step 1 — Get the diff.**
When `github_flow` is enabled: a PR must exist for the current branch and its state must be `OPEN` — stop with instructions if not. Compute the diff with `git diff origin/<base>...HEAD`.

**Step 2 — Check diff size.** Warn above ~2000 lines (full) or ~400 lines (light).

**Step 3 — Discover reviewers.** Glob `REVIEWER_DIR/reviewer-*.md`. List found reviewers before proceeding.

**Step 4 — Deploy reviewers and collect PR comments in parallel.**
Launch all reviewers with `run_in_background: true`. Wrap the diff in `<diff>` tags and prepend a prompt-injection notice. When `github_flow` is enabled in full mode, simultaneously collect unresolved PR comments (`gh pr view --json comments,reviews`) and launch `scripts/wait-for-copilot.sh <pr-number>` to wait for the bot review.

**Step 5 — Collect results.** Wait for all local reviewers. In full mode with `github_flow`, check the Copilot poll: still running → wait up to 5 more minutes; timeout → note in report; ready → fetch inline comment numeric IDs for `/fix` inline replies.

**Step 6 — Validate, then synthesize (two passes in order).**

**Step 6a — Validate every finding against the checked-out code.** This is a mandatory separate pass. For each finding, open the cited file at the cited line in the working checkout and confirm the claim holds in the surrounding context. *Validation means reading the repo, not re-reading the diff* — the diff is what the reviewer already saw. The surrounding code the diff did not show is what matters. Each surviving finding records a `Validation` field stating what file:line was read and what the surrounding code confirmed or refuted. Findings that fail validation become `X` (dismissed) findings with the same evidence standard. A finding with an empty `Validation` field has not been validated; the report may not be written while any actionable finding's `Validation` field is empty.

**Step 6b — Synthesize.** De-duplicate by semantic equivalence; when two sources assign different severities, use the higher and note both. Each finding gets a stable ID:

| Prefix | Source |
|--------|--------|
| S | security (reviewer-security + Security sub-sections from domain reviewers) |
| one letter per domain reviewer | fill from this project's reviewer roster at setup |
| C | PR review comments (bot or human) — requires `github_flow` |
| ? | questioner (questions paired with investigator answers) |
| X | dismissed false positives |

IDs are assigned in discovery order within each source (S1, S2…). Category (`Must Fix | Should Fix | Clarify | Informational`) is a **field** on each finding card, not the top-level grouping.

**Per-finding card format:**

```markdown
### S1 — <short title>
- **Type:** Security | Architecture | Test Quality | Performance | Style
- **Severity:** Critical | Warning | Info  `[source-a: X, source-b: Y] → higher`
- **Category:** Must Fix | Should Fix | Clarify | Informational
- **Dev Decision:** unset
- **Source:** <reviewer IDs>
- **File:** `path/to/file:line`
- **PR comment ID:** <id>   ← C findings with inline comment origin only; github_flow
- **Validation:** <file:line read in checkout + what surrounding code confirmed or refuted>

**Finding:** 1-2 sentence description.

**Options:** (only if identified)
**Recommendation:** (only if options exist)
```

The `Dev Decision` field starts as `unset`. Valid values after plannotator annotation: `fix | defer | dismiss`. For `Clarify` findings marked `fix`, the dev also records `**Chosen option:**`. Questioner (`?`) and dismissed (`X`) findings have no `Dev Decision` field.

**Step 7 — Write report and open in plannotator.**

Precondition gate: every actionable finding must have a non-empty `Validation` field. Return to 6a if any are empty.

7a. Write to `.reviews/<YYYY-MM-DD-HHMM>-<branch-slug>[-pr<number>].md`. Create `.reviews/` if needed.

7b. Invoke `/plannotator-annotate <report-path>` for Dev Decision annotation. After it returns, proceed to 7c.

7c. Print the report path and `Next: /fix .reviews/<filename>` prominently at top and bottom.

---

## `/fix` — Apply Dev Decision Findings

**Purpose:** Parse a `/team_review` report for findings marked `Dev Decision: fix`, dispatch the builder to apply them, append Resolutions to the report, and (when `github_flow`) push and post PR comments.

**Template:** `framework/generator/templates/commands/fix.md`
**Feature gate:** `features.review`

### Steps

**Step 1 — Load report.** `REPORT_PATH` is required (the path to a `.reviews/...md` file). Do not accept raw-pasted review text.

**Step 2 — Parse Dev Decisions.** Collect all finding cards where `Dev Decision: fix`. Match the field in the card's metadata bullet list only (not body prose or code blocks). If scope is empty, stop with instructions to annotate first. For `Clarify` findings, verify a `Chosen option:` line is present or stop.

**Step 3 — Confirm scope.** Print the fix list; wait for confirmation.

**Step 4 — Dispatch builder.** Provide the full finding cards verbatim, scope restriction ("only files mentioned in these cards"), test and lint instructions, and instruction to make a single atomic commit for all fixes in scope. If a fix breaks tests, the builder marks it `❌` and continues rather than aborting.

**Step 5 — Append Resolutions.** Get the current short SHA. Append `## Resolutions` to the report file (not committed by `/fix`):

```markdown
## Resolutions
- S1 ✅ <sha> — <one-line description>
- R1 ⏭ deferred — <reason>
- H2 ❌ failed — <reason>
```

**Step 5.5 — Auto-push (requires `github_flow`).** Push before posting PR comments so referenced SHAs are reachable on the remote. If `git push` fails, stop — do not post comments. The local state at this point: builder commit exists, Resolutions appended (uncommitted), PR not notified. Recover manually.

**Step 6 — Post PR comments (requires `github_flow`).**

6a. For each finding with a `PR comment ID:` field, post an inline reply on that comment thread — even deferred/failed findings get a reply so threads are resolved.

6b. Post a new summary comment every time (do not update existing ones — each `/fix` run preserves history).

**Step 7 — Report results.**

```
## Fix Results
Applied:   S1: <what changed> (<file>)
Deferred:  A1: <reason>
Failed:    H2: <reason>

Report updated: <REPORT_PATH>
PR comment: <url>   ← github_flow only
Tests: X/X passed

Next: /finish
```

---

## `/quickfix` — Light-Tier TDD Fix

**Purpose:** Fix a small, decision-free bug through the light tier. No plan file, no plan-adversary, no task graph. One Beads ticket (when `beads_tickets`), one TDD builder dispatch, a proportionate review.

**Template:** `framework/generator/templates/commands/quickfix.md`
**Feature gate:** `features.light_tier`

**Tier decision rule:** The heavy path (`/plan_w_team` → `/build`) exists for work with open design decisions. `/quickfix` exists for work where the fix is forced — the correct behavior is already specified by an existing test, the ticket, or obviously-intended behavior.

### Tier criteria

A change qualifies only when ALL hold:

**Judgment rule (the real gate):** there are no consequential decisions left to make — the fix is forced.

**Mechanical proxies:**
- Touches ≤ 3 files, excluding tests
- No schema or data migration
- No new route/endpoint, no authorization/permission change, no new dependency
- Restores intended behavior or is trivially additive — does not change a documented contract

> Setup note: tailor the proxies to this project's risk surface during authoring (e.g. for a Rails app: "no migration, no new route, no policy/role change").

If any proxy fails, or the judgment rule fails, stop and direct the user to `/plan_w_team`.

### Steps

**Step 1 — Resolve input.** If `beads_tickets`: resolve a ticket ID or use free-text as bug description.

**Step 2 — Investigate and gate.** Explore the codebase (no subagents) to localize the bug. Print an explicit tier check — every line, every time:

```
Tier check:
  Estimated files: <N> (<paths>)
  Migration: <yes/no>
  New route / auth change / dependency: <yes/no>
  Contract change: <yes/no>
  Open decisions: <none — expected behavior specified by <source>, or list them>
→ Qualifies for quickfix.  |  → Does NOT qualify: <failing criterion>
```

**Step 3 — Branch check.** If on the default branch, create and switch to `fix/<kebab-slug>`.

**Step 4 — Beads ticket (requires `beads_tickets`).** Create or update-to-`in_progress` a ticket for the bug.

**Step 5 — Dispatch builder.** TDD instruction: "RED first — write a failing test that reproduces the bug and confirm it fails for the expected reason. Then GREEN — the minimal fix. Then REFACTOR." Scope restriction to the files from the tier check. Commit instruction: single atomic commit `fix: <summary> (<ticket-id>)`. Escalation instruction: if the builder encounters a decision the ticket doesn't answer, STOP — commit the failing test alone (`test: failing test for <bug> — escalated`) and report via TaskUpdate.

**Step 6 — Escalation path.** If the builder stops on a discovered decision, this is the tier system working — not a failure. Leave the ticket `in_progress` (with a comment recording the discovered decision). Confirm the failing test is committed. Print:

```
Escalated — this fix has an open decision: <decision>.
The failing test at <test path> carries forward as the plan's first test requirement.

Next: /plan_w_team "<original bug description> — see ticket <id>; failing test at <test path>"
```

**Step 7 — Verify.** Run `{{discovery.test_runner.cmd}}`. All tests must pass. If any fail, resume the builder once with specific guidance if the failure is clearly fixable; otherwise escalate to the user. Never resume more than once for the same failure.

**Step 8 — Close and sync (requires `beads_tickets`).** `br close <id>` and `br sync --flush-only`. Stage and commit the beads export if it changed.

**Step 9 — Report.**

```
## Quickfix Complete
Ticket: <id> — closed    ← beads_tickets only
Branch: <branch>
Files changed: <file — what changed>
Tests: X/X passed
Commit: <sha>

Review: open a draft PR via /finish, then run /team_review --light.
Next: /finish
```

---

## `/finish` — Finish a Development Branch

**Purpose:** Verify tests, present completion options (merge locally, flip PR to ready, keep as-is, discard), execute the chosen option, and clean up worktrees.

**Template:** `framework/generator/templates/commands/finish.md`
**Feature gate:** `features.plan_build`

### Steps

1. **Verify tests:** run `{{discovery.test_runner.cmd}}`; stop on failure.
2. **Determine base branch** via `git merge-base`.
3. **Present options** (exactly four — no elaboration):

```
Tests pass. What would you like to do?

1. Merge back to <base-branch> locally
2. Flip draft PR to ready-for-review    ← github_flow only
3. Keep the branch as-is (I'll handle it later)
4. Discard this work
```

4. **Execute choice:**
   - Option 1: checkout base, pull, merge, re-run tests, delete feature branch.
   - Option 2 (requires `github_flow`): find the PR; if not found or already ready, report and stop; otherwise `gh pr ready <pr-number>`.
   - Option 3: keep everything.
   - Option 4: confirm with exact word "discard", then delete the branch.
5. **Clean up worktree** (for Options 1, 2, 4): `git worktree remove <path>` if the feature branch had an associated worktree.

---

## `/verify-browser` — Playwright CLI UI Verification

**Purpose:** Inspect recent git commits, build a verification checklist of user-visible changes, then use `playwright-cli` to walk through it.

**Template:** `framework/generator/templates/commands/verify-browser.md`

Key behaviors:
1. Verify `playwright-cli` is installed (install via `npm install -g @playwright/cli@latest` if not)
2. Ensure dev servers are running
3. Analyze recent commits for user-visible changes, build a verification checklist
4. Use `playwright-cli` commands to navigate, interact, and verify:
   - `playwright-cli open <url>` / `playwright-cli goto <url>` for navigation
   - `playwright-cli click`, `fill`, `select`, `press` for interaction
   - `playwright-cli snapshot` / `screenshot` for visual verification
   - `playwright-cli console` for error checking
5. Report results with screenshots and console errors
6. Clean up with `playwright-cli close`

---

## `/test` — Run Tests and Report

**Purpose:** Run the project's test suite and present structured results. Read-only — never modifies source or test files.

```markdown
---
description: Run tests and report results
argument-hint: [path-or-pattern]
model: {{discovery.models.simple}}
---

# Test

## Variables
TARGET: $ARGUMENTS

## Steps

### 1. Determine Scope

If TARGET is empty, run the full test suite:
`{{discovery.test_runner.cmd}}`

{{#if discovery.workspaces}}
If TARGET exactly matches a workspace name (case-sensitive), run that workspace's test runner:
{{#each discovery.workspaces}}
{{#if test_runner}}
- `{{name}}` → `{{test_runner.cmd}}`
{{/if}}
{{/each}}

If TARGET does not match any workspace name, treat it as a path or filter for the root test runner:
`{{discovery.test_runner.cmd}} TARGET`
{{else}}
If TARGET is provided, pass it as a path or filter:
`{{discovery.test_runner.cmd}} TARGET`
{{/if}}

### 2. Run Tests

Execute the test command. Capture full output.

### 3. Report

Parse the output and present:

| Metric | Count |
|--------|-------|
| Total  | N     |
| Passed | N     |
| Failed | N     |
| Skipped| N     |
| Wall time | Ns  |

**If all pass:** Report the summary and stop.

**If any fail:** For each failure:
- Test name and file:line location
- Error message / assertion that failed
- Likely cause (read the test and the code it tests)
- Do NOT auto-fix. Present the information and stop.

### 4. DO NOT
- Do not modify any test files
- Do not modify any source files
- Do not re-run failed tests automatically
- Do not suggest running with different flags unless the user asks
```

---

## `/audit-docs` — Documentation Health Check

**Purpose:** Identify stale, orphaned, and temporary docs that have overstayed their welcome. Produce a prioritized action list. Optionally fix straightforward cases automatically.

The heavy lifting (git queries, pattern matching, risk scoring) is handled by a standalone shell script (`audit-docs.sh` — see Step 5). The LLM invokes the script once and interprets the structured JSON output.

**When to run:**
- **After a sprint/milestone** — catch permanent docs drifting from their code.
- **Before a major refactor** — identify which docs will be affected, so they're updated as part of the refactor plan.
- **Monthly with `--fix`** — auto-clean temporary files and archive completed specs.
- **When the post-commit hook flags temp files** — the commit hook (`audit-docs-hook.sh`) is a shallow filename scan; this command is a deep analysis (co-change, git history, content signals).

For detailed staleness heuristics and co-change analysis methodology, see `08-docs-structure.md`.

```markdown
---
description: Audit documentation for staleness, sprawl, and drift
argument-hint: [--fix]
---

# Audit Docs

## Variables
ARGS: $ARGUMENTS
FIX_MODE: true if ARGS contains --fix, false otherwise

## Steps

### 1. Run Audit Script

Execute the audit script to collect all deterministic signals:

`bash {{discovery.agent_dir}}/hooks/audit-docs.sh --docs-dir docs --specs-dir specs --index-file docs/README.md`

Parse the JSON output. The script produces structured data for every doc and spec file, including:
- Per-doc: `path`, `last_edit_date`, `last_edit_days`, `commits_90d`, `is_temporary`, `temp_pattern_matched`, `in_index`, `co_change_files`, `todo_count`, `has_stale_versions`, `risk_level`
- Per-spec: `path`, `age_days`, `git_evidence_commits`, `listed_files_exist`, `classification`
- Summary: aggregate counts by risk level and spec status

If the script fails (non-zero exit or invalid JSON), report the error to the user and stop.

### 2. Interpret Results

The script assigns risk levels mechanically. Your job is to add judgment:

**For each HIGH risk doc:**
- If `is_temporary` is true: recommend specific action based on `temp_pattern_matched` (e.g., meeting notes → extract decisions to DECISIONS.md then delete)
- If not temporary but old with no commits: check `co_change_files` — if source files the doc describes have high churn, the doc is genuinely stale

**For each MEDIUM risk doc:**
- Read the file content to determine if the staleness is genuine
- A doc can be old but intentionally stable (e.g., a deployment guide that hasn't changed because the deploy process hasn't changed)
- If `has_stale_versions` is true, check whether the referenced versions are actually outdated
- If `in_index` is false, determine whether it should be added to the index or deleted

**For each spec:**
- If `classification` is `built_complete`: verify by reading the spec's acceptance criteria — the script only checks file existence, not semantic completion
- If `classification` is `built_partial`: flag for human review with specifics on what's missing
- If `classification` is `never_built_old`: recommend deletion or implementation
- If `classification` is `never_built_recent`: leave alone

### 3. Report

Output a prioritized list using the script's data enriched with your interpretation:

```
## Documentation Audit

### High Risk — Action Required
- FRIDAY_CLIENT_MEETING_SUMMARY.md — meeting notes, 45 days old. Recommend: extract any decisions to DECISIONS.md, then delete.
- TESTING_RESULTS.md — test output, not a permanent doc. Recommend: delete (results belong in CI logs).
- DEPLOYMENT_v0.9.7.md — versioned, superseded. Recommend: merge any new info into DEPLOYMENT.md, then delete.

### Medium Risk — Review Needed
- AWS_SETUP_CHECKLIST.md — not in docs index. Recommend: merge into DEVELOPMENT.md or DEPLOYMENT.md.
- ARCHITECTURE.md — last edited 67 days ago, but 12 source files it describes have changed since. May be drifting.

### Low Risk — Looks Healthy
- DECISIONS.md, DEVELOPMENT.md, CHANGELOG.md — recently updated, in index, no issues.

### Untracked Files (not in docs/README.md index)
- AWS_INTEGRATION_SUMMARY.md
- MOCK_DATA_SCHEMAS.md
Action: add to index as permanent docs, or delete if temporary.

### Specs Status
- `specs/add-user-auth.md` — Built & Complete (15 commits reference it). Recommend: archive.
- `specs/migrate-database.md` — Never Built, 45 days old. Recommend: delete or implement.
- `specs/fix-login-flow.md` — Built & Partial (3 of 5 acceptance criteria met). Needs review.
- `specs/add-dark-mode.md` — Never Built, 5 days old. Leave.
```

### 4. Fix Mode (if --fix)

For HIGH risk temporary docs (meeting notes, test results, versioned files):
- Read the file
- Extract any decisions or insights not yet in a permanent doc
- Update the appropriate permanent doc
- Delete the temporary file
- Update docs/README.md if the file was listed there

For specs classified as "Built & Complete":
- Move to `specs/archive/`

Do NOT auto-delete anything that isn't clearly temporary. Flag MEDIUM risk for human review.
```
