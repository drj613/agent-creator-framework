# Step 1.8 — Document Generation

> **Part of Conversation 2.** Discovery context should already be loaded from `.discovery-context.json` at the start of this conversation (loaded during `01a-deep-discovery.md`). If not already in context, re-read `{{agent_dir}}/.discovery-context.json`. This is the last step in Conversation 2 — after completing this step, return to `00-setup-guide.md` and follow the End of Conversation 2 instructions.

> **Feature gate:** Only run this step if `{{discovery.features.deep_discovery}}` is true.

> **Standalone command:** This step also powers the `/document` command (`templates/commands/document.md`). That command is the operational spec; **this guide and that command MUST agree exactly on the frontmatter schema, depth tiers, the evidence rule, the citation self-check, and the ROUTING.md format.** This guide is the reference/rationale layer.

## Prerequisites

- Discovery context from Step 1
- Deep discovery artifacts from Step 1.7 (`{{agent_dir}}/discovery/context.json`, `modules.json`, `questions.json`) — and a **completed** run (`run-state.json` reports no `pending` batches, or is absent). If batches are still `pending`, tell the user to finish discovery (`/discovery --resume`) before documenting — partially-analyzed modules would generate hedged-to-empty docs.
- Documentation structure from Step 8 (if `documentation_structure` is enabled, `docs/` exists)

## Overview

Step 1.7 analyzed the codebase and produced structured JSON artifacts — crucially, a `findings[]` evidence store per module where **every behavioral claim carries a `path:line` or `path#method` citation**. This step transforms those artifacts into human-readable, frontmatter-rich documentation.

The headline rule: **doc-body behavioral claims are generated ONLY from `findings[]`, with the citation rendered inline.** A claim that cannot be backed by a finding is never silently written into the body — it is demoted to Open Questions as an "Unverified: …" item. This is what keeps generated docs from drifting into confident fiction (the failure mode that made the weak `frontend.md` example uncitable). The gold-standard doc (`extractions.md`) reads the way it does precisely because every method, constant, and parameter it names is real.

**Produces:**
- `docs/modules/<module>.md` — one doc per module, with YAML frontmatter, at a **depth tier** matching the module's activity
- Populated `docs/ARCHITECTURE.md` / `docs/DEVELOPMENT.md` — only if empty or stub
- `docs/modules/ROUTING.md` — module routing table (owned exclusively by `/document`)
- Updated `docs/README.md` with the modules index

**Preservation rule:** Existing human-written content is never overwritten. Sections marked `<!-- human-maintained -->` … `<!-- /human-maintained -->` are preserved. Docs with `generated_by: human` are skipped entirely; `generated_by: hybrid` updates frontmatter only.

---

## Depth Tiers

The doc tier is driven by the module's `analysis_depth` / `activity.class` from `modules.json`, recorded in frontmatter as `doc_depth`:

| `doc_depth` | Trigger | Target length | Shape |
|-------------|---------|---------------|-------|
| **deep** | hot module (`analysis_depth: deep`) | **150–400 lines** | The `extractions.md` standard — full Key Files, Data Flow, per-method/constant detail, all cited. |
| **standard** | warm module (`analysis_depth: standard`) | **80–150 lines** | Overview, Key Files, Data Flow, Patterns, Dependencies, Testing, Open Questions — cited, but less exhaustive. |
| **inventory** | cold module (`analysis_depth: inventory`) | **30–60 lines** | **Hedged** overview, a file→class inventory table, era warning if applicable, and a **mandatory re-discover footer**. `confidence` capped `low`. |

**Inventory doc mandatory footer (verbatim):**

```markdown
> **Inventory-grade doc.** This module is cold (little recent activity) and was skimmed, not deeply analyzed. Treat the descriptions above as a map, not a contract. **Re-discover before relying on any behavioral detail:** run `/discovery --module <name>` then `/document --module <name>`.
```

---

## YAML Frontmatter Schema

Every module doc starts with YAML frontmatter that agents and tools parse. **Existing fields are preserved and extended** — ROUTING.md parsing and `/audit-docs` staleness both depend on `source_paths`, `read_when`, `last_analyzed`, and `confidence`, so those never change shape.

```yaml
---
module: billing                       # kebab-case identifier, matches modules.json
title: "Billing & Invoicing"
type: module                          # module | service | data-model | integration

# === Agent Routing ===
source_paths:                         # files this doc describes (for staleness/drift detection)
  - app/models/invoice.rb
  - app/models/charge.rb
read_when:                            # broader globs — when to consult this doc
  - app/models/invoice*
  - app/controllers/billing/**

# === Dependencies ===
depends_on: [database, auth]
depended_by: [reporting]

# === Staleness Detection ===
last_analyzed:
  commit: "a1b2c3d"
  date: "2025-03-15"

# === Confidence & Depth ===
confidence: high                      # high | medium | low
doc_depth: deep                       # deep | standard | inventory
era: rails-7                          # framework-era tag from modules.json
imitate: true                         # false → render the "do NOT imitate" warning
open_questions:
  - "Is refresh token rotation intentional or a TODO?"

generated_by: discovery               # discovery | human | hybrid
tags: [billing, payments]
---
```

**Key fields:**
- `source_paths` — exact files this doc describes. Drift: count commits to these files since `last_analyzed.commit`. **Excludes generated files** (lockfiles, schema dumps) per the discovery rule.
- `read_when` — broader globs for agent routing.
- `confidence` — `high` (clear patterns, citations validated, user-confirmed), `medium` (reasonable inference / partial citation failure / no-tests+old-era), `low` (guesswork, inventory tier, or a `failed` batch).
- `doc_depth` — the tier (see above). New field; additive.
- `era` / `imitate` — from the module's `era` block. `imitate: false` triggers the era warning callout.
- `generated_by` — `discovery`, `human`, or `hybrid`.

---

## The Evidence Rule (how body claims are produced)

For each module, the doc body is assembled from the module's `findings[]` and structured fields in `modules.json`:

1. **Every behavioral claim in the body comes from a `findings[]` entry**, and renders its citation inline. Render style: backticked path with the line/method, e.g.
   > Invoice totals are recomputed from line items on every save (`app/models/invoice.rb#recalculate_total`), not stored.

   Constants render with their value and citation:
   > `MAX_LINE_ITEMS` caps an invoice at 500 line items (`app/models/invoice.rb:8`).

2. **Structural content** (the Key Files table, the dependency lists, the data-flow diagram) comes from `source_paths`, `depends_on`/`depended_by`, and `data_flow` — these are inventory facts, not behavioral claims, and don't each need a citation. But any *behavioral* annotation on a Key Files row must trace to a finding.

3. **Uncitable claims are demoted, never dropped silently.** If the analysis surfaced an observation that has no citation (e.g. a suspicion the subagent couldn't pin to a line), it appears under Open Questions prefixed **`Unverified:`** — e.g. `Unverified: charges may be retried on Stripe timeout, but no retry code was located.` This keeps the signal without asserting it as fact.

4. **Per-doc self-check pass.** After generating a doc, re-read it and confirm every body sentence that asserts behavior has an inline citation or is hedged. Move any naked behavioral assertion to Open Questions as `Unverified:`.

5. **Citation sampling.** Sample **5 citations** from the generated doc and verify them on disk:
   ```bash
   # line citation
   sed -n "${LINE}p" "$FILE"
   # method citation
   grep -nE "(def|function|fn|func)\s+${METHOD}\b" "$FILE"
   ```
   If **more than 1 of the 5 is dead** (file/line gone, method not found), **drop the doc's `confidence` one level** (high→medium→low) and add an Open Question: `Drift detected: N of 5 sampled citations no longer resolve — re-run /discovery --module <name>.`

---

## Era Warning

When `imitate: false` in frontmatter, insert this callout **immediately after the H1**, before the Overview:

```markdown
> ⚠️ **Era warning — do NOT imitate these patterns in new code.** This module dates to the **{{era}}** era and predates the project's current conventions ({{current_era}}). The patterns documented below describe what *is*, not what *should be*. New code must follow current conventions; treat this doc as archaeology.
```

---

## Module Doc Template (deep / standard tier)

````markdown
---
<YAML frontmatter — see schema above>
---

# <Module Title>

<era warning callout here if imitate: false>

## Overview

<What this module does, 2-3 sentences. Behavioral claims cited inline.>

## Key Files

| File | Responsibility |
|------|---------------|
| `app/models/invoice.rb` | Core invoice model — totals, finalization, immutability |
| `app/services/charge_service.rb` | Wraps Stripe charge creation and error mapping |

## Data Flow

```
HTTP request
  → InvoicesController#create
  → Invoice#finalize! (freezes line items)
  → ChargeService → Stripe API
```

<From the module's `data_flow` field.>

## Patterns & Conventions

- <Cited behavioral pattern: e.g., "Invoices are immutable once finalized (`app/models/invoice.rb#finalize!`)">

## Dependencies

**Internal:** <from depends_on>
**External:** <from external_deps>

## Testing Notes

<From findings' testing_notes. If the repo has no tests: "No automated tests found for this module.">

## Open Questions

{{#each open_questions}}
- {{.}}
{{/each}}

<Unanswered questions for this module, plus any "Unverified:" demoted claims.>
````

## Module Doc Template (inventory tier)

````markdown
---
<frontmatter, confidence: low, doc_depth: inventory>
---

# <Module Title>

<era warning callout if imitate: false>

## Overview (inventory-grade)

<1-2 hedged sentences: what this cluster appears to contain. No confident behavioral assertions.>

## File Inventory

| File | Primary class/symbol | Apparent purpose |
|------|----------------------|------------------|
| `app/models/legacy_report.rb` | `LegacyReport` | Report generation (cold) |

## Suspected Dead Files

<From suspected_dead_files[] — files with 0 commits in 24mo and 0 fan-in.>

## Open Questions

{{#each open_questions}}
- {{.}}
{{/each}}

> **Inventory-grade doc.** This module is cold (little recent activity) and was skimmed, not deeply analyzed. Treat the descriptions above as a map, not a contract. **Re-discover before relying on any behavioral detail:** run `/discovery --module <name>` then `/document --module <name>`.
````

---

## Generation Process

### 1. Read Discovery Artifacts

Load from `{{agent_dir}}/discovery/`:
- `context.json` — global architecture, patterns, conventions, `current_era`
- `modules.json` — module definitions with `findings[]`, `activity`, `era`, `analysis_depth`, `confidence`
- `questions.json` — questions/answers; unanswered → Open Questions
- `run-state.json` — confirm no `pending` batches (else stop)

### 2. Create Module Directory

```bash
mkdir -p docs/modules/
```

### 3. Generate Per-Module Docs

For each module in `modules.json`:

1. **Check for existing doc** (`docs/modules/<module>.md`):
   - `generated_by: human` → skip entirely.
   - `generated_by: hybrid` → update frontmatter only; preserve body verbatim.
   - `generated_by: discovery` → update in place, preserving `<!-- human-maintained -->` … `<!-- /human-maintained -->` blocks.

2. **Pick the depth tier** from `analysis_depth` / `activity.class`; select the matching template.

3. **Build frontmatter** from `modules.json`:
   - `module`, `title`, `type`, `source_paths`, `read_when`, `depends_on`, `depended_by`
   - `last_analyzed.commit`/`date` from the run's analysis timestamp
   - `confidence` from the module (capped `low` for inventory; `medium` for no-tests+old-era)
   - `doc_depth`, `era`, `imitate` from the module's `era` block
   - `open_questions` from `questions.json` where `question.module == module.name` AND `status` is unanswered (`deferred`/`asked`/`skipped`). **Filter by the `module` field**; skip any question missing `module` and warn: "Question <id> has no module field — skipped."
   - `generated_by: discovery`; `tags` from type/framework/patterns

4. **Build body via the evidence rule:** render Overview / Patterns / behavioral annotations from `findings[]` with inline citations; structural sections from the inventory fields. Demote uncitable observations to Open Questions as `Unverified:`.

5. **Run the self-check + citation sampling** (5 citations via `sed -n`). Drop confidence a level and add a drift question if >1 of 5 is dead.

6. **Insert the era warning** after the H1 if `imitate: false`.

### 4. Populate Permanent Docs (If Stub)

**`docs/ARCHITECTURE.md`** — only if empty or only a title line: write architecture style/description, module dependency diagram, data-model overview, entry points (from `context.json`).

**`docs/DEVELOPMENT.md`** — only if empty or only a title line: patterns/conventions, testing approach, module navigation.

If a file has any non-whitespace content beyond a title header, leave it unchanged regardless of length.

### 5. Generate `docs/modules/ROUTING.md`

Owned exclusively by `/document`; overwritten on every run; never human-edited.

`/document` also ensures `CLAUDE.md` (the context file) contains the reference line. Check first; if absent, append to the Module Documentation section (or create the section):

```
See `docs/modules/ROUTING.md` for the module routing table.
```

Do not add duplicate lines; do not overwrite other CLAUDE.md content.

**ROUTING.md format and rules:**

```markdown
# Module Routing Table

> Generated by `/document`. Do not edit manually.

When modifying code, consult the relevant module doc before making changes.

| Files you are modifying | Module doc | Depth | Era |
|---|---|---|---|
| `app/models/invoice*`, `app/controllers/billing/**` | [Billing & Invoicing](billing.md) | deep | rails-7 |
| `app/models/legacy_report*` | [Legacy Reports](legacy-reports.md) (inventory) | inventory | rails-4 ⚠️ |

Fallback: for anything not matched above, consult `docs/ARCHITECTURE.md`.
```

- **One row per module, up to 20.** (No grouping — drop any "group related modules" rule.) If a project has >20 modules, list the top 20 by activity and rely on the fallback row.
- **Ordered hot → warm → cold** (by activity).
- **Depth column** (`deep`/`standard`/`inventory`) and **Era column** (era tag, with ⚠️ when `imitate: false`).
- Inventory links get an **`(inventory)` suffix** after the link text.
- A final **fallback row to `docs/ARCHITECTURE.md`** for unmatched paths.
- Join all `read_when` patterns for a module in the first cell, comma-separated.
- Always regenerated from current `modules.json`; no manual rows.

### 6. Update `docs/README.md`

Replace content between `<!-- module-index-start -->` and `<!-- module-index-end -->`:

```markdown
| Module | Description | Doc | Depth |
|--------|-------------|-----|-------|
{{#each modules}}
| {{title}} | <1-line description> | `docs/modules/{{name}}.md` | {{doc_depth}} |
{{/each}}
```

Add to the "When to Update" table:

```markdown
| Changed implementation within a module | `docs/modules/<module>.md` |
```

### 7. Report

```
## Document Generation Complete

Mode: <all | single | routing-only>
Module docs created: <N>
Module docs updated: <N>
Module docs skipped (human-maintained): <N>
Confidence dropped by citation drift: <N>
Routing table: <updated | created>

Generated docs:
{{#each generated}}
- docs/modules/{{name}}.md ({{doc_depth}}, {{confidence}} confidence)
{{/each}}
```

---

## Updating Existing Module Docs

### Preservation Rules

1. **Never overwrite `generated_by: human`** — skip entirely.
2. **`generated_by: hybrid`** — update frontmatter only (`source_paths`, `read_when`, `depends_on`, `depended_by`, `last_analyzed`, `confidence`, `doc_depth`, `era`, `imitate`, `open_questions`); preserve the body verbatim.
3. **Preserve `<!-- human-maintained -->` sections** — content between `<!-- human-maintained -->` and the required closing `<!-- /human-maintained -->` is preserved verbatim. If an opening tag has no closing tag, warn and treat the boundary as ending at the next section header (recovery fallback). Never silently discard content.

   - Use the tag pair to protect a specific section within a `generated_by: discovery` doc.
   - Use `generated_by: hybrid` to freeze the entire body.
   - During `--module <name>` on a `major_drift` doc, list any `<!-- human-maintained -->` sections and prompt the user to verify accuracy (reminder only; never auto-removed).
4. **Always update frontmatter** from fresh discovery data.
5. **Merge, don't replace** for `generated_by: discovery` docs — update sections with new analysis, preserve manually added sections, update Key Files / Dependencies as files/imports change.

### Staleness-Triggered Updates

When `/document --all` runs, for each module doc count commits to `source_paths` since `last_analyzed.commit`:
- 0 commits: skip (fresh)
- 1–5 commits: update frontmatter only (minor drift)
- 6+ commits: full regeneration of body (with preservation rules)

---

## `--update-routing` Mode

When running `/document --update-routing`: only regenerate `docs/modules/ROUTING.md` and the `docs/README.md` module index from current `modules.json`. Do not touch module docs. Useful after manually adding or removing module docs.
