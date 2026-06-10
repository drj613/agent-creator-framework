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

Execute the audit script to collect deterministic signals:

`bash {{discovery.agent_dir}}/hooks/audit-docs.sh --docs-dir docs --specs-dir specs --index-file docs/README.md`

Parse the JSON output. It produces structured data for every doc and spec file:
- Per-doc: `path`, `last_edit_date`, `last_edit_days`, `commits_90d`, `is_temporary`, `temp_pattern_matched`, `in_index`, `co_change_files`, `todo_count`, `has_stale_versions`, `risk_level`
- Per-spec: `path`, `age_days`, `git_evidence_commits`, `listed_files_exist`, `classification`
- Summary: aggregate counts by risk level and spec status

If the script fails (non-zero exit or invalid JSON), report the error and stop.

### 2. Interpret Results

The script assigns risk levels mechanically; add judgment:

**HIGH risk doc:** if `is_temporary`, recommend action by `temp_pattern_matched` (e.g., meeting notes → extract decisions to DECISIONS.md then delete). If not temporary but old with no commits, check `co_change_files` — high churn in described source means genuine staleness.

**MEDIUM risk doc:** read the file to decide whether staleness is genuine (a doc can be old but intentionally stable). If `in_index` is false, decide add-to-index vs delete.

**Specs:** `built_complete` → verify against acceptance criteria; `built_partial` → flag for review with specifics; `never_built_old` → recommend deletion or implementation; `never_built_recent` → leave alone.

{{#if discovery.features.deep_discovery}}
### 2a. Compute Module-Doc Effective Confidence

For every `docs/modules/*.md` except `ROUTING.md`, read the frontmatter (`confidence`, `doc_depth`, `last_analyzed.commit`, `last_analyzed.date`, `source_paths`) and compute drift and effective confidence yourself (the audit script does not emit these). Everything here is **bash 3.2 + awk + git + jq** safe.

**Drift commits** — commits to the doc's `source_paths` since `last_analyzed.commit`:

```bash
# DOC=path to module doc; SRC_PATHS=space-separated source_paths from frontmatter
LAST_COMMIT=$(...)   # last_analyzed.commit from frontmatter
if git cat-file -e "${LAST_COMMIT}^{commit}" 2>/dev/null; then
  DRIFT=$(git log --oneline "${LAST_COMMIT}..HEAD" -- $SRC_PATHS | wc -l | tr -d ' ')
else
  # commit unreachable (rebased/squashed/shallow) — DATE-BASED FALLBACK
  LAST_DATE=$(...)   # last_analyzed.date (YYYY-MM-DD) from frontmatter
  DRIFT=$(git log --oneline --since="$LAST_DATE" -- $SRC_PATHS | wc -l | tr -d ' ')
fi
```

**Baseline** by frontmatter `confidence`: `high → 1.0`, `medium → 0.6`, `low → 0.3`.

**Effective confidence** = `baseline × 0.97^DRIFT`, computed with awk:

```bash
EFFECTIVE=$(awk -v b="$BASELINE" -v d="$DRIFT" 'BEGIN{printf "%.2f", b * (0.97 ^ d)}')
```

**Inventory cap:** if `doc_depth == inventory`, clamp `EFFECTIVE` to a maximum of `0.59` (an inventory doc can never report better than medium-low, even at zero drift):

```bash
EFFECTIVE=$(awk -v e="$EFFECTIVE" 'BEGIN{printf "%.2f", (e>0.59?0.59:e)}')   # only when doc_depth==inventory
```

**Thresholds** → label:
- `EFFECTIVE >= 0.75` → **high**
- `0.45 <= EFFECTIVE < 0.75` → **medium**
- `EFFECTIVE < 0.45` → **low**

**Recommended action** per doc:
- `EFFECTIVE < 0.45` → `/discovery --module <name>` then `/document --module <name>` (full re-analysis).
- `0.45–0.74` → frontmatter refresh may suffice; re-discover if `co_change_files` shows the described source churning hard.
- `>= 0.75` → healthy.
- **Promote to deep:** if the doc is `doc_depth: inventory` but the module's current activity is now **hot** (re-check churn: `git log --since="12 months ago" --oneline -- $SRC_PATHS | wc -l` ≥ 15), recommend `/discovery --module <name>` to **promote it to a deep doc** — a cold module that woke up needs real analysis, not an inventory skim.

### 2b. Routing-Table Consistency

Every `docs/modules/*.md` (except `ROUTING.md`) must have a row in `docs/modules/ROUTING.md`. Flag module docs with no routing entry, and routing entries pointing at non-existent docs.
{{/if}}

### 3. Report

```
## Documentation Audit

### High Risk — Action Required
- <file> — <pattern matched>. Recommend: <action>.

### Medium Risk — Review Needed
- <file> — <reason>. Recommend: <action>.

### Low Risk — Looks Healthy
- <files that are healthy>

### Untracked Files (not in docs/README.md index)
- <files>

### Specs Status
- <spec> — <classification>. Recommend: <action>.

{{#if discovery.features.deep_discovery}}
### Module Docs Health

| Module doc | Depth | Frontmatter conf. | Drift commits | Effective conf. | Action |
|---|---|---|---|---|---|
| billing.md | deep | high | 4 | 0.89 (high) | Healthy |
| legacy-reports.md | inventory | low | 0 | 0.30 (low) | /discovery --module legacy-reports |
| auth.md | standard | high | 31 | 0.39 (low) | /discovery --module auth, then /document |
| imports.md | inventory | low | 18 | 0.17 (low) | Promote to deep — module is now hot |

- Effective confidence = baseline(high 1.0 / medium 0.6 / low 0.3) × 0.97^(drift commits), clamped to ≤0.59 for inventory docs.
- ≥0.75 high · 0.45–0.74 medium · <0.45 low.
- Drift uses commits to `source_paths` since `last_analyzed.commit`; when that commit is unreachable, it falls back to commits since `last_analyzed.date`.

### Routing Consistency
- <module docs missing a ROUTING.md row, and routing rows pointing at missing docs>
{{/if}}
```

### 4. Fix Mode (if --fix)

For HIGH risk temporary docs:
- Read the file, extract decisions/insights not yet in a permanent doc, update the appropriate permanent doc, delete the temporary file, update `docs/README.md` if listed.

For specs classified "Built & Complete":
- Move to `specs/archive/`.

{{#if discovery.features.deep_discovery}}
For module docs: **write the computed `effective_confidence` into each doc's frontmatter** (additive — do not alter the existing `confidence` field, which records the original analysis confidence). Insert/update a single line:

```yaml
effective_confidence: 0.39   # computed by /audit-docs --fix on <date>; baseline confidence × 0.97^drift
```

Place it directly after the existing `confidence:` line. This is the only frontmatter change `--fix` makes to module docs; it never rewrites bodies and never touches `generated_by: human` docs.
{{/if}}

Do NOT auto-delete anything that isn't clearly temporary. Flag MEDIUM risk for human review.
