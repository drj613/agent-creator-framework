# Agent Development Workflow Creator

Every project you start with an AI coding agent requires the same manual setup: configure how the agent behaves, define slash commands, enforce code quality, wire up planning and review workflows. Doing this by hand for each project is tedious and inconsistent.

This repository contains a generator framework that automates that setup. Copy `framework/` into an existing project, tell your agent to run it, answer a few questions about your stack, and it produces a complete, tailored workflow — slash commands, subagents, validation hooks, documentation rules, and more.

**`framework/` is a one-time scaffold. Delete it when setup is done.** The generated files live in your project's agent directory (`.claude/`); the framework is not needed afterward.

---

## What It Creates

| Component | Purpose |
|-----------|---------|
| **Slash commands** | `/dev`, `/plan_w_team`, `/build`, `/ship`, `/finish`, `/team_review`, `/fix`, `/quickfix`, `/verify-browser`, `/test`, `/audit-docs`; `/discovery` and `/document` when `deep_discovery` is enabled |
| **Agent team** | Builder (TDD red-green-refactor, auto-validated by hooks), Validator (checks acceptance criteria + tests; saves E2E specs only when a plan enables it), Questioner (naive questions, fresh eyes), Plan Adversary (eight-lens gap analysis of every plan before execution), and project-specific domain reviewers (security always present; 2–4 others authored from the discovered stack) |
| **Two-tier workflow** | Heavy tier for work with open design decisions (`/plan_w_team → /build → /ship → /team_review → /fix → /finish`); light tier for forced fixes (`/quickfix`, with a gate that verifies the change qualifies and an escalation valve back to the heavy tier) |
| **Validated review** | `/team_review` runs parallel specialists, then **validates every finding against the checked-out code** before it reaches the report; the dev marks each finding fix/defer/dismiss and `/fix` applies only the chosen ones |
| **Issue tracking** _(optional, `beads_tickets`)_ | Beads (`br`) tickets woven through the lifecycle — plans create tickets, builds update them, `/ship` warns on open ones |
| **GitHub PR flow** _(optional, `github_flow`)_ | `/ship` opens draft PRs; `/team_review` cross-references PR review comments (e.g. Copilot); `/fix` posts inline resolution replies |
| **PostToolUse hooks** | Auto-lint and type-check every file write; env check on session start; doc staleness warning on commit |
| **Rules** | Commit workflow (docs before code) and documentation discipline (permanent vs temporary docs) |
| **Skills** | Onboarding flow that installs deps, runs tests, starts servers, offers a code walkthrough |
| **Doc structure** | `docs/` with permanent files, `specs/` for plans, staleness detection, and audit tooling |
| **Deep discovery** _(optional)_ | Batched, checkpointed, resumable codebase analysis built to survive giant legacy monoliths: legacy-aware module boundary detection, git-churn activity classes (hot/warm/cold) driving doc depth, framework-era detection with "do not imitate" warnings, and an evidence rule — every behavioral claim in a module doc carries a `path:line` citation or is demoted to an open question. `/document` generates `docs/modules/<module>.md` plus a routing table; `/audit-docs` decays each doc's confidence by code drift. |

All components are optional — discovery asks which features to enable and skips the rest. Some features have dependencies (`audit_docs` requires `documentation_structure`; `plan_adversary` and `light_tier` require `plan_build`).

---

## The Workflow It Produces

Once setup is complete, the first question for any change is the **tier decision rule**: open decisions to make → heavy tier; forced fix with no decisions → light tier.

**Heavy tier** — features and anything with design decisions:

```
/plan_w_team "add user authentication"     # Analyze codebase, save spec, adversarial review, tickets
  ↓
  review and annotate the spec
  ↓
/build specs/add-user-auth.md              # Pre-flight check, dispatch TDD builders + validator
  ↓
  builder writes code red-green-refactor (auto-linted by hooks on every save)
  spec-compliance review per task; validator checks acceptance criteria + tests
  ↓
/ship specs/add-user-auth.md               # Archive plan, push, open draft PR
  ↓
/team_review                               # parallel specialists; every finding validated against the repo
  ↓
  mark each finding fix / defer / dismiss
  ↓
/fix .reviews/<report>.md                  # apply fix-marked findings, reply on PR threads
  ↓
/finish                                    # merge / flip PR ready / keep / discard
```

**Light tier** — small, decision-free fixes:

```
/quickfix "users can't reset password"     # Tier gate → ticket → one TDD builder → commit
  ↓
/finish → /team_review --light → /fix      # proportionate review: one domain reviewer + questioner
```

If `/quickfix` hits an open decision mid-fix, it stops, commits the failing test, and escalates to `/plan_w_team` — the test carries forward as the plan's first requirement.

Other commands fill in around this cycle:

- `/dev` starts backend + frontend servers in the background
- `/verify-browser` uses `playwright-cli` to walk through recent UI changes
- `/test` runs the test suite with a structured report
- `/audit-docs` detects stale docs, orphaned specs, and doc drift from the codebase

---

## Requirements

Before running setup, confirm you have:

- Claude Code
- `bash` 3.2+ — the macOS system default is sufficient; all scripts are compatible with bash 3.2
- `jq` — required for hook JSON I/O and the generator. On macOS: `brew install jq`; on Linux: `apt-get install jq`
- `git` — required for doc audit co-change analysis and discovery's activity/era classification
- [plannotator](https://github.com/plannotator/plannotator) — the plan/report annotation UI used by `/plan_w_team` and `/team_review` (Dev Decision marking)
- **Optional:** [beads_rust](https://github.com/Dicklesworthstone/beads_rust) (`br`) for the `beads_tickets` feature; `gh` CLI (authenticated) for the `github_flow` feature — the questionnaire auto-detects both
- **Models:** Opus-class for planning, adversarial review, and discovery orchestration; Sonnet-class for building, validation, and per-module discovery analysis. The framework's model tier system configures this automatically during discovery.

---

## Getting Started

### 1. Copy `framework/` into your project

This is not a repository to clone directly into an existing project. Get `framework/` into your project root using one of two methods:

**Download and extract** (run from your project root):

```bash
curl -L <REPO_URL>/archive/refs/heads/main.tar.gz \
  | tar xz --strip-components=1 '*/framework/'
```

**Clone elsewhere, then copy:**

```bash
git clone <REPO_URL> /tmp/agent-workflow-creator
cp -r /tmp/agent-workflow-creator/framework ./
```

Either way, you should now have a `framework/` directory at your project root.

### 2. Run setup

Setup spans **multiple conversations** to stay within context limits. Start the first conversation with this prompt:

> Read the setup guide at `framework/00-setup-guide.md` and run Conversation 1 (Discovery + Generate).

Each conversation saves its output to disk and tells you the exact prompt for the next one. The full sequence:

| Conversation | Steps | What happens |
|---|---|---|
| **1** | Discovery + Generate | Auto-detect stack, ask preferences, run generator |
| **2** | Deep Discovery + Docs | Analyze source code, generate module docs *(only if deep_discovery enabled)* |
| **3** | Context File + Commands | Author project context, workflow guide, all slash commands |
| **4** | Rules + Skills + Docs + Verify | Author rules, skills, doc structure, run verification |

Each conversation starts fresh — state persists via `.discovery-context.json` and `.setup-progress.json`.

### 3. Verify setup, then delete `framework/`

Follow the Post-Setup Verification checklist in `framework/00-setup-guide.md`. Once all checklist items pass, remove the framework and setup state files:

```bash
rm -rf framework/
rm -f .claude/.discovery-context.json .claude/.setup-progress.json   # adjust path for your agent_dir
```

The framework directory and setup state files are not needed after verified setup — everything lives in your agent directory.

---

## How It Works

Setup runs in two distinct phases with different mechanics.

**Phase 1 — Generator** (`framework/generator/generate.sh`)

Reads the discovery JSON produced during setup and outputs deterministic files: one hook script per linter and type-checker, `check-env.sh`, `audit-docs-hook.sh`, `audit-docs.sh`, `builder.md`, `validator.md`, `questioner.md`, `plan-adversary.md` (when enabled), `scripts/wait-for-copilot.sh` (when `github_flow` is enabled), and the directory scaffolding. This phase makes no judgment calls — the same discovery JSON always produces the same output, and you can reproduce it by re-running the generator. Correctness here (file paths, platform-appropriate frontmatter, per-tool configuration) is guaranteed by the script, not by the model.

**Phase 2 — Agent authoring**

Files that require project-specific prose — the context file, slash command bodies, commit and documentation rules, the onboarding skill — are written by the agent using templates from `framework/generator/templates/` as starting points. The agent fills in your project's actual architecture, patterns, commands, and conventions.

This split exists because the two kinds of output have different failure modes. Mechanical files (correct shell paths, valid YAML frontmatter, per-linter command invocations) are error-prone when improvised by a model; a script eliminates that whole class of bugs. Prose files are error-prone when templated; they need the model to synthesize project context rather than fill in slots.

---

## Project Structure

```
agent-workflow-creator/
├── README.md                          # This file
└── framework/                         # Copy this into your project, delete after setup
    ├── 00-setup-guide.md              # Entry point — steps, verification checklist
    ├── 01-discovery.md                # Auto-detect stack + user questionnaire → discovery JSON
    ├── 01a-deep-discovery.md          # Deep codebase analysis → JSON artifacts (deep_discovery feature)
    ├── 01b-document-generation.md     # Generate module docs from discovery artifacts (deep_discovery feature)
    ├── 02-context-file.md             # Project context file + bash best practices reference
    ├── 03-commands.md                 # Slash command definitions
    ├── 04-agents.md                   # Builder/validator architecture + customization guide
    ├── 05-hooks.md                    # Hook I/O contract, validator template
    ├── 06-rules.md                    # Commit workflow and documentation rules
    ├── 07-skills.md                   # Onboarding skill + skill creation guide
    ├── 08-docs-structure.md           # docs/ structure, specs/ lifecycle, staleness heuristics
    ├── bash-best-practices.md         # Shell command guidelines (referenced in context file)
    ├── orchestration-reference.md     # Task management tool docs (shared by /plan_w_team and /build)
    ├── DESIGN.md                      # Design rationale — why decisions were made (human reference)
    └── generator/
        ├── generate.sh                # Entry point — reads discovery JSON, runs all generators
        ├── lib/
        │   ├── helpers.sh             # Shared utilities (jq_read, write_file, etc.)
        │   └── validate.sh            # Discovery JSON schema validation
        ├── generators/
        │   ├── validators.sh          # Hook validator scripts (one per linter/type-checker)
        │   ├── hooks.sh               # check-env.sh, audit-docs-hook.sh, audit-docs.sh
        │   ├── agents.sh              # builder.md + validator.md + questioner.md + plan-adversary.md
        │   └── gitignore.sh           # .gitignore entries for validator logs
        └── templates/                 # Starter templates for prose-heavy generated files
            ├── README.md              # Template index and usage guide
            ├── commands/              # /dev, /plan_w_team, /build, /ship, /finish, /team_review, /fix, /quickfix, /verify-browser, /test, /audit-docs, /discovery, /document
            ├── scripts/               # wait-for-copilot.sh (PR review poll, github_flow only)
            ├── context/               # CLAUDE.md context file template
            ├── rules/                 # commit-workflow.md, documentation-rules.md
            └── skills/onboard/        # SKILL.md onboarding template
```

---

## Key Design Decisions

- **Plan/build separation** creates a reviewable artifact between design and execution — you can edit the spec before anything runs
- **Adversarial plan review** — every plan is stress-tested through eight lenses (open decisions, cross-layer contracts, failure modes, blast radius, …) before tickets are created, the cheapest point to catch a gap
- **Two tiers, one gate** — a sanctioned light path for forced fixes prevents workflow erosion; the gate is auditable and escalation back to planning is cheap and blameless
- **Hooks block, not log** — if a linter fails, the builder must fix it before continuing; this changes agent behavior in practice, not just in theory
- **Parallel review specialists, validated findings** — each specialist reads the full diff with undivided attention on one dimension; then every finding is verified against the checked-out code before it reaches the report, because multi-agent review's top failure mode is confident unverified findings
- **Evidence-cited docs** — generated module docs may only assert what they can cite (`path:line`); everything else becomes an open question instead of plausible-sounding filler
- **Single retry limit on build errors** — one retry catches transient issues; beyond that, human judgment is needed

Full rationale in [`framework/DESIGN.md`](framework/DESIGN.md).

---

## Adapting the Framework

The framework is designed to be forked and extended:

- **Add review specialists** — create additional `reviewer-<domain>.md` files in `{{agent_dir}}/agents/team/`; the `/team_review` command picks them up automatically
- **Add skills** — create `{{agent_dir}}/skills/<name>/SKILL.md` for domain-specific instruction sets (design system, API conventions, database patterns)
- **Add agents** — create new `.md` files in `{{agent_dir}}/agents/team/` for specialized builders (e.g., `frontend-builder.md`, `migration-builder.md`)
- **Adjust thresholds** — `audit-docs.sh` accepts `--days-high`, `--days-medium`, `--specs-max-age` flags

---

## Undoing Setup

To remove what the generator created from your project:

- Delete the agent directory (`{{agent_dir}}/` — `.claude/`)
- Delete `WORKFLOW.md` and `CHANGELOG.md` from the project root (if created by the framework)
- Delete `docs/` and `specs/` directories (if created by the framework — check git blame to verify)
- Remove any `.gitignore` entries added for hook log files

---

## Known Limitations

- **Monorepo support is partial** — discovery detects monorepos and classifies them; `deep_discovery` includes workspace-aware module scoping (per-workspace boundaries, cross-workspace dependency tracking). However, hook path derivation, per-package agent directories, and multi-language root handling still require manual adjustment after setup
