# Agent Development Workflow Framework — Setup Guide

A portable setup guide for establishing an AI-assisted development workflow in any project. Give this framework to an agent and it will create all the files described below, adapted to your specific tech stack.

---

## What This Workflow Provides

- **Slash commands** for common development tasks (start servers, plan features, build from a plan, review changes, verify UI, run tests, audit docs)
- **Subagent team** with distinct roles (builder, validator, domain reviewers) and enforced constraints
- **PostToolUse hooks** that auto-validate every file write (lint + type check) before the agent continues, plus lightweight commit-time doc staleness checks and session-start env verification
- **Rules** that govern commit hygiene and documentation discipline
- **Skills** for loading specialized instruction sets on demand, including a structured onboarding flow
- **Documentation structure** with staleness detection and specs lifecycle management

---

## Directory Structure Created

The exact directory name depends on your agent platform (`.claude/`, `.opencode/`, etc.). All paths below use `{{agent_dir}}` as a placeholder — discovery (Step 1) resolves it.

```
{{agent_dir}}/
├── {{context_filename}}             # Project context injected into every session
├── bash-best-practices.md           # Shell command guidelines (referenced in context file)
├── commands/
│   ├── dev.md                       # /dev — start dev servers
│   ├── plan_w_team.md                # /plan_w_team — create a spec/implementation plan
│   ├── build.md                     # /build — pre-flight check then execute a plan
│   ├── review.md                    # /review — parallel domain-specialist code review
│   ├── verify-browser.md            # /verify-browser — playwright-cli UI verification
│   ├── test.md                      # /test — run test suite with reporting
│   ├── audit-docs.md                # /audit-docs — documentation health check
│   └── fix.md                       # /fix — apply Must Fix items from /review output (requires review feature)
├── agents/
│   └── team/
│       ├── builder.md               # Focused coding agent with hook-based validation
│       ├── validator.md             # Read-only verification agent
│       ├── questioner.md            # Naive questions — fresh eyes, no domain expertise
│       ├── reviewer-security.md     # Always authored — cross-cutting security pass
│       └── reviewer-<domain>.md     # Authored — 2–4 project-specific domain specialists
├── hooks/
│   ├── validators/                  # PostToolUse validators (one per linter/type-checker)
│   ├── audit-docs.sh                # Deterministic audit data collection → JSON output
│   ├── check-env.sh                 # Session-start .env presence check
│   └── audit-docs-hook.sh           # Post-commit temporary doc staleness warning
├── rules/
│   ├── commit-workflow.md           # Pre-commit documentation requirement
│   └── documentation-rules.md      # Doc hierarchy, where changes belong
└── skills/
    └── onboard/
        └── SKILL.md                 # New developer / new agent onboarding flow
docs/                                # Documentation structure (project root)
├── README.md                        # Master index with "When to Update" table
├── ARCHITECTURE.md
├── DEVELOPMENT.md
├── DEPLOYMENT.md
├── DECISIONS.md
├── PERFORMANCE.md
└── modules/                         # Per-module docs from /discovery + /document (deep_discovery)
    └── <module>.md                  # Module doc with YAML frontmatter
CHANGELOG.md                         # Version history (project root)
WORKFLOW.md                          # Human-readable workflow guide (project root)
specs/                               # Plan output from /plan_w_team (project root)
```

> Not all components are created in every project. Step 1 (Discovery) asks which features to enable, and subsequent steps skip disabled components.

---

## Prerequisites

Before starting setup, verify these tools are installed:

| Tool | Minimum | Check | Install (macOS) |
|------|---------|-------|-----------------|
| bash | 3.2 | `bash --version` | macOS system default is sufficient |
| jq | 1.6 | `jq --version` | `brew install jq` |
| git | any | `git --version` | Xcode Command Line Tools |

---

## How to Use This Framework

Setup is designed to span **multiple conversations** to avoid context window overflow. Each conversation handles one or two steps, persists its output to disk, and tells you what to do next.

**Start the first conversation** by giving the framework directory to an agent and saying:

> "Read the setup guide at `framework/00-setup-guide.md` and run **Conversation 1** (Discovery + Generate) to set up the agent development workflow for this project."

When a conversation completes, it will tell you to **start a fresh chat** and give you the exact prompt for the next conversation. The agent reads each step file sequentially, using the discovery context from Step 1 to fill in all project-specific values.

> **Templating notation:** The `{{discovery.*}}` syntax used throughout the step files is pseudo-templating for the setup agent to interpret — it is not a real template engine. The forms are instructions for the agent to read and resolve using the discovery context from Step 1.
>
> **Syntax reference:**
>
> | Syntax | Meaning | Example |
> |--------|---------|---------|
> | `{{field}}` | Direct substitution — replace with the field's value | `{{discovery.app_description}}` |
> | `{{#if field}}...{{/if}}` | Conditional — include block only if field is truthy (non-null, non-false, non-empty). Use `{{else}}` for an alternate branch: `{{#if field}}...{{else}}...{{/if}}` | `{{#if discovery.dev_servers.backend}}...{{/if}}` |
> | `{{#if field == "value"}}...{{/if}}` | Equality conditional — include block only if field equals the given string value | `{{#if discovery.platform == "opencode"}}...{{/if}}` |
> | `{{#each array}}...{{/each}}` | Loop — repeat block for each item; inside, `{{name}}` refers to the item's `name` field. For primitive arrays (e.g., `string[]`), use `{{.}}` to access the current item | `{{#each discovery.linters}}...{{/each}}` |
> | `{{field or 'default'}}` | Fallback — use the field's value if truthy, otherwise use the default | `{{discovery.directories.backend_root or ''}}` |
> | `{{array[0].field}}` | Numeric index — access a specific item by position | `{{discovery.linters[0].cmd}}` |
> | `{{array[n].field}}` | Placeholder index — `[n]` means "for each entry"; create one instance per array item | `{{discovery.linters[n].name}}_validator.sh` |
> | `{{.}}` | Current item — inside `{{#each}}` over a primitive array (e.g., `string[]`), refers to the current string value | `{{#each discovery.languages}}{{.}}{{/each}}` |
> | `{{array[key].field}}` | Semantic index — select the entry whose `language` field matches `discovery.directories.<key>_lang` (e.g., `[backend]` resolves the backend language from discovery, then finds the array entry with that language) | `{{discovery.linters[backend].cmd}}` |
> | `{{../field}}` | Parent scope — inside `{{#each}}`, access a field from the outer context | `{{../discovery.linters[0].cmd}}` |
> | `{{field \| join(sep)}}` | Pipe filter — transform the value; `join(", ")` joins an array with the given separator | `{{discovery.env_files.found \| join(", ")}}` |
>
> **Null/empty handling:** If a `{{field}}` resolves to `null` or is absent from the discovery context, omit it entirely (do not output the literal string "null"). If an `{{#each}}` array is empty or null, produce no output for that block. If an `{{#if}}` field is null, false, or empty, skip the block.
>
> **Important:** Always start a **fresh chat** for each conversation boundary listed in the Setup Steps section below. This prevents context overflow and ensures each step gets the agent's full attention. State is persisted to disk between conversations via `.discovery-context.json` and `.setup-progress.json`.

> **Truthiness rules for `{{#if}}`:**
> - `null`, `false`, `""` (empty string), `[]` (empty array) → **falsy** (skip block)
> - `0` → **falsy**
> - Any non-empty string, non-zero number, `true` → **truthy** (include block)
> - An object (even `{}`) → **truthy** — use `{{#if obj.specific_field}}` to test a specific property instead
> - Example: `{{#if discovery.dev_servers.backend}}` is truthy if `backend` is an object with any properties, even if `cmd` is the only field set. To check for a specific property, use `{{#if discovery.dev_servers.backend.cmd}}`.

---

## Setup Steps

Setup is organized into **conversations** — each conversation runs one or two steps, persists results to disk, and ends by telling you to start a fresh chat. This prevents context overflow while keeping all state available across sessions.

> **Minimal setup (Conversations 1 + 3):** If you want just `/plan_w_team` + `/build` with automatic lint/type-check validation, you only need Conversations 1 and 3. Conversation 4 adds commit rules, onboarding skills, and documentation structure — it can be added later without re-running earlier steps.

### Progress Tracking

The setup agent maintains a progress file at `{{agent_dir}}/.setup-progress.json`:

```json
{
  "completed_steps": [],
  "current_step": null,
  "features_enabled": {},
  "started_at": "ISO-8601",
  "last_updated": "ISO-8601"
}
```

**Canonical step names** — use these exact strings in `completed_steps`:

| Step | String | Conversation |
|------|--------|-------------|
| Discovery | `"discovery"` | 1 |
| Generate | `"generate"` | 1 |
| Deep Discovery | `"deep_discovery"` | 2 |
| Document Generation | `"doc_generation"` | 2 |
| Context File | `"context_file"` | 3 |
| Commands | `"commands"` | 3 |
| Rules | `"rules"` | 4 |
| Skills | `"skills"` | 4 |
| Docs Structure | `"docs_structure"` | 4 |
| Verification | `"verification"` | 4 |

**At the start of each conversation:** Read `{{agent_dir}}/.discovery-context.json` (for the discovery context) and `{{agent_dir}}/.setup-progress.json` (to verify prerequisites and avoid re-doing completed steps). If any required prerequisites (steps from prior conversations) are not listed in `completed_steps`, **stop immediately** and tell the user which conversation to run first. Do not proceed with incomplete prerequisites.

**At the end of each conversation:** Update `.setup-progress.json` with the completed steps, then tell the user:
1. What was completed
2. To start a **fresh chat**
3. The exact prompt to give the agent for the next conversation

---

### Conversation 1: Discovery + Generate (Steps 1 + 1.5)

**Prompt:** _"Read `framework/00-setup-guide.md` and run Conversation 1 (Discovery + Generate)."_

**Step 1: Discovery** (`01-discovery.md`)

Auto-detect the project's tech stack (languages, linters, type checkers, test runners, formatters, package managers, env files, project structure). For monorepos, enumerate workspaces with per-package test and dev server configs. Ask the user questions that cannot be auto-detected (platform, model preferences, app description, dev servers, feature selection). Output: a structured `DISCOVERY_CONTEXT` that all subsequent steps reference via `{{discovery.field}}` notation.

**Persistence:** After compiling the discovery context, write it to `{{agent_dir}}/.discovery-context.json` as JSON. This enables resuming from a partial setup (if the session is interrupted, later steps can read the file instead of re-running discovery) and supports idempotent re-runs. Remove or archive this file after setup is complete.

**No user-facing files are created in this step.** Discovery must complete before proceeding.

**Step 1.5: Generate Files** (`framework/generator/generate.sh`)

Run the generator to produce all deterministic files from the discovery context.

Use `--dry-run` to preview files without writing them (for review only):

```bash
bash framework/generator/generate.sh {{agent_dir}}/.discovery-context.json --dry-run
```

For the recommended production invocation, include `--validate-output` to verify all output files after generation:

```bash
bash framework/generator/generate.sh {{agent_dir}}/.discovery-context.json --validate-output
```

The generator reads the discovery JSON and creates:
- One validator hook script per linter and type checker (`hooks/validators/{name}_validator.sh`)
- `hooks/check-env.sh`, `hooks/audit-docs-hook.sh`, `hooks/audit-docs.sh`
- `agents/team/builder.md`, `agents/team/validator.md`, `agents/team/questioner.md`
- `.gitignore` entries for validator log files
- Directory structure (`hooks/validators/`, `agents/team/`, `specs/`, `specs/archive/`)
- `{{agent_dir}}/discovery/` directory (if `deep_discovery` is enabled)
- `docs/modules/` directory and `docs/modules/ROUTING.md` stub (if `deep_discovery` is enabled)

To understand or customize the generated files, see the supporting references: `04-agents.md` explains the builder/validator architecture and OpenCode adaptation; `05-hooks.md` documents the hook I/O contract and validator template.

**End of Conversation 1:** Update `.setup-progress.json`, then tell the user:

> Conversation 1 complete. Discovery context saved and generator files created.
>
> **If `deep_discovery` is enabled:** Start a fresh chat and say: _"Read `framework/00-setup-guide.md` and run Conversation 2 (Deep Discovery + Document Generation)."_
>
> **If `deep_discovery` is disabled:** Start a fresh chat and say: _"Read `framework/00-setup-guide.md` and run Conversation 3 (Context File + Commands)."_

---

### Conversation 2: Deep Discovery + Document Generation (Steps 1.7 + 1.8)

> **Feature gate:** Only run this conversation if `{{discovery.features.deep_discovery}}` is true. Skip to Conversation 3 otherwise.

**Prompt:** _"Read `framework/00-setup-guide.md` and run Conversation 2 (Deep Discovery + Document Generation)."_

**Step 1.7: Deep Discovery** (`01a-deep-discovery.md`)

Perform deep codebase analysis beyond tooling detection. Reads actual source files to understand architecture, patterns, module boundaries, data flows, and conventions. Three phases: structure scan, deep per-module analysis, and question generation (presenting uncertainties to the user for clarification).

Output: structured JSON artifacts in `{{agent_dir}}/discovery/` (`context.json`, `modules.json`, `questions.json`, `history.json`). These artifacts feed into Step 1.8.

**Step 1.8: Document Generation** (`01b-document-generation.md`)

Transform deep discovery artifacts into populated documentation. Generates `docs/modules/<module>.md` files with YAML frontmatter, populates stub permanent docs (`ARCHITECTURE.md`, `DEVELOPMENT.md`), adds a routing table to the context file, and updates `docs/README.md` with a module index.

Human-written content is never overwritten. Sections marked `<!-- human-maintained -->` are preserved during updates.

**End of Conversation 2:** Update `.setup-progress.json`, then tell the user:

> Conversation 2 complete. Deep discovery artifacts and module docs created.
>
> Start a fresh chat and say: _"Read `framework/00-setup-guide.md` and run Conversation 3 (Context File + Commands)."_

---

### Conversation 3: Context File + Commands (Steps 2 + 3)

**Prompt:** _"Read `framework/00-setup-guide.md` and run Conversation 3 (Context File + Commands)."_

**Step 2: Context File** (`02-context-file.md`)

Create the project context file (`CONTEXT.md` / `CLAUDE.md`), the `bash-best-practices.md` reference, and `WORKFLOW.md` at the project root. The context file is injected into every agent session. The workflow guide is a human-readable reference explaining available commands, the development cycle, and enforced rules.

**Step 3: Slash Commands** (`03-commands.md`)

Create command files for each enabled feature: `/dev`, `/plan_w_team`, `/build`, `/review`, `/fix`, `/verify-browser`, `/test`, `/audit-docs`. Each command has frontmatter (description, model override, tool restrictions) and a step-by-step instruction body.

**End of Conversation 3:** Update `.setup-progress.json`, then tell the user:

> Conversation 3 complete. Context file, workflow guide, and all slash commands created.
>
> Start a fresh chat and say: _"Read `framework/00-setup-guide.md` and run Conversation 4 (Rules + Skills + Docs + Verification)."_

---

### Conversation 4: Rules + Skills + Docs + Verification (Steps 5 + 6 + 7 + Verification)

**Prompt:** _"Read `framework/00-setup-guide.md` and run Conversation 4 (Rules + Skills + Docs + Verification)."_

**Step 5: Rules** (`06-rules.md`)

Create `commit-workflow.md` (pre-commit documentation requirement) and `documentation-rules.md` (doc hierarchy, permanent vs temporary docs, ADR format).

**Step 6: Skills** (`07-skills.md`)

Create the `onboard` skill for automated project setup and code walkthrough. Establish the skills directory for future specialized instruction sets.

**Step 7: Documentation Structure** (`08-docs-structure.md`)

Create the `docs/` directory with permanent doc files and the master index. Create the `specs/` directory for plan output. Includes staleness heuristics and specs audit lifecycle for the `/audit-docs` command.

**Verification:** Run the Post-Setup Verification checklist (below) to confirm everything is correct.

**End of Conversation 4:** Update `.setup-progress.json` with all steps complete, then tell the user:

> Setup complete. All files created and verified.
>
> You can now delete the `framework/` directory: `rm -rf framework/`
>
> Run `/test` for a smoke test, then try `/plan_w_team "your first feature"` to start building.

---

## Resuming Setup

If a conversation is interrupted or you need to restart from a specific point:

1. **Read progress:** The agent reads `{{agent_dir}}/.setup-progress.json` to see what's done.
2. **Skip completed steps:** Any step listed in `completed_steps` is skipped.
3. **Resume the current conversation:** Give the agent the prompt for the conversation that contains uncompleted steps.

If `.discovery-context.json` exists but `.setup-progress.json` does not, the agent should create the progress file and mark Step 1 as complete (since discovery context implies discovery finished).

If both files are missing, start from Conversation 1.

---

## Supporting References

These files are not setup steps but are referenced by the step files:

- **`04-agents.md`** — Builder and validator architecture reference. Covers frontmatter, model selection, tool restrictions, OpenCode adaptation, and the instruction templates the generator uses. Read this to understand or customize generated agent files.
- **`05-hooks.md`** — Hook script reference. Documents the hook I/O contract, validator template, `check-env.sh`, `audit-docs-hook.sh`, `audit-docs.sh`, and OpenCode plugin wrappers. Read this to understand or customize generated hook scripts.
- **`orchestration-reference.md`** — Task management tool documentation (TaskCreate/TaskUpdate/Task for Claude Code; todowrite/todoread/task for OpenCode; Resume pattern). Referenced by `/plan_w_team` and `/build` commands.
- **`DESIGN.md`** — Human-readable rationale for design decisions. Not consumed during setup — exists for framework maintainers and curious users.

---

## Post-Setup Verification

After completing all steps, run this automated verification pass:

**Quick check:** Verify the test command exists: `ls {{agent_dir}}/commands/test.md`. If the file is present, run `/test` for a structured smoke test. If missing, check that `features.test` was enabled in discovery and re-run the generator.

**Template resolution check:** Scan all generated files for unresolved template markers. Search for `{{` in all files under `{{agent_dir}}/`. Any remaining `{{discovery.*}}` markers indicate a template that was not resolved during setup. Also search for the literal string `null` in command positions (e.g., in hook scripts or frontmatter `command:` fields) — this indicates a discovery field that resolved to null but was not omitted.

**File checklist:**

- [ ] `WORKFLOW.md` exists at the project root with commands, cycle, and rules
- [ ] Context file exists and contains accurate project-specific content
- [ ] `bash-best-practices.md` exists in `{{agent_dir}}/`
- [ ] All enabled commands are present in `{{agent_dir}}/commands/`
- [ ] Builder, validator, and questioner agents exist in `{{agent_dir}}/agents/team/`
- [ ] `reviewer-security.md` exists in `{{agent_dir}}/agents/team/`
- [ ] At least 2 domain reviewer files (`reviewer-*.md`) exist in `{{agent_dir}}/agents/team/`
- [ ] One validator hook script (`.sh`) exists per detected linter/type-checker
- [ ] `audit-docs.sh`, `check-env.sh`, and `audit-docs-hook.sh` exist in `{{agent_dir}}/hooks/`
- [ ] Validator log files (`*_validator.log`) are in `.gitignore`
- [ ] Rule files exist if commit/doc rules were enabled
- [ ] Onboarding skill exists if enabled
- [ ] `docs/README.md` exists with the "When to Update" table (or was already present)
- [ ] `CHANGELOG.md` exists at the project root (if documentation_structure enabled)
- [ ] `specs/` and `specs/archive/` directories exist if plan/build was enabled
- [ ] If `deep_discovery` enabled: `{{agent_dir}}/discovery/` contains `context.json`, `modules.json`, `questions.json`
- [ ] If `deep_discovery` enabled: `docs/modules/` contains at least one module doc with valid YAML frontmatter
- [ ] If `deep_discovery` enabled: `docs/modules/ROUTING.md` exists with at least one routing entry
- [ ] Run `/audit-docs` to establish a baseline for existing documentation

**Cleanup:** Once all checklist items pass, remove the framework directory and setup state files:

```bash
rm -rf framework/
rm -f {{agent_dir}}/.discovery-context.json
rm -f {{agent_dir}}/.setup-progress.json
```

Everything the framework created is self-contained in your agent directory. The `framework/` directory and setup state files are not needed after successful setup.

## Idempotency

If re-running setup (e.g., after adding a new linter to the project):

- **Discovery (Step 1):** Re-run fully. Auto-detection will pick up new tooling. User questions will be re-asked — answer based on current state.
- **Generated files (Steps 2–8):** Overwrite existing files with updated content. Preserve any sections marked with `# custom` comments — these indicate user customizations that should be merged, not replaced.
- **Hook scripts:** Add new validators for newly detected tools. Remove validators for tools no longer detected. Leave existing validators unchanged if their tool is still present.

## Post-Setup: Initial Audit

Run `/audit-docs` immediately after setup to assess the current state of any existing documentation. This establishes a baseline and surfaces any pre-existing issues before the workflow rules take effect.
