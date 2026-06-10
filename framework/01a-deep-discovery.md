# Step 1.7 — Deep Discovery

> **Part of Conversation 2.** At the start of this conversation, read `{{agent_dir}}/.discovery-context.json` to load the discovery context and `{{agent_dir}}/.setup-progress.json` to verify that `"discovery"` and `"generate"` are in `completed_steps`. If either is missing, **stop** and tell the user: "Prerequisites incomplete. Please run Conversation 1 first."
> **Skip if complete:** If `"deep_discovery"` is already in `completed_steps`, skip this step and proceed to `01b-document-generation.md`.

> **Feature gate:** Only run this step if `{{discovery.features.deep_discovery}}` is true.

> **Standalone command:** This step also powers the `/discovery` command. When run as a command, skip Phase 2 (user questions) if answers already exist in `{{agent_dir}}/discovery/questions.json`.

## Prerequisites

- Discovery context from Step 1 (tooling detection complete)
- Generator output from Step 1.5 (directory structure exists)

## Overview

Step 1 detects tooling metadata (linters, test runners, package managers). This step goes deeper: it reads actual source code to understand architecture, patterns, module boundaries, data flows, and conventions. The output feeds into Step 1.8 (Document Generation) to produce populated module docs.

**Three phases:**
1. **Phase A — Structure Scan:** Map directory tree, classify module boundaries, identify entry points
2. **Phase B — Deep Analysis:** Per-module source reading, pattern identification, dependency tracing
3. **Phase C — Question Generation:** Record uncertainties, present to user, capture answers

## Output Artifacts

All artifacts are written to `{{discovery.agent_dir}}/discovery/`:

| File | Contents |
|------|----------|
| `context.json` | Architecture style, data models, patterns, conventions |
| `modules.json` | Module boundaries, source paths, read_when patterns, dependencies |
| `questions.json` | Questions with user answers (or null for unanswered) |
| `history.json` | Audit trail of discovery runs (for incremental mode) |

---

## Phase A: Structure Scan

Scan the project to build a high-level map before diving into source code.

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

Read each entry point file to understand:
- What framework is used (Express, FastAPI, Rails, Phoenix, etc.)
- How the application is structured (MVC, hexagonal, microservice, etc.)
- What top-level modules/packages are imported

### A.2a Monorepo and Workspace Handling

> Only run this section if `discovery.workspaces` is non-empty (set in Step 1 discovery context).

When the project uses workspaces (e.g., npm workspaces, Yarn workspaces, Turborepo, Nx, Cargo workspaces, Elixir umbrella apps):

- **Scope:** Treat each workspace as a distinct module boundary. Run Phase B analysis per-workspace, not globally.
- **Module naming:** Prefix module names with the workspace name, e.g., `api/auth`, `web/auth`, to avoid collisions.
- **Cross-workspace dependencies:** When module A imports from module B in a different workspace, record the dependency as `"workspace:web/auth"` in `depends_on`. Mark `type: cross_workspace` on the dependency edge.
- **`source_paths` scope:** Each module's `source_paths` should only include files within its workspace directory.
- **`read_when` patterns:** Use workspace-relative paths in patterns, e.g., `packages/api/src/auth/*`.
- **Shared packages:** If the project has a shared library workspace (e.g., `packages/shared`), treat it as its own module set and note in `context.json` under a `shared_packages` key.
- **`context.json` scope:** `architecture_style`, `conventions`, and `data_models` describe the whole project. If workspaces differ significantly (e.g., different frameworks), add a `workspace_overrides` key with per-workspace values.

### A.3 Module Boundary Detection

Identify 5–15 logical modules using these heuristics (in priority order):

1. **Directory-per-feature structure** — If the source tree has `src/auth/`, `src/tasks/`, `src/billing/`, etc., each directory is a module.

2. **Service class boundaries** — If the project uses service objects (e.g., `AuthService`, `TaskService`), each service and its related files form a module.

3. **Import clustering** — Groups of files that import heavily from each other but have sparse imports to other groups indicate module boundaries.

4. **Framework conventions:**
   - **Rails:** `app/models/`, `app/controllers/`, `app/services/`, each major model cluster forms a module
   - **Express/Fastify:** route file groups + their service/middleware
   - **Django:** each app directory is a module
   - **Phoenix:** each context module is a module
   - **Go:** each package directory is a module

5. **Explicit boundaries** — `packages/` or `libs/` directories in monorepos, plugin directories, middleware directories

**Target:** 5–15 modules. Fewer than 5 suggests too-coarse boundaries (consider splitting). More than 15 suggests too-fine boundaries (consider merging related modules).

For each detected module, record:

```yaml
- name: "auth"                           # kebab-case identifier
  title: "Authentication & Sessions"     # human-readable title
  type: module                           # module | service | data-model | integration
  source_paths:                          # files this module contains
    - src/middleware/auth.ts
    - src/services/AuthService.ts
    - src/models/User.ts
  read_when:                             # broader globs — when agents should consult this module's doc
    - src/middleware/auth*
    - src/services/Auth*
    - src/routes/auth*
    - src/models/User*
  entry_files:                           # main files to read to understand this module
    - src/services/AuthService.ts
  depends_on: []                         # other module names this depends on (filled in Phase B)
  depended_by: []                        # other module names that depend on this (filled in Phase B)
```

**`read_when` semantics:** Patterns are matched using Unix shell glob rules (as implemented by `fnmatch(3)` or equivalent):
- `*` matches any sequence of characters that does not include `/`
- `**` matches any sequence of characters including `/` (recursive path match)
- `?` matches exactly one character
- Matching is case-sensitive on case-sensitive filesystems

Patterns are matched against file paths **relative to the project root**. A file matches if ANY pattern in `read_when` matches its path.

**Examples:**
- `src/auth/*` — matches `src/auth/service.ts` but NOT `src/auth/utils/hash.ts`
- `src/auth/**` — matches `src/auth/service.ts` AND `src/auth/utils/hash.ts`
- `src/**/auth*` — matches any file anywhere under `src/` whose basename starts with `auth`

**`source_paths` vs `read_when`:**
- `source_paths`: exact file paths this module owns (used for staleness detection — git commit counting)
- `read_when`: glob patterns for routing (broader than source_paths — should match files an agent would be modifying when working in this module's domain)

These should NOT be identical. A typical pattern: `source_paths` lists specific files; `read_when` uses broader globs covering the same area plus adjacent files that interact with this module.

---

## Phase B: Deep Analysis

For each module identified in Phase A, perform detailed source analysis.

### B.1 Source File Reading

For each module, read the entry files and key source files. For large modules (>10 files), prioritize:
1. Entry files (identified in A.2)
2. Files with the most imports from other modules
3. Files that define public API/exports
4. Test files (to understand expected behavior)

### B.2 Per-Module Analysis

For each module, extract:

**Architecture & Data Flow:**
- What data enters this module (API requests, events, function calls)
- What processing happens (validation, transformation, business logic)
- What data exits (responses, database writes, events emitted)
- Draw a simple data flow: `input → processing → output`

**Patterns & Conventions:**
- Naming conventions specific to this module
- Error handling approach (throw, return Result, error codes)
- Authentication/authorization patterns
- Logging and observability patterns
- Testing patterns (what's mocked, what's integration-tested)

**Key Types & Interfaces:**
- Core data types/models used by this module
- Public API surface (exported functions, classes, types)
- Configuration shape

**Dependencies:**
- Internal: which other modules does this import from?
- External: which third-party packages does this use?

### B.3 Cross-Module Dependency Mapping

After analyzing all modules, build the dependency graph:
1. For each module, check its imports against other modules' `source_paths`
2. Record `depends_on` and `depended_by` relationships
3. Identify circular dependencies (flag as a concern)
4. Identify "hub" modules that many others depend on (e.g., database, config, utils)

### B.4 Global Pattern Identification

Across all modules, identify:
- **Architecture style**: MVC, hexagonal, layered, microservices-in-monolith, etc.
- **Common patterns**: repository pattern, service layer, middleware chain, event-driven, etc.
- **Naming conventions**: camelCase vs snake_case, file naming, class naming
- **Error handling**: consistent approach or mixed
- **State management**: how state is passed between modules
- **Configuration**: centralized config, env-based, per-module

---

## Phase C: Question Generation

### C.1 Recording Uncertainties

During Phases A and B, record every uncertainty encountered. Each question must include:

Each question MUST include a `module` field matching a name in `modules.json`. Agents must not leave `module` null — if uncertain, use the module whose `source_paths` most closely match the `context.file`.

```yaml
- id: "q-001"
  module: "auth"                        # Module name from modules.json — explicit association
  category: architecture | pattern | convention | dependency | behavior
  question: "Is the refresh token rotation in AuthService intentional or a TODO?"
  context:
    file: "src/services/AuthService.ts"
    line: 47
    snippet: "// TODO: consider rotation"
  confidence_impact: high | medium | low   # how much knowing this would improve doc quality
  suggested_answer: null                    # pre-fill if the code gives strong hints
```

**Categories:**
- **architecture** — "Is this microservice boundary intentional?"
- **pattern** — "Should new services follow the repository pattern used here?"
- **convention** — "Is the snake_case naming in this module intentional or legacy?"
- **dependency** — "Does module X actually depend on Y, or is that import dead?"
- **behavior** — "Is this retry logic production-ready or placeholder?"

### C.2 Question Presentation

After completing analysis, present questions to the user grouped by category. For each question:
1. Show the `file:line` context
2. Show the code snippet
3. Explain why knowing the answer matters (the `confidence_impact`)
4. Offer a suggested answer if the code gives strong hints

Example presentation:

```
## Discovery Questions

I analyzed your codebase and have some questions to improve documentation accuracy.
Answer what you can — unanswered questions will be noted as open items in the module docs.

### Architecture (3 questions)

**Q1** [high impact]: Is the separation between `src/api/` and `src/services/` intentional as a layered architecture, or did it evolve organically?
📍 `src/api/routes.ts:12` — all routes import from services, never from models directly
💡 Suggested: Intentional layered architecture (consistent pattern across all routes)

**Q2** [medium impact]: ...

### Patterns (2 questions)
...
```

### C.3 Answer Integration

User answers (and non-answers) are recorded in `questions.json`:

```json
{
  "questions": [
    {
      "id": "q-001",
      "module": "api-routing",
      "category": "architecture",
      "question": "Is the separation between src/api/ and src/services/ intentional?",
      "context": { "file": "src/api/routes.ts", "line": 12 },
      "confidence_impact": "high",
      "suggested_answer": "Intentional layered architecture",
      "user_answer": "Yes, we enforce this as a rule — services are the only layer that touches the database.",
      "answered": true
    },
    {
      "id": "q-002",
      "module": "auth",
      "question": "...",
      "user_answer": null,
      "answered": false
    }
  ],
  "asked_at": "2025-03-15T10:30:00Z",
  "total": 8,
  "answered": 5,
  "skipped": 3
}
```

---

## Output: `context.json`

```json
{
  "architecture": {
    "style": "layered",
    "description": "Three-layer architecture: API routes → services → repositories → database",
    "frameworks": ["Express", "Prisma"],
    "entry_points": ["src/server.ts", "src/routes/index.ts"]
  },
  "data_models": [
    {
      "name": "User",
      "location": "prisma/schema.prisma",
      "fields_summary": "id, email, passwordHash, role, createdAt, sessions[]"
    }
  ],
  "patterns": {
    "error_handling": "Custom AppError class with status codes, caught by error middleware",
    "naming": "camelCase for variables/functions, PascalCase for classes/types, kebab-case for files",
    "state_management": "Request-scoped via middleware, no global mutable state",
    "testing": "Unit tests mock repositories, integration tests use test database",
    "logging": "Structured JSON logging via pino, correlation IDs in middleware"
  },
  "conventions": [
    "All API handlers return { data, error } shape",
    "Database access only through repository pattern",
    "Environment config loaded once at startup via config.ts",
    "All middleware follows (req, res, next) → void signature"
  ],
  "analyzed_at": "2025-03-15T10:00:00Z",
  "analyzed_commit": "a1b2c3d"
}
```

> **Important:** `analyzed_commit` in `context.json` records the commit at the time of the last FULL analysis run. It is NOT updated during incremental (`--incremental`) or single-module (`--module`) runs. For per-module authoritative timestamps, use the `last_analyzed` field in each module entry in `modules.json`. Callers that need to know when a specific module was last analyzed should read `modules.json`, not `context.json`.

## Output: `modules.json`

```json
{
  "modules": [
    {
      "name": "auth",
      "title": "Authentication & Session Management",
      "type": "module",
      "source_paths": [
        "src/middleware/auth.ts",
        "src/services/AuthService.ts",
        "src/models/User.ts"
      ],
      "read_when": [
        "src/middleware/auth*",
        "src/services/Auth*",
        "src/routes/auth*",
        "src/models/User*"
      ],
      "entry_files": ["src/services/AuthService.ts"],
      "depends_on": ["database", "config"],
      "depended_by": ["api-routing", "task-management"],
      "confidence": "high",
      "key_patterns": [
        "JWT tokens with 15-minute expiry",
        "Refresh token rotation on every use",
        "bcrypt for password hashing"
      ],
      "data_flow": "HTTP request → auth middleware (JWT verify) → route handler → AuthService → UserRepository → database"
    }
  ],
  "total_modules": 8,
  "analyzed_at": "2025-03-15T10:00:00Z",
  "analyzed_commit": "a1b2c3d"
}
```

## Output: `history.json`

```json
{
  "runs": [
    {
      "timestamp": "2025-03-15T10:00:00Z",
      "commit": "a1b2c3d",
      "mode": "full",
      "modules_analyzed": 8,
      "questions_asked": 8,
      "questions_answered": 5,
      "duration_estimate": "~5 minutes"
    }
  ]
}
```

---

## Incremental Mode

When running `/discovery --incremental` (or when `history.json` already contains a previous run):

### 1. Detect Changes

```bash
# Get the commit from the last run
LAST_COMMIT=$(jq -r '.runs[-1].commit' {{agent_dir}}/discovery/history.json)

# Get changed files since that commit
git diff --name-only "$LAST_COMMIT"..HEAD
```

### 2. Map Changes to Modules

For each changed file, check which module's `source_paths` or `read_when` patterns match. Collect the set of affected modules.

### 3. Re-analyze Affected Modules Only

Run Phase B analysis only on affected modules. Preserve unaffected module data from the existing `modules.json`.

> **Note:** Do NOT update `context.json`'s `analyzed_commit` during incremental runs — only update the affected modules' `last_analyzed` fields in `modules.json`.

### 4. Update Module Dependencies

After re-analyzing, re-run the cross-module dependency mapping (B.3) since dependencies may have changed.

### 5. Generate New Questions

Only generate questions for newly analyzed modules. Preserve existing answered questions.

### 6. Append to History

Add a new entry to `history.json` with `mode: "incremental"` and the list of re-analyzed modules.

---

## Single-Module Mode

When running `/discovery --module <name>`:

1. Look up the module in `modules.json` by name
2. Re-analyze only that module (Phase B)
3. Update its entry in `modules.json`
4. Re-check dependencies involving this module
5. Generate questions only for this module
6. Append to history with `mode: "single"` and the module name

---

## Integration with Setup Flow

During initial setup:
1. Step 1 completes tooling discovery → `.discovery-context.json`
2. Step 1.5 runs generator → creates directory structure
3. **Step 1.7 (this step) runs deep discovery** → `{{agent_dir}}/discovery/*.json`
4. Step 1.8 reads discovery artifacts → generates populated docs

The deep discovery step creates the `{{agent_dir}}/discovery/` directory if it doesn't exist.

