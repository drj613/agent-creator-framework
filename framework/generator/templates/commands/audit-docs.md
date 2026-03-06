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
- A doc can be old but intentionally stable
- If `in_index` is false, determine whether it should be added to the index or deleted

**For each spec:**
- If `classification` is `built_complete`: verify by reading the spec's acceptance criteria
- If `classification` is `built_partial`: flag for human review with specifics on what's missing
- If `classification` is `never_built_old`: recommend deletion or implementation
- If `classification` is `never_built_recent`: leave alone

### 3. Report

Output a prioritized list using the script's data enriched with your interpretation:

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
For each entry in the `module_docs` array from the audit script output:
- **fresh** (0 commits): ✓ up to date
- **minor_drift** (1-5 commits): low risk, frontmatter update may suffice
- **moderate_drift** (6-20 commits): recommend `/discovery --module <name>` then `/document --module <name>`
- **major_drift** (20+ commits): high risk, full re-analysis needed

Confidence decay: if a module doc has `confidence: high` but `staleness: moderate_drift` or worse, report effective confidence as `medium`. If `staleness: major_drift`, report effective confidence as `low`.

Check routing table consistency: every `.md` file in `docs/modules/` (excluding `ROUTING.md`) should have a row in `docs/modules/ROUTING.md`. Flag any module doc without a routing entry, and any routing entry pointing to a non-existent module doc.
{{/if}}
```

### 4. Fix Mode (if --fix)

For HIGH risk temporary docs:
- Read the file
- Extract any decisions or insights not yet in a permanent doc
- Update the appropriate permanent doc
- Delete the temporary file
- Update docs/README.md if the file was listed there

For specs classified as "Built & Complete":
- Move to `specs/archive/`

Do NOT auto-delete anything that isn't clearly temporary. Flag MEDIUM risk for human review.
