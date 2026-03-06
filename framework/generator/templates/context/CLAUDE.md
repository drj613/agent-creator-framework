# {{discovery.context_filename}}

## Project Overview

{{discovery.app_description — enriched with details from README.md and source inspection.}}

> Shell command reference: `{{discovery.agent_dir}}/bash-best-practices.md`

## Common Commands

### Backend
```bash
{{discovery.package_managers[backend].install_cmd}}    # install dependencies
{{discovery.test_runner.cmd}}                          # run tests
{{discovery.dev_servers.backend.cmd}}                  # start dev server (port {{discovery.dev_servers.backend.port}})
{{discovery.linters[backend].cmd}}                     # lint
{{discovery.type_checkers[backend].cmd}}               # type check
```

### Frontend
```bash
{{discovery.package_managers[frontend].install_cmd}}   # install dependencies
{{discovery.dev_servers.frontend.cmd}}                 # start dev server (port {{discovery.dev_servers.frontend.port}})
<detected build command>                               # production build
{{discovery.linters[frontend].cmd}}                    # lint
{{discovery.type_checkers[frontend].cmd}}              # type check
```

## Architecture

```
src/
  auth/          — Authentication and session management
  api/           — Route handlers and middleware
  models/        — Database models and schema definitions
  services/      — Business logic layer
  utils/         — Shared utilities and helpers
tests/           — Test suite (mirrors src/ structure)
docs/            — Project documentation
```

_(Replace with actual project structure discovered from source tree.)_

{{#if discovery.features.deep_discovery}}
## Module Documentation

When modifying code, consult the relevant module doc before planning changes. See [docs/modules/ROUTING.md](docs/modules/ROUTING.md) for the full routing table.

Cross-cutting: `docs/ARCHITECTURE.md` for system-level changes, `docs/DECISIONS.md` for ADRs.
{{/if}}

## Key Patterns

- Example: all API handlers return `{data, error}` shape
- Example: errors are thrown as custom `AppError` classes with status codes
- Example: database access goes through repository pattern, never direct queries in handlers

_(Replace with actual patterns identified from reading the codebase.)_

## Testing

- **Total tests:** <count from running test suite>
- **Runner:** {{discovery.test_runner.name}} (`{{discovery.test_runner.cmd}}`)
- **Markers/flags:** <e.g., `-m slow` for slow tests>
- **Coverage:** <if available, current percentage>

## Commit Workflow

Full rules in `{{discovery.agent_dir}}/rules/commit-workflow.md`.
Documentation must be updated BEFORE every commit.

## Documentation

Master index: `docs/README.md` — see the "When to Update" table for where changes belong.
