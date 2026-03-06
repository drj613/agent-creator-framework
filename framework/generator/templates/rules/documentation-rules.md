# Documentation Rules

## Permanent Docs

These files are updated in place, forever. Never create a new file when one of these covers the topic:

- `docs/ARCHITECTURE.md` — system design, data flow, component relationships
- `docs/DEVELOPMENT.md` — local setup, dev commands, toolchain configuration
- `docs/DEPLOYMENT.md` — production deploy procedures, environment requirements
- `docs/DECISIONS.md` — Architecture Decision Records (ADRs)
- `docs/PERFORMANCE.md` — bottlenecks, optimizations, benchmark results
- `CHANGELOG.md` — version history, updated on every commit

## Temporary Docs

Temporary docs have a lifecycle: **extract → update permanent doc → delete**.

Patterns that identify temporary docs:
- Analysis docs: `*_ANALYSIS.md`, `*_SUMMARY.md`, `*_RESULTS.md`
- Meeting notes: `*_MEETING.md`, `*_NOTES.md`
- Versioned files: `*_v0.9.7.md`, `*_2024-01-15.md`

**Lifecycle:** Extract any decisions or insights → update the appropriate permanent doc → delete the temporary file. These should never linger more than one sprint/milestone.

## Where to Document

| You changed... | Update this file |
|----------------|-----------------|
| System architecture | `docs/ARCHITECTURE.md` |
| Local dev setup | `docs/DEVELOPMENT.md` |
| Deploy process | `docs/DEPLOYMENT.md` |
| Architectural decision | `docs/DECISIONS.md` |
| Performance issue | `docs/PERFORMANCE.md` |
| Any code change | `CHANGELOG.md` |

## ADR Format

For architectural decisions in `docs/DECISIONS.md`:

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

## The Cardinal Rule

Check `docs/README.md` before creating any new documentation file. If an appropriate permanent doc already exists, update it instead of creating a new one.

{{#if discovery.features.deep_discovery}}
## Module Documentation

- Check `docs/modules/ROUTING.md` for the routing table before modifying code in a module
- Read `docs/modules/<module>.md` before modifying code in a module
- Update module docs when changing behavior described in them
- Don't remove YAML frontmatter from module docs
- Run `/discovery --module <name>` to refresh a specific module after significant changes
- Protect hand-written sections with `<!-- human-maintained -->` / `<!-- /human-maintained -->` tags
{{/if}}
