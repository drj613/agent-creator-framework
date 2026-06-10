# Design Decisions

This document explains why the framework is built the way it is. It is a human reference — it is NOT consumed by the setup agent during installation.

---

## Original Design Decisions

**Why hooks on the builder agent specifically, not globally?**
The validator is read-only and shouldn't trigger validators. Session-level hooks would fire on every file write including setup tasks. Builder-scoped hooks mean validation only runs when an agent is actively coding.

**Why `{"decision": "block"}` instead of just logging?**
Blocking forces the agent to fix the issue immediately in context, before moving on. Logging alone gets ignored. The block-and-retry loop is what makes the validation actually change behavior.

**Why plan → build separation?**
Planning uses a restricted invocation (`disallowed-tools: Task`) so it cannot execute work. Building reads the plan and dispatches agents. This creates a reviewable artifact between design and execution — you can read and edit the plan before `/build` runs it.

**Why `disallowedTools: Write, Edit` on the validator? (original v1 decision)**
Enforced at the agent definition level, not just instructed. The validator physically cannot modify files. This was a hard constraint, not a soft instruction.

**Why the validator's write restriction moved from `disallowedTools` to a prompt-enforced scope (v6 update)?**
The original `disallowedTools: Write, Edit` also prevented the validator from saving E2E spec files when the plan explicitly requested it via `validator_e2e_capture: true` in `## Validator Controls`. The hard tool block could not be selectively lifted based on plan content — either the validator can write or it cannot. The resolution: set `disallowedTools: []` in the frontmatter and enforce the scope restriction in the system prompt ("write access limited to E2E spec files only, and only when the plan enables it"). The trade-off is real: prompt-level enforcement is softer than tool-level enforcement. A well-behaved validator follows the instruction; a confused one could write files it should not. The prompt is explicit and specific to minimize that risk. The key constraint preserved: the validator still does not write production code or test files outside the designated E2E spec directory, and only when the plan author has consciously opted in. The history of the original hard constraint is worth keeping: it existed for a good reason and was changed for a specific, narrow reason — not because the goal changed.

**Why parallel domain specialists for `/review` instead of one reviewer?**
Each domain requires a fundamentally different reading posture. A security reviewer is pattern-matching against a threat model. A domain specialist reviewing Rails patterns is asking whether the right idioms and conventions are in use. A questioner is deliberately ignoring expertise to surface what the experts overlooked. A single agent context-switching between these lenses systematically underweights whichever one isn't currently active — the mental model for each crowds out the others. Running them in parallel means each reads the full diff with undivided attention on one dimension. The synthesis pass then has independent signals to work from rather than one blended pass that tried to do everything at once.

**Why a dedicated security reviewer in addition to domain specialists?**
Security is cross-cutting: a hardcoded secret, open CORS header, or authorization gap can appear in any changed file regardless of which technical domain it belongs to. Domain specialists cover security concerns within their area, but a separate security reviewer guarantees the cross-cutting pass always runs regardless of which domain files changed. The domain specialists cover architecture and test quality for their area; the security reviewer is the only agent whose mandate cannot be delegated to a domain.

**Why a questioner agent that has no project expertise?**
The questioner's value is specifically its ignorance. Domain experts miss assumptions they share with the original author — the questioner has none of those assumptions. Fresh-eyes questions ("why this approach rather than the simpler one?", "what happens if this is null?") surface implicit decisions that experts have stopped seeing. The questioner cannot be a project expert or it becomes a redundant specialist.

**Why the `audit-docs-hook` is advisory and the validator hooks block?**
Different failure modes, different cost/benefit. A lint error in code the agent just wrote is something it can fix immediately in context — blocking is costless and prevents compounding. A temporary doc that's been in `docs/` for 45 days is not something the current agent caused or can resolve in the moment. Blocking a commit because of pre-existing doc debt creates friction on every commit without driving resolution. The right behavior is to surface it and move on — the `/audit-docs --fix` command is where actual cleanup happens.

---

## Decisions Added in v2 (Multi-File Restructuring)

**Why a separate discovery phase?**
The original framework assumed the setup agent would "read the codebase" ad hoc. A structured discovery phase produces a consistent context object, prevents missed detections, and makes all subsequent steps deterministic rather than dependent on agent judgment. Every file the setup agent creates references the same discovery output, so nothing is inferred twice or inferred differently.

**Why ask model preferences abstractly (by tier, not by name)?**
Model names change. Tiers do not. The framework docs reference tiers (complex / standard / simple); the generated files use concrete names the user provides during discovery. This means the framework stays current even as models rotate or new providers appear. It also supports new model providers without framework changes.

**Why error recovery in `/build` has a single-retry limit?**
LLMs are bad at diagnosing their own failures. One retry catches transient issues (timeout, flaky test, typo). Beyond that, the agent is likely to repeat the same mistake or compound the error. Unbounded retries waste tokens and can produce progressively worse output. Human judgment is needed for anything structural.

**Why the validator checks acceptance criteria, not just tests?**
Tests verify code behavior. Acceptance criteria verify intent. A feature can pass all tests but miss the point of the requirement — for example, a correctly working search endpoint that returns results in the wrong format. The validator bridges the gap between "it compiles and tests pass" and "it does what was asked."

**Why extract the orchestration tutorial from `/plan_w_team` into a shared reference?**
The /plan_w_team command was 230 lines, with ~60 lines being a tutorial on TaskCreate/TaskUpdate/Task tools that are also used by /build. Extracting to a shared reference eliminates duplication and keeps each command file focused on its specific workflow rather than re-teaching tool usage.

**Why audit specs/ in addition to docs/?**
The plan-build cycle generates spec files in `specs/` that have no built-in lifecycle. Without auditing, `specs/` becomes a graveyard of abandoned plans, making it harder to find active ones. Built specs are redundant with the code they produced; unbuilt old specs represent abandoned intent that clutters the planning space.

**Why split the file at all?**
The original single file mixed three concerns: discovery/questionnaire, file generation templates, and design rationale. The rationale sections are useful for humans but actively unhelpful during setup — they burn agent context on "why" when the agent needs "what." Splitting by step gives the setup agent a clear sequence, keeps each file focused on its concern, and lets this DESIGN.md exist as a standalone human reference without inflating setup context.

**Why bash-best-practices is a ~400-line reference instead of 4 bullet points?**
The original framework described this file with four brief bullet points, but it's the most universally applicable artifact in the framework — every project that uses bash benefits. The expanded version was researched from Google's Shell Style Guide, Wooledge BashPitfalls, ShellCheck, and agent-specific sources. The agent-specific pitfalls section (no persistent shell state, no interactive input, timeout constraints, output size limits) is particularly important because these are failure modes that don't exist for human developers.

---

## Decisions Added in v3 (audit-docs Script)

**Why extract audit-docs deterministic logic into a shell script?**
The `/audit-docs` command mixed two concerns: data collection (git queries, pattern matching, file scans) and data interpretation (judging staleness, deciding fixes). The shell script handles collection and produces structured JSON. The LLM handles interpretation. This makes data collection reproducible, testable, and fast — one script invocation vs. dozens of sequential tool calls for git queries. The same script can also be used by CI pipelines without an LLM.

**Why shell scripts instead of Python for all hooks?**
The deterministic operations (git queries, grep, find, jq) are all native shell operations. Python adds a runtime dependency and complexity for operations that are naturally expressed in bash. The bash-best-practices reference already exists in the framework, so agents have comprehensive guidance for writing reliable shell scripts. Shell scripts also avoid the `uv run --script` shebang pattern that tied hooks to a specific Python package manager.

**Why does audit-docs.sh work on macOS bash 3.2?**
The script uses `date -r <epoch>` (macOS/BSD) falling back to `date -d @<epoch>` (GNU/Linux) for epoch-to-date formatting, instead of the bash 4.2-only `printf '%(%Y-%m-%d)T'` builtin. All other constructs (arrays, process substitution, arithmetic) are compatible with bash 3.2, which macOS ships by default.

---

## Decisions Added in v4 (Monorepo Support)

**Why `workspaces[]` instead of expanding `dev_servers` and `directories`?**
The existing `dev_servers.backend`/`dev_servers.frontend` and `directories.backend_root`/`directories.frontend_root` assume a binary split. A monorepo may have 2, 5, or 20 packages. Rather than make every existing field accommodate N entries (breaking the simple case), a separate `workspaces` array carries per-package config. Non-monorepo projects are completely unaffected — all new code is behind `{{#if discovery.workspaces}}` guards with `{{else}}` branches preserving the original behavior.

**Why `null` instead of `[]` for non-monorepo workspaces?**
The framework's truthiness rules (defined in `00-setup-guide.md`) treat both `null` and `[]` as falsy, so technically either would work for `{{#if discovery.workspaces}}`. However, `null` communicates intent more clearly: "this field does not apply to this project type," not "this project has zero workspaces." It also follows the convention already established by `formatter: null` and `dev_servers: null` in the schema — nullable fields use `null` for "not applicable," while array fields use `[]` for "applicable but empty" (e.g., `linters: []` means "no linters detected," which is different from "linters don't apply").

**Why `git rev-parse --show-toplevel` for hook path derivation?**
The previous approach (`cd "$SCRIPT_DIR/../../.." && pwd`) required manually counting directory depth from the script to the project root. In monorepos where the agent directory might be at `apps/backend/.claude/`, the depth changes per project and is easy to get wrong. `git rev-parse --show-toplevel` always returns the repository root regardless of where the script lives. The `SCRIPT_DIR` depth is retained as a fallback for non-git environments.

**Why workspace path prefix matching in validator scripts?**
When a file is written in a monorepo, the validator needs to determine which workspace it belongs to in order to run the correct linter/type-checker in the correct working directory. Matching the file's path against `workspaces[].path` prefixes is simple, deterministic, and fast. Files outside any workspace path fall back to the project root. This logic lives inside the validator scripts, not in the hook wiring — so the builder frontmatter is identical for monorepo and non-monorepo projects.

---

## Decisions Added in v3 (Generator Script)

**Why move hook and agent generation to a bash script?**
Two rounds of review found ~40 bugs in the pseudo-Handlebars template interpretation — the setup agent was generating hook scripts and agent YAML frontmatter from template markers like `{{#each discovery.linters}}`. These files are 100% deterministic given the discovery context: no prose judgment, no adaptive content. Moving them to a bash script that reads JSON and generates files via heredocs eliminates this entire class of bugs. The runtime (commands, hooks, agents in operation) is unchanged. Only the setup step changes.

**Why multiple focused files instead of one monolith?**
Each generator file is under 300 lines and handles one concern (validators, hooks, agents, gitignore). This makes the scripts readable and testable in isolation. `generate.sh` is a thin orchestrator that sources the others and calls them in sequence.

**Why heredocs instead of separate template files?**
Separate template files require their own escaping conventions and a template engine to execute them. Heredocs in bash are the template engine — variable interpolation is standard bash, no additional dependency. The generator's only external dependency is `jq` (already required by the hook scripts themselves).

**What the agent still generates (prose-heavy, adaptive):**
- Context file (`CLAUDE.md`) — project-specific prose
- `bash-best-practices.md` — referenced in context file
- `WORKFLOW.md` — human-readable workflow guide
- All command files — adaptive step-by-step instructions
- Rule files and skill files
- Documentation structure content

These cannot be templated because they require the agent to synthesize and adapt based on project-specific details that don't map cleanly to JSON fields.

---

## Decisions Added in v5 (Context Management, TDD, Playwright CLI)

**Why split setup into multiple conversations with a progress tracker?**
The end-to-end setup process (Steps 1 through 7) routinely overflows context windows when run in a single conversation. The agent reads step files, generates content, asks questions, and writes files — all accumulating context. Inspired by the BMAD method's "always use fresh chats" approach, setup is now organized into 4 conversations with artifacts persisted to disk between them. `.discovery-context.json` already existed for discovery state; `.setup-progress.json` was added to track which steps are complete so any conversation can resume from the right point. Each step file has a preamble that loads state from disk rather than depending on prior conversation context.

**Why 4 conversations specifically?**
Each conversation groups steps that share context naturally: (1) discovery + generation share the discovery context being built; (2) deep discovery + doc generation share the analysis artifacts; (3) context file + commands are both prose authoring from the same discovery data; (4) rules + skills + docs + verification are lighter steps that fit together. Fewer conversations would overflow; more would add unnecessary friction.

**Why test-first in the plan format?**
Specs that don't define test requirements frequently ship without adequate test coverage. By making `## Test Requirements` a standard section of every plan and structuring tasks as "write failing tests → implement → verify tests pass," TDD becomes the default workflow. The build command warns if a plan lacks test requirements, and the completion report checks whether all listed tests exist and pass. A spec is not considered complete until its tests pass.

**Why `playwright-cli` instead of the Playwright MCP?**
The Playwright MCP sends large accessibility trees and page snapshots through the tool call interface, consuming significant context. `playwright-cli` (https://github.com/microsoft/playwright-cli) is a command-line tool designed specifically for coding agents — it executes browser commands via short shell invocations (`playwright-cli click`, `playwright-cli screenshot`, `playwright-cli snapshot`) that are far more token-efficient. The CLI also supports session management, headed/headless modes, and a monitoring dashboard.

---

## Decisions Added in v6 (Validated Review, Plan Adversary, Two-Tier Workflow, Dev Decision)

**Why every reviewer finding must be validated against the checked-out code before it reaches the report?**
Multi-agent review's top failure mode is confident unverified findings: a reviewer sees a changed hunk, flags an issue, and the synthesis pass accepts it without checking whether the surrounding code already resolves it. The most common cases — a missing validation that exists upstream in the middleware chain, a missing cache that is already applied at the model layer, a security gap that is handled by a shared concern — all require reading code the diff did not show. The validation pass (Step 6a of `/team_review`) addresses this by requiring the synthesizer to open the cited file at the cited line in the working checkout and confirm the claim holds in context. The rule is explicit: citing the diff line is circular proof; the diff is exactly what the reviewer saw. The validation field on each finding card records what was read and what it confirmed — an empty field means the finding was not validated, and the report gate blocks until it is filled. The cost is one extra read per finding; the benefit is a report that developers can trust rather than one they have to cross-check themselves.

**Why the plan-adversary is generated only when `features.plan_adversary` is true?**
The cheapest point to catch decision gaps is before tickets are created and before any code is written. Once implementation starts, a gap discovered mid-build causes rework — tickets have to be updated, dependencies re-wired, and the plan patched mid-flight. A plan review before execution catches the same gaps at a fraction of the cost. The adversary is gated rather than always-on because it adds latency to every `/plan_w_team` run and not all teams or projects need it — simpler projects with well-understood problem domains may find the overhead disproportionate. The gate lets teams opt in deliberately. When enabled, the adversary runs after the plan is saved but before Beads tickets are written, so findings can be incorporated without orphaned tickets pointing at a superseded task structure.

**Why a sanctioned light tier (`/quickfix`) instead of just letting developers skip the heavy path?**
Without a sanctioned light path, developers who judge a change too small for `/plan_w_team` → `/build` either use the heavy path anyway (wasteful) or quietly skip the workflow entirely (untracked, unreviewed). The light tier makes "skip the ceremony" a gated, auditable decision: the tier check prints explicit criteria every time it runs, so the gate is visible and its reasoning is recorded. The escalation valve — if the builder discovers an open decision mid-fix, it stops, commits the failing test, and hands control to `/plan_w_team` — means the light tier cannot silently grow into a heavy change. The failing test carries forward as the plan's first test requirement, so nothing is lost. The result: the light tier reduces friction for genuinely small changes and prevents workflow erosion by making the boundary explicit rather than leaving it to developer judgment with no accountability.

**Why Dev Decision annotation happens between `/team_review` and `/fix`?**
The cheapest human-in-the-loop point in the review-fix cycle is after findings are synthesized but before any code is changed. At that point, the developer reads the report and marks each finding `fix`, `defer`, or `dismiss` — a judgment call that takes seconds per finding and requires no code context. `/fix` then operates on exactly the developer's chosen scope, not a superset. The alternative — having `/fix` apply all Must Fix findings automatically — removes human judgment from a step that is genuinely judgment-dependent: whether a finding is actionable, whether it conflicts with other work in flight, whether it addresses a risk the developer has already mitigated another way. The plannotator annotation UI makes the annotation step fast (inline editing on the report file) and its output machine-readable (the `Dev Decision:` field in the card) so `/fix` can parse scope without additional user input.
