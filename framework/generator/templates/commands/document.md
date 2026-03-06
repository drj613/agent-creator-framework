---
description: Generate module docs from discovery analysis
argument-hint: [--all | --module <name> | --update-routing]
model: {{discovery.models.complex}}
---

# Document

Generate or update module documentation from the discovery analysis artifacts. Reads `{{discovery.agent_dir}}/discovery/` and produces populated docs in `docs/modules/`.

## Variables

ARGS: $ARGUMENTS
DISCOVERY_DIR: `{{discovery.agent_dir}}/discovery/`
MODULES_DIR: `docs/modules/`

## Steps

### 0. Verify Prerequisites
Verify that `{{discovery.agent_dir}}/discovery/` exists and contains `modules.json`. If not, tell the user to run `/discovery` first. This command depends on discovery artifacts.

### 1. Parse Arguments

- `--all` (default): generate/update all module docs
- `--module <name>`: generate/update one module doc
- `--update-routing`: only regenerate the `docs/modules/ROUTING.md` routing table and `docs/README.md` index

### 2. Verify Discovery Artifacts

Check that DISCOVERY_DIR contains `context.json` and `modules.json`. If missing:
```
Discovery artifacts not found. Run /discovery first to analyze the codebase.
```
Stop and tell the user.

### 3. Load Discovery Data

Read:
- `DISCOVERY_DIR/context.json` — architecture, patterns, conventions
- `DISCOVERY_DIR/modules.json` — module definitions
- `DISCOVERY_DIR/questions.json` — questions and answers (for open_questions)

### 4. Generate Module Docs

Create `MODULES_DIR/` if it doesn't exist.

For each module (or the specified module in `--module` mode):

**4a. Check existing doc:**
- If `MODULES_DIR/<name>.md` exists, read its YAML frontmatter
- If `generated_by: human` → skip entirely, report "Skipped (human-maintained)"
- If `generated_by: hybrid` → update frontmatter only (`source_paths`, `read_when`, `depends_on`, `depended_by`, `last_analyzed`, `confidence`, `open_questions`); preserve entire body verbatim
- If `generated_by: discovery` → full update with preservation of `<!-- human-maintained -->` sections
- If no existing doc → create new

**4b. Build YAML frontmatter** from modules.json entry:
- `module`: module name
- `title`: module title
- `type`: module type
- `source_paths`: from module entry
- `read_when`: from module entry
- `depends_on`: from module entry
- `depended_by`: from module entry
- `last_analyzed.commit`: from latest discovery run
- `last_analyzed.date`: from latest discovery run
- `confidence`: from module entry
- `open_questions`: unanswered questions from questions.json for this module
- `generated_by`: `discovery` (new) or preserve existing value
- `tags`: derived from module analysis

**4c. Build doc body** using the following steps:

**Doc generation steps:**
1. Load `modules.json` from `{{discovery.agent_dir}}/discovery/`
2. Load `questions.json` to get answered questions per module
3. For each module: check if `docs/modules/<module>.md` exists
   - If not: create with full YAML frontmatter + generated sections
   - If exists with `generated_by: discovery`: update frontmatter + regenerate body (preserve `<!-- human-maintained -->` blocks)
   - If exists with `generated_by: hybrid`: update frontmatter only, preserve entire body
   - If exists with `generated_by: human`: skip entirely
4. Update `docs/modules/ROUTING.md` with current routing table
5. Update `docs/README.md` module index section
6. Populate stub permanent docs (`docs/ARCHITECTURE.md`, `docs/DEVELOPMENT.md`) only if they are empty or contain only a title line

Sections to generate for each new or `generated_by: discovery` doc:
1. **Overview** — 2-3 sentence summary from analysis
2. **Key Files** — table of files and responsibilities
3. **Data Flow** — how data moves through the module
4. **Patterns & Conventions** — module-specific patterns
5. **Dependencies** — internal and external
6. **Testing Notes** — how to test this module
7. **Open Questions** — unanswered items

**4d. Write the file** to `MODULES_DIR/<name>.md`.

### 5. Populate Permanent Docs (if stub)

Check `docs/ARCHITECTURE.md` and `docs/DEVELOPMENT.md`:
- If the file exists and is not empty (has any non-whitespace content beyond a title header) → leave it alone regardless of length
- If the file is completely empty or contains only a title line → populate from `context.json`
- **ARCHITECTURE.md**: architecture style, module diagram, data model overview, entry points
- **DEVELOPMENT.md**: patterns, conventions, testing approach, module navigation guide

### 6. Update Routing Table

Build the routing table from modules.json and write it to `docs/modules/ROUTING.md`:

```markdown
## Module Documentation

When modifying code, consult the relevant module doc BEFORE planning changes.

| Files you are modifying | Read this doc |
|------------------------|---------------|
<for each module: all read_when patterns joined with ", " | docs/modules/<name>.md>

Cross-cutting: `docs/ARCHITECTURE.md` for system-level changes, `docs/DECISIONS.md` for ADRs.
```

Rules:
- Maximum ~20 rows — if more modules exist, group related ones
- Join all `read_when` patterns for a module in a single cell, comma-separated
- Write the full file content to `docs/modules/ROUTING.md` (create if it does not exist)

### 7. Update docs/README.md

Replace content between `<!-- module-index-start -->` and `<!-- module-index-end -->` markers in `docs/README.md`:

```markdown
| Module | Description | Doc |
|--------|-------------|-----|
<for each module: title, 1-line description, link to doc>
```

Add to the "When to Update" table:
```markdown
| Changed implementation within a module | `docs/modules/<module>.md` |
```

### 8. Report

```
## Document Generation Complete

Mode: <all | single | routing-only>
Module docs created: <N>
Module docs updated: <N>
Module docs skipped (human-maintained): <N>
Routing table: <updated | created>
docs/README.md: <updated>

Generated docs:
{{#each generated}}
- docs/modules/{{name}}.md ({{confidence}} confidence)
{{/each}}

{{#if skipped}}
Skipped (human-maintained):
{{#each skipped}}
- docs/modules/{{name}}.md
{{/each}}
{{/if}}
```

## Preservation Rules

- **Never overwrite `generated_by: human`** docs
- **Preserve `<!-- human-maintained -->` sections** during updates
- **Don't remove YAML frontmatter** from existing docs
- **Merge, don't replace** — preserve manually added sections
- **Permanent docs** (ARCHITECTURE.md, etc.) are only populated if they're stubs (<10 lines of content)
