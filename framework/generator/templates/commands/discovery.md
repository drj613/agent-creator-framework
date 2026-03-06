---
description: Deep codebase analysis — architecture, patterns, modules
argument-hint: [--incremental | --module <name> | --full]
model: {{discovery.models.complex}}
---

# Discovery

Perform deep codebase analysis to understand architecture, patterns, module boundaries, and conventions. This is a **read-only** operation — no files are modified except the discovery artifacts in `{{discovery.agent_dir}}/discovery/`.

## Variables

ARGS: $ARGUMENTS
DISCOVERY_DIR: `{{discovery.agent_dir}}/discovery/`

## Steps

### 0. Verify Feature Gate
Check that `deep_discovery` is enabled in this project. Look for the Module Documentation section in the project context file (CLAUDE.md). If neither `docs/modules/` directory nor `docs/modules/ROUTING.md` exists AND no prior discovery artifacts exist in the agent directory, confirm with the user before proceeding — this command may have been installed on a project where deep_discovery was later disabled.

### 1. Parse Arguments

- `--full` (default on first run, or when no `history.json` exists): analyze entire codebase
- `--incremental`: only re-analyze modules affected by changes since last run
- `--module <name>`: re-analyze a single module by name

If DISCOVERY_DIR does not exist, create it and default to `--full`.

### 2. Check for Previous Runs

Read `DISCOVERY_DIR/history.json` if it exists. If running `--incremental`:
- Get the commit hash from the last run
- Run `git diff --name-only <last_commit>..HEAD` to get changed files
- Map changed files to modules using `modules.json` `source_paths` and `read_when` patterns
- If no modules are affected, report "No changes affect any known modules" and stop
- Otherwise, list affected modules and proceed with re-analysis of only those modules

If running `--module <name>`:
- Verify the module exists in `modules.json`
- If not found, list available modules and stop

### 3. Run Analysis

**Phase A — Structure Scan**
Map the directory tree (top two levels). For each directory: record path, approximate file count by extension, whether it contains an entry point. Skip: node_modules, .git, build artifacts, vendor directories. Classify 5–15 logical module boundaries using: directory-per-feature layout, service class groupings, import clustering, and framework conventions (e.g., Rails app/ subdirs, Django apps, Phoenix contexts). Record results in memory for Phase B.

If `discovery.workspaces` is non-empty: scope analysis per-workspace. Prefix module names with workspace name (e.g., `api/auth`). Treat cross-workspace imports as `cross_workspace` dependencies.

**Phase B — Deep Analysis (per module)**
For each module identified in Phase A, read source files in this order: entry point, type definitions/interfaces, core business logic, data access layer, test files (to understand expected behavior). For each file read: identify exported API surface, data structures, key patterns, dependencies, side effects. Limit to 8–12 representative files per module; prioritize breadth over exhaustive depth. Record in `modules.json` format: `name`, `title`, `type`, `source_paths`, `read_when`, `entry_files`, `depends_on`, `depended_by`, `confidence`, `key_patterns`, `data_flow`.

**Phase C — Question Generation**
Record uncertainties with `confidence_impact: high | medium | low`. Each question MUST include a `module` field matching a name in `modules.json`. Format per the `questions.json` schema. Present high-confidence-impact questions to the user now. Record all questions in `questions.json`.

### 4. Present Questions

If any questions were generated:
- Group by category
- Show `file:line` context and code snippet for each
- Explain the confidence impact
- Offer suggested answers where the code gives hints
- Ask the user to answer what they can — unanswered questions become `open_questions` in module docs

Record all answers (and non-answers) in `DISCOVERY_DIR/questions.json`.

### 5. Write Artifacts

Write/update these files in DISCOVERY_DIR:
- `context.json` — architecture style, data models, patterns, conventions
- `modules.json` — module boundaries, source paths, read_when patterns, dependencies
- `questions.json` — questions with answers (merged with existing if incremental)
- `history.json` — append new run entry

### 6. Report

```
## Discovery Complete

Mode: <full | incremental | single>
Modules analyzed: <N>
Total modules: <N>
Questions asked: <N> (answered: <N>, skipped: <N>)
Commit: <current HEAD>

Modules:
{{#each modules}}
- {{name}} ({{confidence}} confidence) — {{title}}
{{/each}}

Next step: Run /document to generate module documentation from this analysis.
```

## DO NOT

- Do not modify any source files
- Do not create documentation files (that's `/document`'s job)
- Do not execute tests or run build commands
- Do not create or modify any files outside of DISCOVERY_DIR
