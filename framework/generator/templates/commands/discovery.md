---
description: Deep codebase analysis — architecture, patterns, modules
argument-hint: [--full | --incremental | --module <name> | --resume | --questions | --max-batches <N>]
model: {{discovery.models.complex}}
---

# Discovery

Perform deep, **batched, resumable** codebase analysis to understand architecture, patterns, module boundaries, activity, eras, and conventions. This is a **read-only** operation except for the discovery artifacts in `{{discovery.agent_dir}}/discovery/`.

You are the **orchestrator**. You run Phase A and inventory batches yourself (on this command's model), and you **dispatch deep/standard batches to subagents on `{{discovery.models.standard}}`**. You validate every subagent result against the evidence rule and **checkpoint after every batch** so the run survives crashes and context exhaustion.

## Variables

ARGS: $ARGUMENTS
DISCOVERY_DIR: `{{discovery.agent_dir}}/discovery/`
RAW_DIR: `{{discovery.agent_dir}}/discovery/raw/`
MAX_BATCHES: 5 (override with `--max-batches <N>`)

## Steps

### 0. Verify Feature Gate

Confirm `deep_discovery` is enabled. If neither `docs/modules/` nor `docs/modules/ROUTING.md` exists AND no prior artifacts exist in DISCOVERY_DIR, confirm with the user before proceeding (the command may be installed on a project where deep_discovery was disabled).

### 1. Parse Arguments & Resolve Run State

Parse the flag (`--full` default | `--incremental` | `--module <name>` | `--resume` | `--questions` | `--max-batches <N>`). Then read `DISCOVERY_DIR/run-state.json` if it exists.

**Incomplete-run gating** (a run-state with any batch `status` in `pending|in_progress|failed`):
- Plain `/discovery` or `--full` → **ask the user "resume or restart?"** Resume → behave as `--resume`. Restart → move the old run-state aside (`run-state.<run_id>.bak`) and start fresh.
- `--incremental` → **refuse**: "An incomplete discovery run exists. Run `/discovery --resume` to finish it, or `/discovery --full` to restart." Do not run incremental on top of a half-done full run.
- `--resume` → proceed to step 6 (Resume).
- `--questions` → proceed to step 7 (Questions only).

If DISCOVERY_DIR does not exist, create it and `RAW_DIR`, and default to `--full`.

### 2. Step 0 Preflight — Sizing & History  (`--full` / restart)

```bash
mkdir -p {{discovery.agent_dir}}/discovery/raw

# Adapt the extension list to the project's languages.
SRC_FILES=$(git ls-files '*.rb' '*.ts' '*.js' '*.py' '*.go' '*.rs' '*.ex' | grep -vE 'vendor/|node_modules/' | wc -l | tr -d ' ')
SRC_LINES=$(git ls-files '*.rb' '*.ts' '*.js' '*.py' '*.go' '*.rs' '*.ex' | grep -vE 'vendor/|node_modules/' | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
FIRST_EPOCH=$(git log --reverse --format=%ct | head -1)
NOW_EPOCH=$(date +%s)
HISTORY_MONTHS=$(awk -v a="$FIRST_EPOCH" -v b="$NOW_EPOCH" 'BEGIN{printf "%d",(b-a)/2629800}')
SHALLOW=$([ -f "$(git rev-parse --git-dir)/shallow" ] && echo true || echo false)
echo "files=$SRC_FILES lines=$SRC_LINES history_months=$HISTORY_MONTHS shallow=$SHALLOW"
```

Detect tests: if no test directory/files exist, set `has_tests=false`.

**Threshold scaling / degradation:**
- `HISTORY_MONTHS >= 18`: `SCALE=1.0`.
- `3 <= HISTORY_MONTHS < 18`: `SCALE = HISTORY_MONTHS/18` (awk); multiply the activity thresholds (15, 5, 2) by SCALE.
- `HISTORY_MONTHS < 3` OR `SHALLOW == true`: disable activity weighting (every module `warm`), pattern-marker-only era detection, date-based drift.

Estimate batches: `ceil(deep_file_count/30)` deep + `ceil(inventory_modules/5)` inventory. If `> MAX_BATCHES`, **warn the user this is a multi-session run**, checkpointed and resumable via `/discovery --resume`.

Generate `RUN_ID="$(date -u +%Y-%m-%dT%H-%M-%SZ)-$(git rev-parse --short HEAD)"` and `HEAD_COMMIT="$(git rev-parse --short HEAD)"`.

### 3. Phase A — Structure Scan & Boundary Detection  (`--full` / restart)

**A.1–A.2 Tree & entry points.** Map the top two levels; skip `node_modules/.git/dist/build/__pycache__/.next/target/vendor/` and `{{discovery.agent_dir}}/`. Identify entry points and the framework. If `discovery.workspaces` is non-empty, scope per-workspace and prefix module names with the workspace name; record cross-workspace imports as `type: cross_workspace`.

**A.3 Boundary detection.** If the tree is feature-structured, cluster by directory/service/import/framework convention. If the tree is **flat (a legacy monolith)**, apply the Legacy Codebase Recipe (cache to RAW_DIR; the example below is Rails — adapt to the stack):

```bash
# (2) controller namespace clustering (>=3 controllers => candidate module)
git ls-files 'app/controllers/**/*.rb' | sed -E 's#app/controllers/##; s#/[^/]+$##' | sort | uniq -c | sort -rn

# (3) model association edges + class fan-in (hub-and-spoke)
grep -rEn '^\s*(has_many|has_one|belongs_to|has_and_belongs_to_many)\s+:[a-z_]+' app/models > {{discovery.agent_dir}}/discovery/raw/assoc-edges.txt
grep -rohE '\b[A-Z][A-Za-z0-9]+\b' app/models | sort | uniq -c | sort -rn > {{discovery.agent_dir}}/discovery/raw/class-fanin.txt

# (4) implicit-service fan-in (Manager|Processor|Builder|Service|Calculator|Handler, fan-in>=10 across >=2 clusters => shared-services)
grep -rlE 'class\s+[A-Z][A-Za-z0-9]*(Manager|Processor|Builder|Service|Calculator|Handler)\b' app > {{discovery.agent_dir}}/discovery/raw/service-candidates.txt
```

Recipe order: engines/path-gems → controller namespaces (≥3) → model association hub-and-spoke (assign spokes to most-shared hub; merge overlapping hubs) → routes namespaces + implicit-service fan-in → **merge to 5–15** (small/low-confidence clusters merge into best edge-neighbor or `legacy-misc`; split `legacy-misc` if it exceeds 30% of files; split largest hub if <5, merge smallest if >15) → **dead-file marking** (0 commits 24mo AND 0 class fan-in → `suspected_dead_files`).

**A.4 Activity classification.** Cache churn once, then sum per module:

```bash
git log --since="24 months ago" --name-only --format= | grep -vE 'vendor/|node_modules/' | sort | uniq -c | sort -rn > {{discovery.agent_dir}}/discovery/raw/churn-24mo.txt
git log --since="12 months ago" --name-only --format= | grep -vE 'vendor/|node_modules/' | sort | uniq -c | sort -rn > {{discovery.agent_dir}}/discovery/raw/churn-12mo.txt
# last commit age for a file: git log -1 --format=%ct -- "$file"
```

Per module sum `C12`, `C24`, find days since last commit. **Exclude generated files** (lockfiles, `*.lock`, schema dumps, `db/schema.rb`, generated proto/GraphQL) from churn and from `source_paths`. Classify (with SCALE applied):

- **hot** = `C12 ≥ 15*SCALE` OR (`C12 ≥ 5*SCALE` AND last commit ≤ 60d)
- **cold** = `C24 ≤ 2*SCALE`
- **warm** = otherwise

`score = C12 + 0.5*(C24 - C12)`. Depth: hot→`deep`, warm→`standard`, cold→`inventory`. Write `activity {class, commits_12mo, commits_24mo, score}` and `analysis_depth` per module.

**A.5 Era detection** (generic; Rails example). Sample the dependency manifest across history, read config markers, find dominant commit years:

```bash
for sha in $(git log --format=%H --since="20 years ago" | awk 'NR==1 || NR%400==0'); do
  echo "$sha $(git show "$sha:Gemfile.lock" 2>/dev/null | grep -A1 '^    rails ' | head -1)"
done > {{discovery.agent_dir}}/discovery/raw/era-manifest.txt
```

Set per-module `era {tag, evidence, imitate}` and project `current_era`. `imitate: false` when the module's era is materially older than `current_era`. Below 3 months history: pattern-marker-only (skip manifest sampling).

**A.6 Checkpoint.** Write skeleton `modules.json` (all fields, `findings: []`, `analysis_status: pending`, `boundary_confidence`), write `context.json` (`eras`, `current_era`, `activity_basis`), and write `run-state.json` with the **full batch plan**:
- Batches: **1–3 same-tier modules, ≤40 files, ≤50K lines.** Never mix tiers.
- **Inventory (cold): 5 modules/batch**, `tier: inventory` (orchestrator-handled, no dispatch).
- Order batches hot → warm → cold; within a tier by `score` desc.
- Set every batch `status: pending`, `phase_a_complete: true`, `rebound_rounds: 0`.

### 4. Incremental / Single-Module short circuits

- `--incremental`: `git diff --name-only "$(jq -r '.runs[-1].commit' {{discovery.agent_dir}}/discovery/history.json)"..HEAD`; map changed files to modules via `source_paths`/`read_when`. If none, report "No changes affect any known modules" and stop. Otherwise re-run Phase B for affected modules only, preserve the rest, **do not** update `context.json.analyzed_commit`, append a `mode: incremental` history entry.
- `--module <name>`: verify it exists in `modules.json` (else list modules and stop); re-run Phase B for it; update its entry + `last_analyzed`; re-check its dependencies; questions only for it; append a `mode: single` history entry.

### 5. Phase B — Batched Deep Analysis

Process pending batches in plan order, up to `MAX_BATCHES` this session. Mark a batch `in_progress` before working it.

**Inventory batches (orchestrator-handled, no dispatch):** for each module, read 1–2 representative files, record a one-line purpose, a file→class inventory, and confirm `suspected_dead_files`. No citations required. `confidence: low`.

**Deep/standard batches — dispatch one subagent on `{{discovery.models.standard}}`** with this exact prompt (fill the bracketed slots from `context.json` and the batch's module entries):

```
You are a code-analysis subagent. Analyze ONLY the modules in the manifest below and return findings. You have a read budget — do not read files outside the manifest.

GLOBAL CONTEXT
- Architecture style: [context.architecture.style]
- Current era: [context.current_era]
- Conventions: [context.conventions]

MODULE MANIFEST (batch [batch_id])
For each module: name, title, source_paths, entry_files, boundary_confidence, activity.class, era, suspected_dead_files.
[paste the per-module manifest]

READ BUDGET
Read entry_files first, then the highest-fan-in files, then test files. Cap at the source_paths list for the batch (<=40 files). Do not read outside the manifest.

THE EVIDENCE RULE (mandatory)
Every behavioral claim you emit MUST carry a citation: either `path:line` or `path#method`.
- A claim you cannot cite to a specific line or method is NOT a finding. Put it in `questions` instead.
- Never cite a generated file (lockfile, schema dump).
- Max 5 questions per module.

BOUNDARY ESCAPE HATCH
If a module's files clearly don't belong together, set `boundary_verdict` for that module with a suggested re-bound instead of forcing findings.

OUTPUT
Return EXACTLY ONE fenced ```json block, schema_version 2, matching this shape:
{
  "schema_version": 2,
  "batch_id": "[batch_id]",
  "modules": [
    {
      "name": "...", "title": "...", "type": "module",
      "depends_on": ["..."], "external_deps": ["..."],
      "data_flow": "input -> processing -> output",
      "key_patterns": ["..."],
      "findings": [ { "claim": "...", "citation": "path:line | path#method", "kind": "behavior|constant|dependency|convention|data-model" } ],
      "testing_notes": "...",
      "suspected_dead_confirmed": ["..."],
      "boundary_verdict": null,
      "questions": [ { "category": "behavior", "question": "...", "context": {"file":"...","line":1}, "confidence_impact": "high|medium|low" } ]
    }
  ]
}
Output nothing outside the single fenced json block.
```

**Validation (per batch).** On the returned block, in order:
1. **jq parse** the single fenced json block: `... | jq .` — malformed → fail.
2. **Schema check:** `schema_version == 2`, every manifest module present, required keys present.
3. **Citation regex + file existence:** every `finding.citation` matches `^[^:]+:[0-9]+$` OR `^[^#]+#[a-zA-Z_?!]+$`, and the cited file exists:
   ```bash
   echo "$CIT" | grep -Eq '^[^:]+:[0-9]+$|^[^#]+#[a-zA-Z_?!]+$' || echo "BAD_CITATION:$CIT"
   test -f "${CIT%%:*}" || test -f "${CIT%%#*}" || echo "MISSING_FILE:$CIT"
   ```
4. **Spot-verify 3 random citations** with `sed -n` / `grep`:
   ```bash
   sed -n "${LINE}p" "$FILE"                                  # line citation
   grep -nE "(def|function|fn|func)\s+${METHOD}\b" "$FILE"    # method citation
   ```
   A spot-checked citation pointing at an unrelated line counts as a failure.

**On any validation failure:** re-dispatch the **same** subagent once with the validation errors appended to the prompt. Second failure → **orchestrator-fallback**: you analyze the batch yourself (shallower, still citing what you can). Third failure → mark the batch `status: failed`, set affected modules `confidence: low`, and continue.

**Boundary re-bound:** if a module returns `boundary_verdict.verdict == "wrong"` and `rebound_rounds < 2`: apply the suggested re-bound to `modules.json`, mark affected pending batches `superseded`, replan those modules into new pending batches, increment `rebound_rounds`. At `rebound_rounds == 2`, accept current bounds with `boundary_confidence: low` and proceed.

**Checkpoint after EVERY batch:** merge the batch into `modules.json` (`findings[]`, `depends_on`, `data_flow`, `key_patterns`, `analysis_status`, derived `confidence`), append `questions` into `questions.json` (`status: deferred`, `run_id: RUN_ID`), update the batch `status` and `updated_at` in `run-state.json`.

When `MAX_BATCHES` is reached with batches still `pending`: write the checkpoint and tell the user to run `/discovery --resume`. When no `pending` remain: run B.6 reconciliation (dependency graph + global patterns into `context.json`), then proceed to questions and the completion report; append a `history.json` entry (one per completed multi-session run); mark/clear `run-state.json` complete.

### 6. Resume  (`--resume`)

1. Read `run-state.json`. Drift check: `CHANGED=$(git diff --name-only "$HEAD_COMMIT"..HEAD | wc -l | tr -d ' ')`. If `CHANGED <= 50`, continue; if `> 50`, prompt the user (continue / restart `--full`).
2. Re-queue batches: `failed` → `in_progress` → `pending`.
3. Reuse `RAW_DIR` caches; recompute only if missing.
4. Process up to `MAX_BATCHES`, checkpointing after each (step 5 mechanics).

### 7. Questions

**During a normal run:** after this session's batches, collect `status: deferred` questions, rank **high-impact → hot modules → activity score**, present **at most 12**, mark them `status: asked`, record answers (`answered`/`skipped`). The rest stay `deferred`.

**`--questions` mode:** no analysis — re-rank all `deferred` questions, present the next 12, record answers.

Present grouped by category with `file:line`, snippet, confidence impact, and a suggested answer where the code gives strong hints.

### 8. Report

```
## Discovery Complete

Mode: <full-batched | incremental | single | resume | questions>
Run: <RUN_ID>   HEAD: <commit>
Batches: <done>/<total>  (failed: <N>, superseded: <N>, pending: <N>)
Modules analyzed: <N> / <total>
Questions: asked <N>, answered <N>, deferred <N>

Modules (hot → cold):
{{#each modules}}
- {{name}} [{{activity.class}}/{{analysis_depth}}] ({{confidence}} confidence){{#unless era.imitate}} ⚠️ {{era.tag}}{{/unless}} — {{title}}
{{/each}}

{{#if pending_remaining}}
Run `/discovery --resume` to process the remaining <N> batches.
{{else}}
Next step: run `/document` to generate module documentation.
{{/if}}
```

## DO NOT

- Do not modify source files or run tests/builds.
- Do not create documentation files (that's `/document`).
- Do not write outside DISCOVERY_DIR.
- Do not emit an uncited behavioral claim, and do not accept one from a subagent — it becomes a question, not a finding.
- Do not skip the per-batch checkpoint; a crash must lose at most one batch.
