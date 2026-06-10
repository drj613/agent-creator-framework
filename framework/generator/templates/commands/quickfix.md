---
description: Light-tier TDD fix for small, decision-free changes{{#if discovery.features.beads_tickets}} — Beads ticket + builder dispatch{{/if}}, no plan
argument-hint: "[bug description{{#if discovery.features.beads_tickets}} or Beads ticket ID{{/if}}]"
---

# Quickfix

Fix a small, decision-free bug through the light tier: no plan file, no plan-adversary, no task graph. One {{#if discovery.features.beads_tickets}}Beads ticket, one {{/if}}TDD builder dispatch, a proportionate review. The heavy path (`/plan_w_team` → `/build`) exists for work with open design decisions; this path exists for work where the fix is forced.

## Variables

INPUT: $ARGUMENTS  # free-text bug description{{#if discovery.features.beads_tickets}} OR an existing Beads ticket ID{{/if}}

## Tier Criteria

A change qualifies for quickfix only when ALL of the following hold.

**Judgment rule (the real gate):** there are no consequential decisions left to make — the correct behavior is already specified by an existing test, the ticket, or obviously-intended behavior. The fix is forced.

**Mechanical proxies (enforceable):**
- Touches ≤ 3 files, excluding tests
- No schema or data migration
- No new route/endpoint, no authorization/permission change, no new dependency
- Restores intended behavior or is trivially additive — does not change a documented contract

> Setup note: tailor the proxies to this project's risk surface during authoring (e.g. for a Rails app: "no migration, no new route, no policy/role change").

If any proxy fails, or the judgment rule fails, this is not a quickfix. Stop and direct the user to `/plan_w_team`.

## Workflow

### 1. Resolve Input

If INPUT is empty, stop and ask for a bug description{{#if discovery.features.beads_tickets}} or ticket ID.

If INPUT looks like a Beads ticket ID (matches the project's issue prefix), run `br show <id>` and use its description as the bug report. Otherwise treat INPUT as a free-text bug description{{/if}}.

### 2. Investigate and Gate

Explore the codebase directly (no subagents) just enough to localize the bug and estimate the fix's footprint.{{#if discovery.features.deep_discovery}} Read `docs/modules/ROUTING.md` and any module doc covering the affected files.{{/if}}

Then print an explicit tier check — every line, every time, so the gate is auditable:

```
Tier check:
  Estimated files: <N> (<paths>)
  Migration: <yes/no>
  New route / auth change / dependency: <yes/no>
  Contract change: <yes/no>
  Open decisions: <none — expected behavior specified by <source>, or list them>
→ Qualifies for quickfix.  |  → Does NOT qualify: <failing criterion>
```

If the check fails, stop with:

```
This needs the heavy tier: <failing criterion>.
Run: /plan_w_team "<bug description>"
```

Do not proceed past a failed gate, even if the user's request sounded small. The human chooses the tier by invoking the command; the command verifies it.

### 3. Branch Check

If the current branch is the default branch, create and switch to `fix/<kebab-slug>` derived from the bug description. Otherwise stay on the current branch.

{{#if discovery.features.beads_tickets}}
### 4. Beads Ticket

If Step 1 resolved an existing ticket, run `br update <id> --status=in_progress`.

Otherwise create one:

```bash
br create --title="<short bug title>" \
          --description="Repro: <how to trigger>. Expected: <intended behavior + where that's specified>. Suspected files: <paths from Step 2>." \
          --type=bug --priority=2
br update <id> --status=in_progress
```
{{/if}}

### 5. Dispatch Builder

Deploy one builder agent (subagent_type: `builder`) with:

{{#if discovery.features.beads_tickets}}- The `br show <id>` output under a `## Beads Context` heading
{{/if}}- The repro steps and the expected behavior (and its source — the ticket, an existing test, documented behavior)
{{#if discovery.features.deep_discovery}}- The relevant module doc(s) from Step 2, with instruction to follow documented patterns
{{/if}}- Scope restriction: "Only modify the files identified in the tier check, plus their tests. Do not touch other files."
- TDD instruction: "RED first — write a failing test that reproduces the bug and confirm it fails for the expected reason. Then GREEN — the minimal fix. Then REFACTOR. Run the full suite before reporting complete."
- Commit instruction: "Make a single atomic commit: `fix: <summary>{{#if discovery.features.beads_tickets}} (<ticket-id>){{/if}}`. Include the test and the fix together."
- **Escalation instruction:** "If at any point you encounter a decision the ticket doesn't answer — a second behavior to choose, a needed migration, a fourth file, a contract that has to change — STOP. Do not decide and do not implement past the boundary you discovered. Commit the failing test by itself (`test: failing test for <bug> — escalated`), then report what you found via TaskUpdate."

### 6. Escalation Path

If the builder stops on a discovered decision, this is the tier system working — not a failed quickfix. Nothing is wasted: the failing test carries forward as input to the plan.

1. {{#if discovery.features.beads_tickets}}Leave the ticket `in_progress`; record what was learned: `br comment <id> "Escalated to heavy tier: <discovered decision>"`
2. {{/if}}Confirm the failing test is committed on the branch.
3. Print:

```
Escalated — this fix has an open decision: <decision>.
The failing test at <test path> carries forward as the plan's first test requirement.

Next: /plan_w_team "<original bug description> — see {{#if discovery.features.beads_tickets}}ticket <id>; {{/if}}failing test at <test path>"
```

Stop here. Do not attempt the fix in this session.

### 7. Verify

Independently confirm the builder's result:

```bash
{{discovery.test_runner.cmd}}
```

All tests must pass. If any fail, follow the same recovery rules as `/build`: resume the builder once with specific guidance if the failure is clearly fixable; otherwise escalate to the user. Never resume more than once for the same failure.

{{#if discovery.features.beads_tickets}}
### 8. Close and Sync

```bash
br close <id> --reason="Fixed via /quickfix"
br sync --flush-only
```

Stage and commit the beads export if it changed.
{{/if}}

### 9. Report

```
## Quickfix Complete
{{#if discovery.features.beads_tickets}}Ticket: <id> — closed
{{/if}}Branch: <branch>
Files changed: <file — what changed>
Tests: X/X passed
Commit: <sha>

Review: open a draft PR via /finish, then run /team_review{{#if discovery.features.light_tier}} --light{{/if}}.
Next: /finish
```
