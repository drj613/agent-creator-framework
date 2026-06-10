# Step 1.7 — Deep Discovery

> **Part of Conversation 2.** At the start of this conversation, read `{{agent_dir}}/.discovery-context.json` to load the discovery context and `{{agent_dir}}/.setup-progress.json` to verify that `"discovery"` and `"generate"` are in `completed_steps`. If either is missing, **stop** and tell the user: "Prerequisites incomplete. Please run Conversation 1 first."
> **Skip if complete:** If `"deep_discovery"` is already in `completed_steps`, skip this step and proceed to `01b-document-generation.md`.

> **Feature gate:** Only run this step if `{{discovery.features.deep_discovery}}` is true.

> **Standalone command:** This step also powers the `/discovery` command. The command template at `templates/commands/discovery.md` is the operational spec — it carries the exact shell commands, subagent dispatch contract, checkpoint writes, and `--resume` semantics. **This guide and that command MUST agree exactly on every schema, formula, file name, and threshold.** This guide is the reference/rationale layer for the setup-authoring agent; the command is what runs. When you (the setup-authoring agent) emit the `/discovery` command for a target project, transcribe the schemas and formulas here verbatim into the command and adapt only the language-specific recipe (Phase A) to the project's stack.

## Prerequisites

- Discovery context from Step 1 (tooling detection complete)
- Generator output from Step 1.5 (directory structure exists)

## Overview

Step 1 detects tooling metadata (linters, test runners, package managers). This step goes deeper: it reads actual source code to understand architecture, patterns, module boundaries, data flows, and conventions. The output feeds into Step 1.8 (Document Generation) to produce populated module docs.

This pipeline is **hardened for large, old, undocumented codebases** — a 20-year-old monolith with 500+ flat models, no service layer, dead code, and mixed framework eras must still produce useful docs instead of failing on context limits or mis-bounding modules. The hardening rests on five pillars:

1. **Batched, resumable analysis** — a checkpoint file (`run-state.json`) lets a run span multiple sessions; every batch is checkpointed so a crash or context exhaustion loses at most one batch.
2. **Activity weighting** — git churn classifies each module hot/warm/cold so analysis effort (and doc depth) tracks where the code actually lives, not where it sprawls.
3. **A legacy-codebase boundary recipe** — deterministic clustering moves (namespace, association hub-and-spoke, fan-in service detection, merge-to-5–15) replace "directory-per-feature" when the tree is flat.
4. **An evidence rule** — every behavioral claim a subagent emits must carry a `path:line` or `path#method` citation; uncitable claims become Open Questions, never silent prose. This is what stops doc drift.
5. **Era detection + confidence decay** — old code is tagged so docs warn "do not imitate," and confidence decays as the code churns past the analysis commit.

**Three phases:**
1. **Phase A — Structure Scan & Boundary Detection:** Map the tree, classify module boundaries (legacy recipe when flat), compute activity classes, detect eras, write the skeleton checkpoint + batch plan.
2. **Phase B — Deep Analysis (batched, dispatched):** Per-batch source reading via subagents that return cited findings; orchestrator validates and checkpoints after every batch.
3. **Phase C — Question Discipline:** Rank, cap, and present questions; defer the rest.

## Output Artifacts

All artifacts are written to `{{discovery.agent_dir}}/discovery/`:

| File | Contents |
|------|----------|
| `context.json` | Architecture style, data models, patterns, conventions, era timeline, activity basis |
| `modules.json` | Module boundaries, source paths, read_when, dependencies, **activity, era, analysis_depth, analysis_status, boundary_confidence, findings[], suspected_dead_files** |
| `questions.json` | Questions with `status`, `priority_rank`, `run_id`, user answers |
| `run-state.json` | **Resumable checkpoint:** run_id, head_commit, sizing, batch plan with per-batch status. Deleted (or marked complete) when the run finishes. |
| `history.json` | Append-only audit trail — **one entry per completed multi-session run** |
| `raw/` | Cache dir for expensive git computations (churn, association edge lists, fan-in counts), computed once per run and reused on resume |

### `run-state.json` schema

```json
{
  "schema_version": 1,
  "run_id": "2025-03-15T10-00-00Z-a1b2c3d",
  "mode": "full-batched",
  "head_commit": "a1b2c3d",
  "started_at": "2025-03-15T10:00:00Z",
  "updated_at": "2025-03-15T10:42:00Z",
  "sizing": {
    "total_source_files": 1840,
    "total_source_lines": 410000,
    "git_history_months": 96,
    "shallow": false,
    "has_tests": true
  },
  "phase_a_complete": true,
  "rebound_rounds": 0,
  "batches": [
    {
      "id": "batch-01",
      "tier": "deep",
      "modules": ["billing", "invoicing"],
      "file_count": 31,
      "line_count": 38000,
      "status": "done"
    },
    {
      "id": "batch-02",
      "tier": "deep",
      "modules": ["auth"],
      "file_count": 12,
      "line_count": 9000,
      "status": "in_progress"
    },
    {
      "id": "batch-07",
      "tier": "inventory",
      "modules": ["legacy-reports", "legacy-exports", "legacy-imports", "legacy-feeds", "legacy-misc"],
      "file_count": 60,
      "line_count": 22000,
      "status": "pending"
    }
  ]
}
```

Per-batch `status` is one of `pending | in_progress | done | failed | superseded`. `superseded` marks a batch invalidated by a mid-run module re-bound (see Edge Cases). The batch plan is written at the end of Phase A and is the resumable unit of work.

---

## Phase A: Structure Scan & Boundary Detection

Phase A is deterministic and cheap. It must finish (and checkpoint) before any expensive subagent dispatch, so a resume never re-derives boundaries.

### A.0 Step 0 Preflight — Sizing & History

Before anything else, size the repo and characterize its git history. These numbers drive batch counts, threshold scaling, and the multi-session warning.

```bash
# Source file + line counts (adapt the find extensions to the project's languages)
SRC_FILES=$(git ls-files '*.rb' '*.ts' '*.js' '*.py' '*.go' '*.rs' '*.ex' | grep -vE 'vendor/|node_modules/' | wc -l)
SRC_LINES=$(git ls-files '*.rb' '*.ts' '*.js' '*.py' '*.go' '*.rs' '*.ex' | grep -vE 'vendor/|node_modules/' | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')

# Git history span in months (first commit → now)
FIRST_COMMIT_EPOCH=$(git log --reverse --format=%ct | head -1)
NOW_EPOCH=$(date +%s)
HISTORY_MONTHS=$(awk -v a="$FIRST_COMMIT_EPOCH" -v b="$NOW_EPOCH" 'BEGIN{printf "%d", (b-a)/2629800}')

# Shallow clone?
SHALLOW=$([ -f "$(git rev-parse --git-dir)/shallow" ] && echo true || echo false)
```

- **Estimate batch count:** `ceil(deep_file_count / 30)` deep batches (target ~30 files/batch, hard cap 40) + `ceil(inventory_module_count / 5)` inventory batches. If the estimate exceeds `--max-batches` (default 5), **warn the user this is a multi-session run** and that progress is checkpointed and resumable with `/discovery --resume`.
- **Shallow / short history degradation** (see Edge Cases for the full table): if `HISTORY_MONTHS < 18`, scale activity thresholds linearly (`scale = HISTORY_MONTHS / 18`); if `< 3` months or `SHALLOW == true`, disable activity weighting (all modules `warm`), use pattern-marker-only era detection, and switch staleness/drift to a date basis.
- **Zero-test repos:** detect absence of a test directory / test files; record `has_tests: false` in `run-state.json.sizing`. This propagates to Testing Notes and confidence caps.

Write `run-state.json` sizing block and `context.json` `activity_basis` after this step.

### A.1 Directory Tree Mapping

Read the top two levels of the source directory tree. For each directory, record:
- Path relative to project root
- Approximate file count (by extension)
- Whether it contains an entry point (e.g., `index.ts`, `main.py`, `app.rb`, `main.go`)

Skip directories that are clearly not source code:
- `node_modules/`, `.git/`, `dist/`, `build/`, `__pycache__/`, `.next/`, `target/`, `vendor/` (unless it's the project's own code)
- `{{discovery.agent_dir}}/` (the agent directory itself)

### A.2 Entry Point Identification

Find the application's entry points by scanning for:

| Pattern | Type |
|---------|------|
| `main.ts`, `index.ts`, `app.ts`, `server.ts` | TypeScript entry |
| `main.py`, `app.py`, `wsgi.py`, `asgi.py`, `manage.py` | Python entry |
| `main.go`, `cmd/*/main.go` | Go entry |
| `main.rs`, `lib.rs` | Rust entry |
| `application.rb`, `config.ru` | Ruby entry |
| `lib/<app_name>/application.ex` | Elixir entry |
| Routes/router files (`routes.ts`, `urls.py`, `router.go`, `routes.rb`) | API surface |

Read each entry point file to understand the framework, the structure (MVC, hexagonal, microservice), and the top-level modules/packages imported.

### A.2a Monorepo and Workspace Handling

> Only run this section if `discovery.workspaces` is non-empty (set in Step 1 discovery context).

When the project uses workspaces (npm/Yarn workspaces, Turborepo, Nx, Cargo workspaces, Elixir umbrella apps):

- **Scope:** Treat each workspace as a distinct module boundary. Run Phase B analysis per-workspace, not globally.
- **Module naming:** Prefix module names with the workspace name, e.g., `api/auth`, `web/auth`.
- **Cross-workspace dependencies:** Record as `"workspace:web/auth"` in `depends_on`; mark `type: cross_workspace` on the dependency edge.
- **`source_paths` scope:** Only files within the workspace directory.
- **`read_when` patterns:** Workspace-relative, e.g., `packages/api/src/auth/*`.
- **Shared packages:** Note under a `shared_packages` key in `context.json`.
- **`context.json` scope:** `architecture_style`, `conventions`, `data_models` describe the whole project; add `workspace_overrides` if workspaces differ significantly.

### A.3 Module Boundary Detection

Identify **5–15 logical modules**. When the source tree has a clear feature/directory structure, the original heuristics suffice. When the tree is flat (a legacy monolith), use the Legacy Codebase Recipe in A.3b.

#### A.3a Generic heuristics (well-structured codebases)

In priority order:

1. **Directory-per-feature structure** — `src/auth/`, `src/tasks/`, `src/billing/` → each directory is a module.
2. **Service class boundaries** — `AuthService`, `TaskService` → each service and its related files form a module.
3. **Import clustering** — files that import heavily from each other but sparsely from other groups.
4. **Framework conventions:**
   - **Rails:** `app/models/`, `app/controllers/`, `app/services/`; each major model cluster forms a module.
   - **Express/Fastify:** route file groups + their service/middleware.
   - **Django:** each app directory is a module.
   - **Phoenix:** each context module is a module.
   - **Go:** each package directory is a module.
5. **Explicit boundaries** — `packages/`/`libs/` in monorepos, plugin directories, middleware directories.

#### A.3b Legacy Codebase Recipe (flat trees, no feature dirs)

When the generic heuristics produce a single giant blob (e.g., 500 flat models, fat controllers, no service layer), apply a deterministic clustering pipeline. **This pipeline is language-generic; the worked example below is Rails. Adapt each move to the target stack** — the moves are: namespace clustering → hub-and-spoke by association/import edges → fan-in service detection → merge-to-5–15 → dead-file marking.

Run these in priority order; later steps only place files not yet assigned.

**(1) Engines / path-gems / explicit packages.**
Each in-repo engine or path-dependency package is its own module. (Rails: gems in `engines/` or path-sourced in the Gemfile. Other stacks: workspace packages, Go internal packages, Python sub-packages with their own `setup.py`.)

**(2) Controller namespace clustering (≥3 controllers).**
Cluster by controller namespace; a namespace with ≥3 controllers becomes a module candidate.

```bash
# Rails worked example — controllers grouped by top-level namespace dir
git ls-files 'app/controllers/**/*.rb' \
  | sed -E 's#app/controllers/##; s#/[^/]+$##' \
  | sort | uniq -c | sort -rn
```

(Other stacks: route prefixes / blueprint names / router groups.)

**(3) Model association hub-and-spoke.**
Build an association edge list, find the top fan-in models ("hubs"), and assign spoke models to the hub they share the most edges with. Merge hubs whose spoke sets overlap heavily.

```bash
# Rails worked example — extract association edges (model -> associated)
# cache to raw/ so resume reuses it
grep -rEn '^\s*(has_many|has_one|belongs_to|has_and_belongs_to_many)\s+:[a-z_]+' app/models \
  > {{discovery.agent_dir}}/discovery/raw/assoc-edges.txt

# fan-in: how many models reference each model by class name
grep -rohE '\b[A-Z][A-Za-z0-9]+\b' app/models \
  | sort | uniq -c | sort -rn \
  > {{discovery.agent_dir}}/discovery/raw/class-fanin.txt
```

(Other stacks: import/`require`/`use` edges between source files; the same hub-and-spoke logic applies to import graphs.)

**(4) Routes namespaces + implicit-service fan-in.**
Pick up route-level namespaces missed by controller clustering. Then detect an implicit service layer: classes whose names match `*Manager|*Processor|*Builder|*Service|*Calculator|*Handler` with **fan-in ≥ 10 across ≥ 2 clusters** are collected into a `shared-services` module.

```bash
# Rails worked example — candidate implicit-service classes and their fan-in
grep -rlE 'class\s+[A-Z][A-Za-z0-9]*(Manager|Processor|Builder|Service|Calculator|Handler)\b' app \
  > {{discovery.agent_dir}}/discovery/raw/service-candidates.txt
```

**(5) Merge step — enforce 5–15 modules.**
- Small, low-confidence clusters (≤2 files, or no clear hub) merge into the edge-neighbor module they share the most edges with; if none, into `legacy-misc`.
- If `legacy-misc` ends up holding **> 30% of all source files**, split it by the next-strongest signal (secondary namespace, directory, or filename prefix) until no bucket exceeds 30%.
- Target the final count to **5–15**. Fewer than 5 → split the largest hub. More than 15 → merge the smallest by shared edges.

**(6) Dead-file marking.**
A file is `suspected_dead` when it has **0 commits in 24 months AND zero class-name fan-in** (nothing references its primary class). Record these in the owning module's `suspected_dead_files[]`. Do not delete; the doc will flag them.

```bash
# Rails worked example — 24-month commit count for a file
git log --since="24 months ago" --oneline -- "$file" | wc -l
```

#### Per-module record (written to skeleton `modules.json`)

```yaml
- name: "billing"                          # kebab-case identifier
  title: "Billing & Invoicing"             # human-readable title
  type: module                             # module | service | data-model | integration
  source_paths:                            # files this module owns
    - app/models/invoice.rb
    - app/models/charge.rb
    - app/controllers/billing/invoices_controller.rb
  read_when:                               # broader globs for routing
    - app/models/invoice*
    - app/models/charge*
    - app/controllers/billing/**
  entry_files:                             # main files to read first
    - app/models/invoice.rb
  depends_on: []                           # filled in Phase B
  depended_by: []                          # filled in Phase B
  boundary_confidence: high                # high | medium | low (low = merged/uncertain cluster)
  suspected_dead_files: []                 # 0-commit + 0-fanin files
  activity: {}                             # filled in A.4
  era: {}                                  # filled in A.5
  analysis_depth: null                     # deep | standard | inventory — set by A.4
  analysis_status: pending                 # pending | analyzed | failed
  findings: []                             # the evidence store — filled in Phase B
```

**`read_when` semantics** (unchanged): Unix shell glob (`fnmatch(3)`): `*` matches non-`/`, `**` matches recursively including `/`, `?` matches one char, case-sensitive. Matched against paths relative to project root; a file matches if ANY pattern matches.

**`source_paths` vs `read_when`:**
- `source_paths`: exact files this module owns (used for staleness/drift — git commit counting). **Exclude generated files** (lockfiles, schema dumps — see Edge Cases).
- `read_when`: broader globs for routing.

These should NOT be identical: `source_paths` lists specific files; `read_when` uses broader globs covering the same area plus adjacent files.

### A.4 Activity Classification

Compute git churn per module and classify each. Cache the raw churn once per run:

```bash
# Cache churn once (24-month window), reuse on resume
git log --since="24 months ago" --name-only --format= \
  | grep -vE 'vendor/|node_modules/' | sort | uniq -c | sort -rn \
  > {{discovery.agent_dir}}/discovery/raw/churn-24mo.txt

git log --since="12 months ago" --name-only --format= \
  | grep -vE 'vendor/|node_modules/' | sort | uniq -c | sort -rn \
  > {{discovery.agent_dir}}/discovery/raw/churn-12mo.txt
```

For each module, sum the per-file commit counts across its `source_paths` to get `C12` (commits in 12mo) and `C24` (commits in 24mo), and find the days since the module's most recent commit.

**Classification (apply scaling factor from A.0 to the numeric thresholds when history < 18 months):**

| Class | Rule |
|-------|------|
| **hot**  | `C12 ≥ 15` **OR** (`C12 ≥ 5` AND last commit ≤ 60 days ago) |
| **cold** | `C24 ≤ 2` |
| **warm** | everything else |

**Activity score** (for ranking within a tier): `score = C12 + 0.5 × (C24 − C12)`. Higher = analyze first.

**Depth mapping:** hot → `deep`, warm → `standard`, cold → `inventory`. Write `activity {class, commits_12mo, commits_24mo, score}` and `analysis_depth` into each module record. (The doc-side depth tiers in 01b key off `analysis_depth` and `activity.class`.)

### A.5 Era Detection

Detect the dominant framework era of the codebase and of each module so docs can warn against imitating obsolete patterns. **Era detection is generic; Rails markers are the worked example.** Three signals, combined:

1. **Dependency-manifest history** — sample the lockfile at ~2-year steps and read the framework version:
   ```bash
   # Rails worked example: sample Gemfile.lock across history
   for sha in $(git log --format=%H --since="20 years ago" | awk 'NR==1 || NR%400==0'); do
     ver=$(git show "$sha:Gemfile.lock" 2>/dev/null | grep -A1 '^    rails ' | head -1)
     echo "$sha $ver"
   done > {{discovery.agent_dir}}/discovery/raw/era-manifest.txt
   ```
   (Other stacks: `package-lock.json`/`yarn.lock` framework version, `go.mod`, `Cargo.lock`, `mix.lock`.)
2. **Config markers** — framework defaults pin (Rails: `config.load_defaults 5.2`; other stacks: equivalent compatibility flags).
3. **Dominant commit years per module** — the years in which a module's files were most actively committed.

Combine into an `era` per module and a project-wide `current_era`. Set `imitate: false` when the module's era is materially older than `current_era` (e.g., Rails 3/4 patterns in a Rails 7 app). Below 3 months of history, era detection is **pattern-marker-only** (skip manifest sampling).

```yaml
era:
  tag: "rails-4"                # framework-era label
  evidence: "config/application.rb pins 4.2; bulk of commits 2014–2016; Gemfile.lock rails 4.2.x"
  imitate: false                # false → docs get a "do NOT imitate" warning
```

### A.6 Checkpoint after Phase A

Write the **skeleton `modules.json`** (all fields above, `findings: []`, `analysis_status: pending`) and the **full batch plan** into `run-state.json`. From this point the run is fully resumable: a crash re-enters at Phase B with boundaries, activity, era, and the batch plan intact, and the `raw/` caches already computed.

**Batch planning rules:**
- A batch holds **1–3 same-tier modules**, **≤ 40 files**, **≤ 50,000 lines**.
- **Deep and standard** modules are dispatched to subagents (see Phase B). Pack them densest-first by file count without exceeding the caps; never mix tiers in one batch.
- **Inventory (cold)** modules are batched **5 per batch** and handled by the **orchestrator directly — no dispatch** (cold code is cheap to skim and not worth a subagent round-trip).
- Order batches **hot → warm → cold**, and within a tier by activity `score` descending.

---

## Phase B: Deep Analysis (batched, dispatched)

Phase B walks the batch plan. The orchestrator (running on the command's own model) dispatches each deep/standard batch to a **standard-tier analysis subagent** (`{{discovery.models.standard}}`), validates the returned findings, merges them, and checkpoints. Inventory batches it handles itself.

### B.1 The Evidence Rule (the core contract)

**Every behavioral claim a subagent emits MUST carry a citation** — either `path:line` (a specific line) or `path#method` (a method/function). Claims that cannot be cited are not emitted as findings; they are emitted as questions instead. This is the single rule that prevents doc drift: the doc generator (01b) renders body claims **only** from cited findings.

Citation grammar (validated by regex):
- Line citation: `^[^:]+:[0-9]+$` — e.g. `app/models/invoice.rb:42`
- Method citation: `^[^#]+#[a-zA-Z_?!]+$` — e.g. `app/services/bedrock_service.rb#extract`

### B.2 Subagent Dispatch Contract

For each deep/standard batch, dispatch a subagent on `{{discovery.models.standard}}` with this exact prompt contract (the command template carries the verbatim text; this is the design spec):

The prompt MUST contain:
1. **Global context** — architecture style, `current_era`, conventions (from `context.json`), and the project's read budget.
2. **Module manifest** — for each module in the batch: name, title, `source_paths`, `entry_files`, `boundary_confidence`, `activity.class`, `era`, `suspected_dead_files`.
3. **Read budget** — read entry files first, then highest-fan-in files, then tests; cap at the batch file list (≤40 files). Do not read outside the manifest.
4. **The evidence rule** — every behavioral claim carries `path:line` or `path#method`; uncitable observations go in `questions` (max **5 questions per module**).
5. **The `boundary_verdict` escape hatch** — if a module's files clearly don't belong together (the cluster is wrong), the subagent returns `boundary_verdict` with a suggested re-bound instead of forcing findings.
6. **Output format** — exactly one fenced JSON block, `schema_version: 2`.

**Subagent output schema (one fenced ```json block):**

```json
{
  "schema_version": 2,
  "batch_id": "batch-01",
  "modules": [
    {
      "name": "billing",
      "title": "Billing & Invoicing",
      "type": "module",
      "depends_on": ["database", "auth"],
      "external_deps": ["stripe", "money"],
      "data_flow": "HTTP → InvoicesController#create → Invoice#finalize! → ChargeService → Stripe API",
      "key_patterns": [
        "Invoices are immutable once finalized (Invoice#finalize! freezes line items)"
      ],
      "findings": [
        {
          "claim": "Invoice totals are recomputed from line items on every save, not stored",
          "citation": "app/models/invoice.rb#recalculate_total",
          "kind": "behavior"
        },
        {
          "claim": "MAX_LINE_ITEMS caps an invoice at 500 line items",
          "citation": "app/models/invoice.rb:8",
          "kind": "constant"
        }
      ],
      "testing_notes": "Model spec spec/models/invoice_spec.rb; no E2E coverage found",
      "suspected_dead_confirmed": ["app/models/legacy_invoice_v1.rb"],
      "boundary_verdict": null,
      "questions": [
        {
          "category": "behavior",
          "question": "Is the v1 invoice path still reachable or fully dead?",
          "context": { "file": "app/models/legacy_invoice_v1.rb", "line": 1 },
          "confidence_impact": "medium"
        }
      ]
    }
  ]
}
```

`finding.kind` is one of `behavior | constant | dependency | convention | data-model`. `boundary_verdict`, when non-null, is:

```json
"boundary_verdict": {
  "verdict": "wrong",
  "reason": "reports/* and exports/* share no edges; should be two modules",
  "suggested_modules": [
    { "name": "legacy-reports", "source_paths": ["..."] },
    { "name": "legacy-exports", "source_paths": ["..."] }
  ]
}
```

### B.3 Validation (orchestrator, per batch)

On receiving a subagent's block, the orchestrator validates in this order. **Any failure → one re-dispatch** with the validation errors appended to the prompt; a second failure → orchestrator-fallback (orchestrator analyzes the batch itself, more shallowly); a third failure → mark batch `failed` and continue.

1. **jq parse** — extract the single fenced ```json block and parse it. Malformed JSON fails immediately.
2. **Schema check** — `schema_version == 2`; every module present; required keys present.
3. **Citation regex + file existence** — every `finding.citation` matches `^[^:]+:[0-9]+$` OR `^[^#]+#[a-zA-Z_?!]+$`, and the cited file exists (`test -f`).
4. **Spot-verify** — pick **3 random citations** and confirm them with `sed -n`:
   ```bash
   # line citation path:line
   sed -n "${LINE}p" "$FILE"
   # method citation path#method — confirm the method is defined in the file
   grep -nE "(def|function|fn|func)\s+${METHOD}\b" "$FILE"
   ```
   If a spot-checked citation points at an unrelated line (clearly not supporting the claim), treat as a validation failure.

### B.4 Inventory batches (orchestrator-handled)

For cold/inventory batches, the orchestrator skims each module itself: read 1–2 representative files, record a one-line purpose, a file→class inventory, and the `suspected_dead_files`. No findings citations are required at inventory depth (the doc will be explicitly hedged). Confidence is capped `low`.

### B.5 Checkpoint after every batch

After validation succeeds (or fallback/failure is recorded), **merge the batch result into `modules.json`** (`findings[]`, `depends_on`, `data_flow`, `key_patterns`, `analysis_status: analyzed|failed`), **append any questions into `questions.json`** (status `deferred` initially, `run_id` stamped), and **update `run-state.json`** (batch `status`, `updated_at`). This is what makes a crash lose at most one batch.

**Default 5 batches per session** (`--max-batches`). When the session budget is hit with batches still `pending`, write a final checkpoint and tell the user to run `/discovery --resume`.

### B.6 Cross-Module Dependency Mapping & Global Patterns

After all batches in scope are analyzed (or at the end of a session), reconcile `depends_on`/`depended_by` from the subagents' reported `depends_on`, flag circular dependencies and hub modules, and synthesize the global `architecture_style`, `conventions`, and `patterns` for `context.json`.

---

## Phase C: Question Discipline

### C.1 Recording

Each question (whether raised by a subagent or the orchestrator) MUST include a `module` field matching a name in `modules.json` — never null; if uncertain, use the module whose `source_paths` most closely match `context.file`.

```yaml
- id: "q-001"
  module: "billing"
  run_id: "2025-03-15T10-00-00Z-a1b2c3d"
  category: architecture | pattern | convention | dependency | behavior
  question: "Is the v1 invoice path still reachable or fully dead?"
  context: { file: "app/models/legacy_invoice_v1.rb", line: 1 }
  confidence_impact: high | medium | low
  priority_rank: 3                  # computed at presentation time
  status: asked | deferred | answered | skipped
  suggested_answer: null
  user_answer: null
```

**Categories:** architecture, pattern, convention, dependency, behavior.

### C.2 Ranking & Capping

Present **at most 12 questions per session**, ranked by:
1. `confidence_impact: high` first,
2. then questions for **hot** modules,
3. then by module activity `score`.

Mark presented questions `status: asked`; everything else stays `status: deferred`. Subagents are capped at **5 questions per module** at source (B.2) so a single noisy module can't flood the backlog.

### C.3 `--questions` mode

`/discovery --questions` drains the deferred backlog: it re-ranks all `status: deferred` questions, presents the next 12, and records answers. No analysis is run.

### C.4 Presentation & Answer Integration

Present grouped by category with `file:line`, snippet, confidence impact, and a suggested answer where the code gives strong hints. Record answers (and non-answers) in `questions.json`, flipping `status` to `answered` or `skipped`.

```json
{
  "questions": [
    {
      "id": "q-001",
      "module": "billing",
      "run_id": "2025-03-15T10-00-00Z-a1b2c3d",
      "category": "behavior",
      "question": "Is the v1 invoice path still reachable or fully dead?",
      "context": { "file": "app/models/legacy_invoice_v1.rb", "line": 1 },
      "confidence_impact": "medium",
      "priority_rank": 3,
      "status": "answered",
      "suggested_answer": "Likely dead — 0 commits 24mo, 0 fan-in",
      "user_answer": "Dead. Safe to remove next cleanup."
    }
  ],
  "asked_at": "2025-03-15T10:30:00Z",
  "total": 18,
  "asked": 12,
  "answered": 9,
  "skipped": 3,
  "deferred": 6
}
```

---

## Output: `context.json`

```json
{
  "architecture": {
    "style": "layered",
    "description": "Three-layer architecture: API routes → services → repositories → database",
    "frameworks": ["Rails 7"],
    "entry_points": ["config/application.rb", "config/routes.rb"]
  },
  "data_models": [
    { "name": "Invoice", "location": "app/models/invoice.rb", "fields_summary": "id, total, status, line_items[]" }
  ],
  "patterns": {
    "error_handling": "Custom error classes, rescued in controllers",
    "naming": "snake_case files, CamelCase classes",
    "state_management": "Request-scoped; no global mutable state",
    "testing": "RSpec unit + request specs",
    "logging": "Rails logger, sanitized payloads"
  },
  "conventions": [
    "Service objects in app/services for multi-model operations",
    "Pundit policies gate all controller actions"
  ],
  "eras": [
    { "tag": "rails-3", "approx_years": "2010-2013", "evidence": "Gemfile.lock rails 3.2 in early history" },
    { "tag": "rails-5", "approx_years": "2017-2019", "evidence": "config.load_defaults 5.2" },
    { "tag": "rails-7", "approx_years": "2022-present", "evidence": "current Gemfile.lock rails 7.1" }
  ],
  "current_era": "rails-7",
  "activity_basis": {
    "window_months": 24,
    "history_months": 96,
    "shallow": false,
    "scaled": false,
    "scale_factor": 1.0,
    "hot_rule": "C12>=15 OR (C12>=5 AND last_commit<=60d)",
    "cold_rule": "C24<=2"
  },
  "analyzed_at": "2025-03-15T10:00:00Z",
  "analyzed_commit": "a1b2c3d"
}
```

> **Important:** `analyzed_commit` records the commit at the last FULL analysis run. It is NOT updated during `--incremental` or `--module` runs. For per-module authoritative timestamps, read `last_analyzed` in each `modules.json` entry, not `context.json`.

## Output: `modules.json`

```json
{
  "modules": [
    {
      "name": "billing",
      "title": "Billing & Invoicing",
      "type": "module",
      "source_paths": ["app/models/invoice.rb", "app/models/charge.rb"],
      "read_when": ["app/models/invoice*", "app/controllers/billing/**"],
      "entry_files": ["app/models/invoice.rb"],
      "depends_on": ["database", "auth"],
      "depended_by": ["reporting"],
      "confidence": "high",
      "boundary_confidence": "high",
      "analysis_depth": "deep",
      "analysis_status": "analyzed",
      "activity": { "class": "hot", "commits_12mo": 41, "commits_24mo": 73, "score": 57 },
      "era": { "tag": "rails-7", "evidence": "...", "imitate": true },
      "key_patterns": ["Invoices immutable once finalized"],
      "data_flow": "HTTP → InvoicesController#create → Invoice#finalize! → ChargeService → Stripe",
      "suspected_dead_files": ["app/models/legacy_invoice_v1.rb"],
      "findings": [
        { "claim": "Invoice totals recomputed from line items on save", "citation": "app/models/invoice.rb#recalculate_total", "kind": "behavior" }
      ]
    }
  ],
  "total_modules": 9,
  "analyzed_at": "2025-03-15T10:00:00Z",
  "analyzed_commit": "a1b2c3d"
}
```

`confidence` (the doc-facing rating) is derived: `high` for analyzed hot/warm modules with all citations validated; `medium` when some citations failed, no tests + old era, or orchestrator-fallback was used; `low` for inventory modules and `failed` batches.

## Output: `history.json` (append-only, one entry per completed run)

```json
{
  "runs": [
    {
      "run_id": "2025-03-15T10-00-00Z-a1b2c3d",
      "timestamp": "2025-03-15T13:10:00Z",
      "commit": "a1b2c3d",
      "mode": "full-batched",
      "sessions": 3,
      "modules_analyzed": 9,
      "batches_total": 7,
      "batches_failed": 0,
      "questions_asked": 12,
      "questions_answered": 9,
      "questions_deferred": 6
    }
  ]
}
```

A `history.json` entry is appended **only when a full-batched run completes** (all batches `done`/`failed`, no `pending`). `--incremental` and `--module` runs append entries with `mode: incremental` / `mode: single` after they finish.

---

## `/discovery` Argument Surface

`/discovery [--full | --incremental | --module <name> | --resume | --questions | --max-batches <N>]`

| Flag | Behavior |
|------|----------|
| `--full` | Default on first run. Full batched analysis from Phase A. Refuses to silently clobber an incomplete run — see resume semantics. |
| `--incremental` | Re-analyze only modules touched since the last completed run. **Refuses to run while an incomplete `run-state.json` exists** — offers resume or restart. |
| `--module <name>` | Re-analyze a single module (Phase B only for that module). |
| `--resume` | Continue an incomplete batched run from `run-state.json`. |
| `--questions` | Drain the deferred question backlog (no analysis). |
| `--max-batches <N>` | Cap batches processed this session (default 5). |

**Incomplete-run gating:**
- Plain `/discovery` (or `--full`) with an incomplete `run-state.json` present → ask **"resume or restart?"** Resume continues; restart archives the old run-state and starts fresh.
- `--incremental` with an incomplete run-state → **refuse**, offer `--resume` or restart. Incremental on top of a half-done full run is meaningless.

### `--resume` semantics

1. Read `run-state.json`. Re-queue batches in order: `failed` → `in_progress` → `pending`. (`failed` first so a flaky batch gets another shot before fresh work.)
2. **Drift check:** `git diff --name-only <run-state.head_commit>..HEAD | wc -l`. If **≤ 50 changed files**, continue (the analysis is still broadly valid). If **> 50**, prompt the user: continue anyway, or restart `--full`.
3. **Reuse `raw/` caches** — do not recompute churn/edges/fan-in unless they're missing.
4. Process up to `--max-batches`; checkpoint after every batch as in Phase B.

---

## Edge Cases (encode these)

| Case | Handling |
|------|----------|
| **Shallow git history / short span** | `< 18 months`: scale activity thresholds linearly (`scale = months/18`). `< 3 months` OR shallow clone: disable activity weighting (all modules `warm`), pattern-marker-only era detection, date-based drift/staleness. Record `scaled`/`shallow` in `context.json.activity_basis`. |
| **Zero-test repos** | Testing Notes for every module states **"none found."** Each **hot** module gets a standing question ("no test coverage for active module X — intentional?"). When a module has **no tests AND an old era**, cap its `confidence` at `medium` (can't trust uncited behavior in stale, untested code). |
| **Generated files** (lockfiles, schema dumps, `db/schema.rb`, `*.lock`, generated GraphQL/proto) | Excluded from churn counting AND never used as citation targets. A finding may not cite a generated file. |
| **HEAD moved between sessions** | On `--resume`, `≤ 50` changed files → continue silently; `> 50` → prompt continue/restart. |
| **Wrongly-bounded module mid-run** | A subagent returns `boundary_verdict.verdict == "wrong"`. Apply the suggested re-bound to `modules.json`, mark affected pending batches `superseded`, replan those modules into new batches. Cap at **2 re-bound rounds per run** (`run-state.rebound_rounds`); after 2, accept the current bounds with `boundary_confidence: low` and proceed. |
| **Validation can't be satisfied** | re-dispatch once (errors appended) → orchestrator-fallback (shallower self-analysis) → mark batch `failed`, continue. Resume re-queues `failed` first. |

---

## `--incremental` Mode

When running `/discovery --incremental` (only allowed when no incomplete run-state exists):

1. **Detect changes:** `git diff --name-only "$(jq -r '.runs[-1].commit' history.json)"..HEAD`.
2. **Map to modules** via `source_paths`/`read_when`. If none affected, report and stop.
3. **Re-analyze affected modules only** (Phase B), preserving unaffected module data. Do NOT update `context.json.analyzed_commit`; only update affected modules' `last_analyzed`.
4. **Re-run dependency mapping** (B.6) for affected modules.
5. **Generate questions only for re-analyzed modules.** Preserve answered questions.
6. **Append** a `mode: incremental` entry to `history.json`.

## `--module <name>` Mode

1. Look up the module in `modules.json`. If not found, list available modules and stop.
2. Re-analyze only that module (Phase B), reusing/recomputing its churn and era.
3. Update its `modules.json` entry and `last_analyzed`.
4. Re-check dependencies involving it.
5. Generate questions only for it.
6. Append a `mode: single` entry to `history.json`.

---

## Integration with Setup Flow

During initial setup:
1. Step 1 completes tooling discovery → `.discovery-context.json`
2. Step 1.5 runs generator → creates directory structure
3. **Step 1.7 (this step) runs deep discovery** → `{{discovery.agent_dir}}/discovery/*.json` (+ `run-state.json`, `raw/`)
4. Step 1.8 reads discovery artifacts → generates populated docs

The deep discovery step creates `{{discovery.agent_dir}}/discovery/` (and `raw/`) if they don't exist. On a large monolith, expect a multi-session run: each session processes `--max-batches` batches and checkpoints; the user resumes with `/discovery --resume` until `run-state.json` reports no `pending` batches.
