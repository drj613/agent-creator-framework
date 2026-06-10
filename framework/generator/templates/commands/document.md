---
description: Generate module docs from discovery analysis
argument-hint: [--all | --module <name> | --update-routing]
model: {{discovery.models.complex}}
---

# Document

Generate or update module documentation from the discovery artifacts. Reads `{{discovery.agent_dir}}/discovery/` and produces populated docs in `docs/modules/`.

The governing rule: **doc-body behavioral claims come ONLY from each module's `findings[]` (the cited evidence store), with citations rendered inline.** Uncitable observations are demoted to Open Questions as `Unverified: …`, never silently written as fact. Doc length and shape follow a **depth tier** (deep/standard/inventory) keyed off the module's activity.

## Variables

ARGS: $ARGUMENTS
DISCOVERY_DIR: `{{discovery.agent_dir}}/discovery/`
MODULES_DIR: `docs/modules/`

## Steps

### 0. Verify Prerequisites

Verify `DISCOVERY_DIR` exists and contains `modules.json`. If not, tell the user to run `/discovery` first. Read `run-state.json`: if any batch `status` is `pending|in_progress`, **stop** and tell the user to finish discovery (`/discovery --resume`) — partially-analyzed modules would generate empty/hedged docs.

### 1. Parse Arguments

- `--all` (default): generate/update all module docs
- `--module <name>`: one module doc
- `--update-routing`: only regenerate `docs/modules/ROUTING.md` and the `docs/README.md` index

### 2. Load Discovery Data

Read:
- `DISCOVERY_DIR/context.json` — architecture, patterns, conventions, `current_era`
- `DISCOVERY_DIR/modules.json` — module definitions with `findings[]`, `activity`, `era`, `analysis_depth`, `confidence`, `suspected_dead_files`
- `DISCOVERY_DIR/questions.json` — unanswered → Open Questions

### 3. Generate Module Docs

Create `MODULES_DIR/` if absent (`mkdir -p docs/modules/`). For each module (or the `--module` target):

**3a. Check existing doc** (`MODULES_DIR/<name>.md`):
- `generated_by: human` → skip; report "Skipped (human-maintained)".
- `generated_by: hybrid` → update frontmatter only; preserve body verbatim.
- `generated_by: discovery` → full update, preserving `<!-- human-maintained -->` … `<!-- /human-maintained -->` blocks (closing tag required; if missing, warn and treat the next section header as the boundary).
- none → create new.

**3b. Pick depth tier** from `analysis_depth` / `activity.class`:

| `doc_depth` | Trigger | Target length | Shape |
|-------------|---------|---------------|-------|
| **deep** | hot / `analysis_depth: deep` | 150–400 lines | Full Key Files, Data Flow, per-method/constant detail, all cited |
| **standard** | warm / `analysis_depth: standard` | 80–150 lines | Overview, Key Files, Data Flow, Patterns, Dependencies, Testing, Open Questions — cited |
| **inventory** | cold / `analysis_depth: inventory` | 30–60 lines | Hedged overview, file→class inventory, era warning, **mandatory re-discover footer**, `confidence: low` |

**3c. Build YAML frontmatter** from the `modules.json` entry (preserve existing field shapes — ROUTING.md parsing and `/audit-docs` depend on them):
- `module`, `title`, `type`, `source_paths` (generated files already excluded), `read_when`, `depends_on`, `depended_by`
- `last_analyzed: { commit, date }` from the run timestamp
- `confidence` from the module (inventory capped `low`; no-tests+old-era capped `medium`)
- `doc_depth`, `era`, `imitate` from the module's `era` block (additive fields)
- `open_questions`: from `questions.json` where `question.module == <name>` and status is unanswered (`deferred`/`asked`/`skipped`). **Filter by the `module` field**; skip any question missing `module` and warn "Question <id> has no module field — skipped."
- `generated_by: discovery` (or preserve existing); `tags` from type/framework/patterns

**3d. Build the body via the evidence rule:**
1. **Overview** (2–3 sentences) and **Patterns & Conventions** — behavioral statements rendered from `findings[]` with the citation inline. Render `path#method` and `path:line` in backticks at the end of the sentence:
   > Invoice totals are recomputed from line items on every save (`app/models/invoice.rb#recalculate_total`), not stored.
   > `MAX_LINE_ITEMS` caps an invoice at 500 line items (`app/models/invoice.rb:8`).
2. **Key Files** table — from `source_paths`; behavioral annotations on a row must trace to a finding.
3. **Data Flow** — from the module's `data_flow` field (a code-block diagram).
4. **Dependencies** — Internal from `depends_on`, External from `external_deps`.
5. **Testing Notes** — from findings' `testing_notes`; if the repo has no tests, write "No automated tests found for this module."
6. **Open Questions** — unanswered questions for this module, **plus** any uncitable observation demoted as `Unverified: …`.
7. **Inventory tier** instead uses: hedged Overview, a **File Inventory** table (file → primary class → apparent purpose), a **Suspected Dead Files** section from `suspected_dead_files[]`, and the mandatory footer:

   ```markdown
   > **Inventory-grade doc.** This module is cold (little recent activity) and was skimmed, not deeply analyzed. Treat the descriptions above as a map, not a contract. **Re-discover before relying on any behavioral detail:** run `/discovery --module <name>` then `/document --module <name>`.
   ```

**3e. Era warning.** If `imitate: false`, insert immediately after the H1:

```markdown
> ⚠️ **Era warning — do NOT imitate these patterns in new code.** This module dates to the **<era>** era and predates the project's current conventions (<current_era>). The patterns below describe what *is*, not what *should be*. New code must follow current conventions; treat this doc as archaeology.
```

**3f. Self-check + citation sampling.** Re-read the generated doc:
- Every body sentence asserting behavior must have an inline citation or be hedged. Move naked assertions to Open Questions as `Unverified: …`.
- Sample **5 citations** and verify on disk:
  ```bash
  sed -n "${LINE}p" "$FILE"                                  # line citation
  grep -nE "(def|function|fn|func)\s+${METHOD}\b" "$FILE"    # method citation
  ```
  If **>1 of 5 is dead**, drop the doc's `confidence` one level (high→medium→low) and add an Open Question: `Drift detected: N of 5 sampled citations no longer resolve — re-run /discovery --module <name>.`

**3g. Write** the file to `MODULES_DIR/<name>.md`.

### 4. Populate Permanent Docs (if stub)

`docs/ARCHITECTURE.md` / `docs/DEVELOPMENT.md`: if the file has any non-whitespace content beyond a title header → leave it alone regardless of length. If empty or only a title line → populate from `context.json`:
- **ARCHITECTURE.md**: style, module dependency diagram, data-model overview, entry points.
- **DEVELOPMENT.md**: patterns, conventions, testing approach, module navigation guide.

### 5. Generate `docs/modules/ROUTING.md`

Owned exclusively by `/document`; overwritten every run; never human-edited. Also ensure the context file (`CLAUDE.md`) has the reference line `See \`docs/modules/ROUTING.md\` for the module routing table.` in its Module Documentation section (add the section if absent; no duplicates; don't touch other content).

Write this exact format:

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

Rules:
- **One row per module, up to 20.** No grouping. If >20 modules exist, list the top 20 by activity; the fallback row covers the rest.
- **Order hot → warm → cold** (by activity).
- First cell: all `read_when` patterns for the module, comma-separated.
- **Depth column** (`deep`/`standard`/`inventory`); **Era column** (era tag, append ` ⚠️` when `imitate: false`).
- Inventory links get an **`(inventory)` suffix** after the link text.
- Final **fallback row to `docs/ARCHITECTURE.md`**.
- Always regenerated from current `modules.json`; no manual rows.

### 6. Update `docs/README.md`

Replace content between `<!-- module-index-start -->` and `<!-- module-index-end -->`:

```markdown
| Module | Description | Doc | Depth |
|--------|-------------|-----|-------|
<for each module: title, 1-line description, link, doc_depth>
```

Add to the "When to Update" table (if not already present):

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

{{#if skipped}}
Skipped (human-maintained):
{{#each skipped}}
- docs/modules/{{name}}.md
{{/each}}
{{/if}}
```

## Preservation Rules

- **Never overwrite `generated_by: human`** docs.
- **`generated_by: hybrid`** → update frontmatter only; freeze the body.
- **Preserve `<!-- human-maintained -->` … `<!-- /human-maintained -->`** blocks (closing tag required; missing → warn + boundary at next header; never silently discard).
- **Don't remove YAML frontmatter** from existing docs; extend it (the new `doc_depth`/`era`/`imitate` fields are additive).
- **Merge, don't replace** for `generated_by: discovery` docs — preserve manually added sections; update Key Files / Dependencies as files/imports change.
- **Permanent docs** (ARCHITECTURE.md, DEVELOPMENT.md) only populated if stubs (empty or title-only).

## `--update-routing` Mode

Only regenerate `docs/modules/ROUTING.md` and the `docs/README.md` index from current `modules.json`. Do not touch module docs.

## Staleness-Triggered Updates (during `--all`)

For each existing module doc, count commits to `source_paths` since `last_analyzed.commit`:
- 0 commits → skip (fresh)
- 1–5 → update frontmatter only (minor drift)
- 6+ → full body regeneration (with preservation rules)
