# Step 6: Rules

> **Part of Conversation 4.** At the start of this conversation, read `{{agent_dir}}/.discovery-context.json` to load the discovery context and `{{agent_dir}}/.setup-progress.json` to verify that `"discovery"`, `"generate"`, `"context_file"`, and `"commands"` are in `completed_steps`. If any are missing, **stop** and tell the user which conversation to run first.
> **Skip if complete:** If `"rules"` is already in `completed_steps`, skip this step and proceed to `07-skills.md`.

> **Feature gate:** Only create `commit-workflow.md` if `{{discovery.features.commit_workflow}}` is true. Only create `documentation-rules.md` if `{{discovery.features.documentation_structure}}` is true.

## Prerequisites

- Discovery context from Step 1

## Overview

Rules are Markdown files in `{{discovery.agent_dir}}/rules/`. They are referenced from the context file (created in Step 2) and loaded as context when relevant. Unlike hooks (which enforce automatically), rules are instructions the agent follows during its workflow.

## Files to Create

```
{{discovery.agent_dir}}/rules/
├── commit-workflow.md       # Pre-commit documentation requirement
└── documentation-rules.md   # Doc hierarchy, where changes belong
```

---

## `commit-workflow.md`

The single most important rule file. Enforces: documentation is updated **before** creating a commit, not after.

**The core rule in plain terms:**

> Complete the feature → update documentation → update CHANGELOG → run tests → stage everything (code + docs) → commit

**Must include in the generated file:**

1. **Pre-commit checklist** — the exact steps, in order:
   - Code changes complete
   - Documentation updated (see where-to-document table below)
   - CHANGELOG.md updated
   - Tests pass: `{{discovery.test_runner.cmd}}`
   - All changes staged (code AND docs together)
   - Commit with descriptive message

2. **Where-to-document table** — which doc to update for each type of change:

   | You changed... | Update this file |
   |----------------|-----------------|
   | System architecture | `docs/ARCHITECTURE.md` |
   | Local dev setup | `docs/DEVELOPMENT.md` |
   | Deploy process | `docs/DEPLOYMENT.md` |
   | Made an architectural decision | `docs/DECISIONS.md` |
   | Found/fixed a performance issue | `docs/PERFORMANCE.md` |
   | Any code change at all | `CHANGELOG.md` |

3. **Commit message template:**

   ```
   <action>: <what changed>

   - <specific change 1>
   - <specific change 2>

   Docs updated: <list of doc files changed>
   Tests: <X/X passed>
   ```

4. **Example commit message:**

   ```
   feat: add user authentication endpoints

   - POST /auth/login with JWT token generation
   - POST /auth/logout with token invalidation
   - Middleware for protected routes

   Docs updated: docs/ARCHITECTURE.md, CHANGELOG.md
   Tests: 47/47 passed
   ```

5. **What NOT to do:**
   - Do not commit code without updating relevant docs
   - Do not create a separate "docs update" commit after the code commit
   - Do not skip the CHANGELOG
   - Do not commit with failing tests
   - Do not stage docs and code in separate commits

6. **Step-by-step process** — no ambiguity about the order

---

## `documentation-rules.md`

Governs how documentation is maintained. Prevents doc sprawl.

**Must include in the generated file:**

1. **Permanent docs list** — files that are updated in place forever:
   - `docs/ARCHITECTURE.md` — system design, data flow, services
   - `docs/DEVELOPMENT.md` — local setup, dev commands, testing
   - `docs/DEPLOYMENT.md` — production deploy procedures
   - `docs/DECISIONS.md` — Architecture Decision Records (ADRs)
   - `docs/PERFORMANCE.md` — bottlenecks, optimizations, benchmarks
   - `CHANGELOG.md` — version history, updated on every commit

2. **Temporary doc patterns** — with explicit lifecycle:
   - Analysis docs (`*_ANALYSIS.md`), summaries (`*_SUMMARY.md`), results (`*_RESULTS.md`)
   - Meeting notes (`*_MEETING.md`, `*_NOTES.md`)
   - Versioned files (`*_v0.9.7.md`), date-stamped files (`*_2024-01-15.md`)
   - **Lifecycle:** extract insights → update the appropriate permanent doc → delete the temporary file
   - These should never linger more than one sprint/milestone

3. **Where-to-document table** (same as commit-workflow, reinforced here):

   | You changed... | Update this file |
   |----------------|-----------------|
   | System architecture | `docs/ARCHITECTURE.md` |
   | Local dev setup | `docs/DEVELOPMENT.md` |
   | Deploy process | `docs/DEPLOYMENT.md` |
   | Architectural decision | `docs/DECISIONS.md` |
   | Performance issue | `docs/PERFORMANCE.md` |
   | Any code change | `CHANGELOG.md` |

4. **ADR format** for architectural decisions:

   ```markdown
   ## ADR-NNN: <Title>

   **Date:** YYYY-MM-DD
   **Status:** proposed | accepted | deprecated | superseded

   ### Context
   <what prompted this decision>

   ### Decision
   <what we decided>

   ### Consequences
   <what follows from this decision — both positive and negative>
   ```

5. **The cardinal rule:** Check the doc index (`docs/README.md`) before creating a new file. If an appropriate permanent doc already exists, update it instead of creating a new one.

{{#if discovery.features.deep_discovery}}
6. **Module documentation rules:**
   - Check `docs/modules/ROUTING.md` for the routing table before modifying code in a module. Read the relevant module doc (`docs/modules/<module>.md`) before planning changes.
   - When you change behavior described in a module doc, update the doc to reflect the new behavior. At minimum, update the "Patterns & Conventions" and "Data Flow" sections if they're affected.
   - Do not remove YAML frontmatter from module docs — it is parsed by tools for staleness detection and agent routing.
   - Do not modify the `source_paths`, `read_when`, `last_analyzed`, or `generated_by` fields manually — these are managed by `/discovery` and `/document`.
   - Run `/discovery --module <name>` to refresh a specific module's analysis after significant changes. The staleness detection in `/audit-docs` will flag modules that need refreshing.
   - Sections wrapped in `<!-- human-maintained -->` / `<!-- /human-maintained -->` tags are preserved during automated regeneration — use these tags to protect hand-written content.
{{/if}}

