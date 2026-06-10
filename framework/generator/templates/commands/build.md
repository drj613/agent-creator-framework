---
description: Pre-flight check and execute a plan
argument-hint: [path-to-plan]
---

# Build

## Variables
PATH_TO_PLAN: $ARGUMENTS

## Workflow

### 1. Pre-flight Checks

If no PATH_TO_PLAN is provided, stop and ask for it.

**File check:** Verify the plan file exists at PATH_TO_PLAN. If not, stop and tell the user.

{{#if discovery.features.beads_tickets}}
**Beads ticket check:** Parse the plan's `## Beads Tickets` table and each task's `**Beads Ticket**` field. Build a map of `task-id → ticket-id`. If any ticket field reads `TBD` or is missing, warn the user: "Some tasks have no Beads ticket assigned. Continue anyway?" Wait for confirmation. For all valid ticket IDs, run `br show <ticket-id>` now and store the output as context for execution.
{{/if}}

**Agent type check:** Parse the plan's `## Team Orchestration / Team Members` section. For each
listed Agent Type, check that a matching `.md` file exists in `{{discovery.agent_dir}}/agents/team/`. List any
missing agent types and stop — do not proceed until they exist or the plan is updated.

**Task ID check:** Parse all task IDs from the `## Step by Step Tasks` section. Verify each ID matches `[a-z0-9-]+` (kebab-case alphanumeric). Verify all IDs are unique. If any ID is malformed or duplicated, report it and stop.

**Dependency check:** Parse the `## Step by Step Tasks` section. Build the dependency graph from
`Depends On` fields. Check for cycles. If any task depends on a task ID that doesn't exist in the
plan, report it and stop.

**Test requirements check:** Parse the `## Test Requirements` section. Verify it exists and lists at least one required test. If the section is missing, warn the user: "This plan has no Test Requirements section. Tests should be defined before building. Continue anyway?" Wait for confirmation.

**Validator controls check:** Parse the plan's `## Validator Controls` section for `validator_e2e_capture: true|false`. If missing, default to `false` and note this in the dry-run summary.

### 2. Dry-Run Summary

Print a summary for the user to review before anything runs:

```
Plan: PATH_TO_PLAN
Complexity: <from plan>
Validator E2E Capture: <enabled|disabled>

Tasks (in execution order):
  1. <task-id> — <assigned-to> [parallel]
  2. <task-id> — <assigned-to> [sequential, depends on: task-id]
  ...
  N-1. run-tests — <builder> [sequential]
  N.   validate-all — validator [sequential]

Team:
  - <name> (<agent-type>) — <role>

Proceed? (yes to continue)
```

Wait for confirmation before dispatching any agents.

### 2a. Pre-execution: type-check baseline

Check the plan's **Validation Commands** section for any type-checker commands (tsc, mypy, pyright, rustc, etc.). Run each one before deploying any builders. If any fail, report the pre-existing errors to the user and stop — do not deploy builders into a broken type system. Ask the user to fix the baseline first.

If the plan has no explicit validation commands, fall back to running any type-checker listed in the project's discovery configuration.

### 3. Execute

Read and execute the plan at PATH_TO_PLAN. Create all tasks via TaskCreate before deploying
any agents. Follow the orchestration workflow defined in the plan.

**Per-task execution sequence:**

1. **Before dispatching**: Capture the current HEAD SHA (`git rev-parse --short HEAD`) and store it as `<before-sha>`.{{#if discovery.features.beads_tickets}} Run `br update <ticket-id> --status=in_progress`. Include the `br show <ticket-id>` output in the builder's prompt under a `## Beads Context` heading.{{/if}} If the task implements specs written by a prior test-writing task, list those spec file paths in the builder's prompt as the **expected-red baseline** so the builder does not block on them.

2. **After builder reports done**: Run a spec compliance reviewer subagent with:
   - The full task spec text (the task's entry from the plan's `## Step by Step Tasks` section)
   - The diff since dispatch: `git diff <before-sha>` (compares that commit to the current working tree, capturing both committed and uncommitted changes)
   - Instruction: "Verify the diff implements the task spec exactly — nothing missing, nothing added beyond the spec. Return ✅ COMPLIANT or ❌ with a specific list of gaps."

3. **If ❌**: Dispatch the builder again with the spec gaps as the prompt. Re-run the spec reviewer after. If it fails a second time, escalate to the user (same options as error recovery below) — do not retry further.

{{#if discovery.features.beads_tickets}}
4. **After ✅**: Run `br close <ticket-id> --reason="Completed in build"`.

5. **After failure/skip**: Leave the ticket `in_progress`; add a comment via `br comment <ticket-id> "Task failed: <summary>"` so status is recorded.
{{/if}}

{{#if discovery.features.deep_discovery}}
**Module doc consultation:** Before dispatching each builder, read `docs/modules/ROUTING.md` to check which module docs cover the files the task will modify. Include in the builder's prompt: "Read `docs/modules/<module>.md` before coding and follow the documented patterns." After the builder completes, if it changed behavior described in a module doc, note this in the completion report so the user can run `/discovery --module <name>` to refresh.
{{/if}}

For full documentation of task management tools, see `orchestration-reference.md`.

### 3a. Error Recovery

When a deployed agent fails or reports an error:

1. **Read the output** — understand the failure from the agent's report or TaskOutput.

2. **Classify the failure** using these heuristics:
   - **Clearly fixable** — the error message includes a specific file and line number, AND the fix is obvious from context:
     Resume the agent ONCE with specific fix guidance.
     Example: `Task({ resume: agentId, prompt: "The import path should be ../utils not ./utils. Fix and re-run tests." })`
   - **Ambiguous or structural** — escalate to user without retrying:
     DO NOT retry. Present to the user with full context:
     ```
     Task [task-id] failed.
     Agent: [name]
     Error: [summary of what went wrong]
     Output: [relevant portion]

     Options:
     1. Retry with guidance: [suggest what to tell the agent]
     2. Skip this task and continue
     3. Abort the build
     ```
     Wait for the user's choice.
   - **More than 3 distinct errors across multiple files:** Always treat as Ambiguous — escalate to the user. A single retry prompt rarely resolves a cascade of errors.

3. **Task state management:**
   - Failed tasks remain `in_progress` (not completed, not deleted)
   - Downstream tasks that depend on a failed task stay `blocked`
   - If the user chooses to skip, mark the task `completed` with a note: "Skipped by user after failure"
   - If the user chooses to abort, report all task statuses and stop

4. **Single retry limit:** Never resume the same agent more than once for the same failure.
   If the retry also fails, escalate to the user regardless of failure type.

5. **Timeout handling:** If `TaskOutput` times out:
   - Check `TaskList` to see if the task is still `in_progress`.
   - If still `in_progress`: wait and retry `TaskOutput` with a longer timeout (once).
   - If the second attempt also times out: escalate to the user with the task's current state.

6. **Validator caveats:** When a validator returns PASS but with CANNOT VERIFY items:
   - Display the caveats to the user.
   - If the user confirms, mark the task complete.
   - If the user wants to review, keep the task `in_progress`.

7. **Validator E2E capture disabled:** If validator reports `E2E Test: N/A — capture not requested`, treat this as expected when `validator_e2e_capture` is false (or absent).

### 4. Completion Report

Once all tasks are complete, verify test requirements and present a build summary:

**Test verification procedure:**
1. Parse the plan's `## Test Requirements / Required tests` checklist
2. For each listed test, search the codebase for a matching test function (by name or description in `it()`/`test()`/`#[test]` blocks)
3. Run the test suite: use the plan's Validation Commands if specified, otherwise use the project's default test runner
4. Map test results back to the required tests list — mark each as passing, failing, or not found

```
## Build Complete
Plan: [path]
Tasks completed: [N]
Validator final status: [PASS / FAIL]

## Test Requirements Status
Required tests: [N defined in plan]
Tests passing: [N/N]
Tests failing: [list with failure reason]
Missing tests: [list any required tests not found in codebase]
{{#if discovery.features.beads_tickets}}
## Beads Ticket Status
[ticket-id] [task-id] — closed / failed / skipped
{{/if}}
Next: /ship <plan-path>
```

If any required tests are missing or failing, the spec is not considered complete. Flag this prominently in the report.
{{#if discovery.features.beads_tickets}}
After printing the report, run `br sync --flush-only` to export all ticket state changes.
{{/if}}
