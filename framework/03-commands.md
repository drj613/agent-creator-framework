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
├── review.md          # Parallel domain-specialist code review
├── fix.md             # Apply Must Fix items from /review
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
| `/review` | `discovery.features.review` |
| `/fix` | `discovery.features.review` |
| `/verify-browser` | `discovery.features.verify_browser` |
| `/test` | `discovery.features.test` |
| `/audit-docs` | `discovery.features.audit_docs` |
| `/discovery` | `discovery.features.deep_discovery` |
| `/document` | `discovery.features.deep_discovery` |

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

**Purpose:** Analyze a requirement, explore the codebase, design the solution, and save a spec document to `specs/`. No code is written — output is only a plan file. The saved plan is then executed by `/build`.

The command takes two arguments: the user's requirement, and an optional orchestration hint that guides team composition and task structure.

```markdown
---
description: Create an implementation plan and save it to specs/
argument-hint: "[requirement] [orchestration hint]"
model: {{discovery.models.complex}}
disallowed-tools: Task, EnterPlanMode
---

# Plan With Team

Create a detailed implementation plan based on USER_PROMPT. Analyze the request, think through
the approach, and save a spec document to PLAN_OUTPUT_DIRECTORY that can be used as a blueprint
for actual development. Follow the Instructions and Workflow below.

## Variables

USER_PROMPT: $1
ORCHESTRATION_PROMPT: $2  # Optional — guides team composition, task granularity, parallel/sequential decisions
PLAN_OUTPUT_DIRECTORY: `specs/`
TEAM_MEMBERS: `{{discovery.agent_dir}}/agents/team/*.md`

## Instructions

- **PLANNING ONLY**: Do NOT build, write code, or deploy agents. Output is a plan document saved to PLAN_OUTPUT_DIRECTORY.
- If no USER_PROMPT is provided, stop and ask the user to provide it.
- If ORCHESTRATION_PROMPT is provided, use it to guide team composition, task granularity, dependency structure, and parallel/sequential decisions.
- Determine the task type (chore|feature|refactor|fix|enhancement) and complexity (simple|medium|complex).
- Think deeply about the best approach before writing the plan.
- Explore the codebase directly (no subagents) to understand existing patterns and architecture.
- Generate a descriptive kebab-case filename based on the plan topic.
- Save the complete plan to `PLAN_OUTPUT_DIRECTORY/<filename>.md`.
- The plan must be detailed enough that another agent could follow it without clarification.
- Include code examples or pseudo-code where it clarifies complex steps.
- Consider edge cases, error handling, and scalability.
- **Test-first by default:** Plans should specify tests to write before implementation. The first builder task writes failing tests; subsequent tasks implement code to make them pass. Include a `## Test Requirements` section in every plan listing required tests, test types, and coverage expectations. A spec is not complete until all listed tests pass.

## Team Orchestration

As team lead when executing plans via /build, you coordinate work via task management tools.
You NEVER write code directly — you orchestrate team members.

For full documentation of TaskCreate, TaskUpdate, TaskList, TaskGet, Task, and the Resume
pattern, see `orchestration-reference.md`.

## Workflow

PLANNING ONLY — do not execute, build, or deploy.

1. Parse USER_PROMPT — understand the core problem and desired outcome
{{#if discovery.features.deep_discovery}}
1a. **Consult module docs** — read `docs/modules/ROUTING.md` to find which module docs cover the files this plan will likely affect. For each matching entry, read the corresponding `docs/modules/<module>.md` to understand patterns, conventions, and dependencies. Record consulted docs in the plan's "Module Docs Consulted" section.
{{/if}}
2. Explore codebase — read relevant files directly to understand existing patterns
3. Design solution — architecture decisions, implementation approach
4. Define team — identify needed agents from TEAM_MEMBERS or use general-purpose
5. Define tasks — write out steps with IDs, dependencies, assignments
6. Generate filename — descriptive kebab-case
7. Save plan — write to PLAN_OUTPUT_DIRECTORY/<filename>.md
8. Report — summarize per the Report section below

## Plan Format

Replace all <angle bracket> placeholders with actual content.
Non-placeholder text must appear exactly as written.

---

# Plan: <task name>

## Task Description
<describe the task in detail>

## Objective
<what will be accomplished when this plan is complete>

<if feature or medium/complex complexity:>
## Problem Statement
<the specific problem or opportunity this addresses>

## Solution Approach
<how the solution addresses the objective>
</if>

{{#if discovery.features.deep_discovery}}
## Module Docs Consulted
<list module docs that were read during planning, e.g.:>
- `docs/modules/auth.md` — authentication patterns and JWT conventions
- `docs/modules/database.md` — repository pattern and migration conventions
{{/if}}

## Relevant Files
<bullet list of existing files relevant to the task, with one-line explanations>

### New Files
<files to be created, if any>

<if medium/complex complexity:>
## Implementation Phases
### Phase 1: Foundation
### Phase 2: Core Implementation
### Phase 3: Integration & Polish
</if>

## Team Orchestration

You operate as team lead. Use Task and Task* tools exclusively — never touch the codebase directly.

### Team Members

- Builder
  - Name: <unique name, e.g. "builder-api">
  - Role: <single focused responsibility>
  - Agent Type: <agent name from TEAM_MEMBERS, or "general-purpose">
  - Resume: true
- <additional team members as needed>

## Step by Step Tasks

Run TaskCreate for each task before deploying any agents.

Task IDs must be kebab-case alphanumeric (`[a-z0-9-]+`). The `Depends On` field must reference task IDs (not task names or descriptions).

### 1. <Write Tests (Test-First)>
- **Task ID**: <write-tests-kebab-case-id>
- **Depends On**: none
- **Assigned To**: <team member name>
- **Agent Type**: <agent type>
- **Parallel**: <true|false>
- Write failing tests per the Test Requirements section
- Verify all new tests fail before implementation begins

### 2. <Implement Feature>
- **Task ID**: <kebab-case-id>
- **Depends On**: <write-tests-task-id>
- **Assigned To**: <team member name>
- **Agent Type**: <agent type>
- **Parallel**: <true|false>
- <specific action>
- All tests from the test-writing task must pass before marking complete

### N-1. Run Tests
- **Task ID**: run-tests
- **Depends On**: <all builder task IDs>
- **Assigned To**: <last builder>
- **Agent Type**: builder
- **Parallel**: false
- Run the full test suite — all tests must pass before marking complete
- Fix any failures before proceeding

### N. Final Validation
- **Task ID**: validate-all
- **Depends On**: run-tests, <all other task IDs>
- **Assigned To**: <validator>
- **Agent Type**: validator
- **Parallel**: false
- Run test suite independently to confirm
- Run lint and type checks
- Verify acceptance criteria met

## Task Granularity

A well-sized task:
- Can be completed by one agent without losing context (roughly 1–5 files changed)
- Has a single clear acceptance criterion or a small set of closely related criteria
- Depends on 0–2 other tasks (deep dependency chains signal too-fine granularity)

**Anti-patterns:** "Rename variable in 3 files" as a separate task (too fine — fold into the task that needs the rename). "Implement entire auth system" as one task (too coarse — split by concern: middleware, routes, tests).

**Heuristic:** If you can describe the task in 1–2 sentences and it maps to a coherent unit of work, it's probably right-sized.

## Acceptance Criteria

Use checkbox format. Each criterion must be specific and independently verifiable.

- [ ] <criterion 1 — e.g. POST /auth/login endpoint accepts username + password>
- [ ] <criterion 2 — e.g. Successful login returns JWT token in response body>
- [ ] <criterion 3 — e.g. Failed login returns 401 with error message>

## Test Requirements

Specs are not complete until their tests pass. Define what tests must exist:

**Test approach:** <test-first | test-alongside | not-applicable>
- `test-first` (default): write failing tests before implementation
- `test-alongside`: write tests during implementation (use only when the user explicitly requests it or the task is pure refactoring with existing coverage)
- `not-applicable`: no testable behavior (documentation-only, config changes, dependency upgrades, CSS/styling-only). Requires justification below.

**Required tests:**
- [ ] <test 1 — e.g. Unit: AuthService.login returns JWT for valid credentials>
- [ ] <test 2 — e.g. Unit: AuthService.login throws for invalid credentials>
- [ ] <test 3 — e.g. Integration: POST /auth/login returns 200 with token>
- [ ] <test 4 — e.g. Integration: POST /auth/login returns 401 for bad password>

**Test types needed:**
- Unit tests: <yes/no — what to cover>
- Integration tests: <yes/no — what to cover>
- E2E tests: <yes/no — what to cover, only if verify_browser is enabled>

**Coverage notes:** <any specific coverage expectations, e.g. "all new public functions must have unit tests", "all new API endpoints must have integration tests">

**Skip justification:** <required if test approach is not-applicable — explain why this change has no testable behavior>

## Validation Commands
<the exact commands to run to verify correctness — adapted to this project's stack>

## Notes
<optional: edge cases, dependencies, open questions>

---

## Example Plan

A complete example showing the expected plan structure for a medium-complexity feature:

````markdown
# Plan: add-api-rate-limiting

## Task Description
Add rate limiting to the public API endpoints to prevent abuse and ensure fair usage across tenants.

## Objective
All public API routes enforce per-tenant rate limits with configurable thresholds, returning 429 Too Many Requests when exceeded.

## Problem Statement
The API currently has no rate limiting. A single tenant can consume unlimited resources, degrading service for others. Production logs show occasional traffic spikes from individual API keys causing elevated p99 latency.

## Solution Approach
Implement a sliding window rate limiter using Redis, applied as middleware to all routes under `/api/v1/`. Limits are configurable per tier (free: 100/min, pro: 1000/min). Rate limit headers (X-RateLimit-Remaining, X-RateLimit-Reset) are included in every response.

## Relevant Files
- `src/middleware/auth.ts` — existing auth middleware where rate limiting will be added
- `src/config/index.ts` — app configuration, will add rate limit thresholds
- `src/lib/redis.ts` — existing Redis client
- `tests/middleware/auth.test.ts` — existing auth tests

### New Files
- `src/middleware/rate-limiter.ts` — rate limiting middleware
- `tests/middleware/rate-limiter.test.ts` — rate limiter tests

## Team Orchestration

You operate as team lead. Use Task and Task* tools exclusively — never touch the codebase directly.

### Team Members

- Builder
  - Name: builder-api
  - Role: Implement rate limiter middleware and configuration
  - Agent Type: builder
  - Resume: true
- Validator
  - Name: validator-api
  - Role: Verify acceptance criteria and run full test suite
  - Agent Type: validator
  - Resume: true

## Step by Step Tasks

Run TaskCreate for each task before deploying any agents.

### 1. Write Rate Limiter Tests (Test-First)
- **Task ID**: write-rate-limiter-tests
- **Depends On**: none
- **Assigned To**: builder-api
- **Agent Type**: builder
- **Parallel**: false
- Create `tests/middleware/rate-limiter.test.ts` with failing tests per the Test Requirements section
- Write unit tests for the sliding window logic (increment, reset, headers)
- Write integration tests for HTTP responses (200 under limit, 429 over limit, tier enforcement)
- Verify all new tests fail (no implementation yet) — this confirms tests are testing the right thing

### 2. Implement Rate Limiter Middleware
- **Task ID**: implement-rate-limiter
- **Depends On**: write-rate-limiter-tests
- **Assigned To**: builder-api
- **Agent Type**: builder
- **Parallel**: false
- Create `src/middleware/rate-limiter.ts` with sliding window algorithm using Redis
- Add rate limit tier configuration to `src/config/index.ts`
- Wire middleware into the Express app before route handlers
- All tests from step 1 must pass before marking complete

### 3. Run Tests
- **Task ID**: run-tests
- **Depends On**: implement-rate-limiter
- **Assigned To**: builder-api
- **Agent Type**: builder
- **Parallel**: false
- Run the full test suite — all tests must pass before marking complete
- Fix any failures before proceeding

### 4. Final Validation
- **Task ID**: validate-all
- **Depends On**: run-tests
- **Assigned To**: validator-api
- **Agent Type**: validator
- **Parallel**: false
- Run test suite independently to confirm
- Run lint and type checks
- Verify acceptance criteria met

## Acceptance Criteria

- [ ] All `/api/v1/` routes return `X-RateLimit-Remaining` and `X-RateLimit-Reset` headers
- [ ] Requests exceeding the rate limit receive 429 status with a JSON error body
- [ ] Free tier is limited to 100 requests per minute per API key
- [ ] Pro tier is limited to 1000 requests per minute per API key
- [ ] Rate limits use a sliding window (not fixed window)
- [ ] All existing tests continue to pass

## Test Requirements

**Test approach:** test-first — write failing tests before implementing the rate limiter

**Required tests:**
- [ ] Unit: sliding window counter increments correctly
- [ ] Unit: sliding window counter resets after window expires
- [ ] Unit: rate limiter returns correct headers (Remaining, Reset)
- [ ] Integration: request under limit returns 200 with rate limit headers
- [ ] Integration: request at limit returns 200
- [ ] Integration: request over limit returns 429 with JSON error body
- [ ] Integration: free tier limit (100/min) enforced
- [ ] Integration: pro tier limit (1000/min) enforced

**Test types needed:**
- Unit tests: yes — sliding window algorithm logic, header calculation
- Integration tests: yes — full HTTP request/response cycle with Redis
- E2E tests: no

**Coverage notes:** All new public functions in rate-limiter.ts must have unit tests. All new middleware behavior must have integration tests.

## Validation Commands
```bash
pnpm vitest run tests/middleware/rate-limiter.test.ts
pnpm vitest run
pnpm tsc --noEmit
pnpm eslint src/middleware/rate-limiter.ts
```

## Notes
- Redis must be running locally for integration tests (`docker compose up redis`)
- Consider adding a bypass for health check endpoints (`/api/v1/health`)
````

---

## Report

After saving the plan, summarize:

```
Plan created: PLAN_OUTPUT_DIRECTORY/<filename>.md
Topic: <what it covers>
Complexity: <simple|medium|complex>

Tasks:
- <task id> — <owner> (<parallel|sequential>)
- ...

Team:
- <name> — <role>
- ...

Run when ready:
/build PLAN_OUTPUT_DIRECTORY/<filename>.md
```

---

## `/build` — Execute a Plan

**Purpose:** Pre-flight check the plan, confirm with the user, then execute it by dispatching the agent team.

```markdown
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

**Agent type check:** Parse the plan's `## Team Orchestration / Team Members` section. For each
listed Agent Type, check that a matching `.md` file exists in `{{discovery.agent_dir}}/agents/team/`. List any
missing agent types and stop — do not proceed until they exist or the plan is updated.

**Task ID check:** Parse all task IDs from the `## Step by Step Tasks` section. Verify each ID matches `[a-z0-9-]+` (kebab-case alphanumeric). Verify all IDs are unique. If any ID is malformed or duplicated, report it and stop.

**Dependency check:** Parse the `## Step by Step Tasks` section. Build the dependency graph from
`Depends On` fields. Check for cycles. If any task depends on a task ID that doesn't exist in the
plan, report it and stop.

**Test requirements check:** Parse the `## Test Requirements` section. Verify it exists and lists at least one required test. If the section is missing, warn the user: "This plan has no Test Requirements section. Tests should be defined before building. Continue anyway?" Wait for confirmation.

### 2. Dry-Run Summary

Print a summary for the user to review before anything runs:

```
Plan: PATH_TO_PLAN
Complexity: <from plan>

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

### 3. Execute

Read and execute the plan at PATH_TO_PLAN. Create all tasks via TaskCreate before deploying
any agents. Follow the orchestration workflow defined in the plan.

{{#if discovery.features.deep_discovery}}
**Module doc consultation:** Before dispatching each builder task, read `docs/modules/ROUTING.md` to check which module docs cover the files the task will modify. Include instructions in the builder's prompt to read the relevant module docs and follow documented patterns. After task completion, if the builder changed behavior described in a module doc, flag it for `/discovery --module <name>` refresh.
{{/if}}

For full documentation of task management tools, see `orchestration-reference.md`.

### 3a. Error Recovery

When a deployed agent fails or reports an error:

1. **Read the output** — understand the failure from the agent's report or TaskOutput.

2. **Classify the failure** using these heuristics:
   - **Clearly fixable** — the error message includes a specific file and line number, AND the fix is obvious from context:
     - Missing import or wrong import path
     - Typo in variable/function name
     - Type mismatch with a clear expected vs. actual
     - Test assertion off by a small amount
     - Linter error with auto-fix available
     Resume the agent ONCE with specific fix guidance.
     Example: `Task({ resume: agentId, prompt: "The import path should be ../utils not ./utils. Fix and re-run tests." })`
   - **Ambiguous or structural** — escalate to user without retrying:
     - Error message is vague ("Something went wrong", "Internal error")
     - Fix requires changing architecture or design approach
     - Failure is in code the agent did not write (pre-existing test breaking)
     - Missing external dependency or service
     - Multiple cascading errors suggesting a wrong approach
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

3. **Task state management:**
   - Failed tasks remain `in_progress` (not completed, not deleted)
   - Downstream tasks that depend on a failed task stay `blocked`
   - If the user chooses to skip, mark the task `completed` with a note: "Skipped by user after failure"
   - If the user chooses to abort, report all task statuses and stop

4. **Single retry limit:** Never resume the same agent more than once for the same failure.
   If the retry also fails, escalate to the user regardless of failure type.

5. **Timeout handling:** If `TaskOutput` times out (no response within the timeout window):
   - Check `TaskList` to see if the task is still `in_progress` (agent may still be running).
   - If still `in_progress`: wait and retry `TaskOutput` with a longer timeout (once).
   - If the second attempt also times out: escalate to the user with the task's current state.

6. **Validator caveats:** When a validator returns PASS but with CANNOT VERIFY items:
   - Display the caveats to the user.
   - If the user confirms, mark the task complete.
   - If the user wants to review, keep the task `in_progress`.

### 4. Completion Report

Once all tasks are complete, verify test requirements and present a build summary:

**Test verification procedure:**
1. Parse the plan's `## Test Requirements / Required tests` checklist
2. For each listed test, search the codebase for a matching test function (by name or description in `it()`/`test()`/`#[test]` blocks)
3. Run the test suite and map results back to the required tests list

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
```

If any required tests are missing or failing, the spec is not considered complete.
```

---

## `/review` — Parallel Domain-Specialist Code Review

**Purpose:** Run all project-specific reviewer agents against the current diff in parallel, then synthesize their findings into a structured, prioritized report. Reviewers are discovered dynamically from `{{discovery.agent_dir}}/agents/team/reviewer-*.md` — no hardcoded specialists in the command itself.

The review team always includes:
- **`reviewer-security`** — cross-cutting security pass (always authored during setup)
- **`questioner`** — naive questions with fresh eyes (always generated)
- **`reviewer-<domain>`** — 2–4 project-specific specialists authored during setup (e.g. `reviewer-rails`, `reviewer-sql-performance`, `reviewer-hotwire`)

Each domain reviewer covers security, architecture, and test quality within its area. See `04-agents.md` for how to author the team and `framework/generator/templates/commands/review.md` for the full command template.

The command template at `framework/generator/templates/commands/review.md` is the authoritative source. Key behaviours:

1. Get the diff (staged or commit range)
2. Warn if diff exceeds ~2000 lines
3. Glob `agents/team/reviewer-*.md` to discover reviewers; list them before dispatching
4. Launch all reviewers + questioner simultaneously with `run_in_background: true`; wrap diff in `<diff>` tags with a prompt-injection notice
5. Wait for all to complete
6. Synthesize: unify security findings from security reviewer + domain Security sub-sections into one bucket; de-duplicate by semantic equivalence; tag each finding with source reviewer

Summary format:
```
## Review Summary — <date> — <diff target>

### Security (must fix before merge)
### Architecture
### Test Quality
### Questions (from questioner)
### Clean

---
Security: <PASS | N issues>
<reviewer-name>: <PASS | N issues>
```

To add a new reviewer: create `{{discovery.agent_dir}}/agents/team/reviewer-<domain>.md` — the command picks it up automatically on the next run.

---

### `/fix`

Applies Must Fix items from a `/review` run. Accepts review output (or user-specified findings), filters to Must Fix items, creates a targeted fix spec limited to listed files, and dispatches the builder with that spec. Reminds user to re-run `/review` after fixing.

**Template:** `framework/generator/templates/commands/fix.md`
**Feature gate:** `features.review`

---

## `/verify-browser` — Playwright CLI UI Verification

**Purpose:** Inspect recent git commits, build a verification checklist of user-visible changes, then use `playwright-cli` (https://github.com/microsoft/playwright-cli) to walk through it. Uses the CLI tool, not the Playwright MCP — the CLI is more token-efficient for coding agents.

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

