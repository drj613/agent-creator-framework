# Commit Workflow

Documentation is updated **before** creating a commit, not after.

## Pre-commit Checklist

Complete each step in order before running `git commit`:

1. **Code changes complete** — all intended code changes are written and saved
2. **Documentation updated** — see the Where-to-Document table below
3. **CHANGELOG.md updated** — add an entry describing what changed
4. **Tests pass** — run `{{discovery.test_runner.cmd}}` and confirm all pass
5. **All changes staged** — stage code AND docs together in the same commit
6. **Commit** — use a descriptive message following the template below

## Where to Document

| You changed... | Update this file |
|----------------|-----------------|
| System architecture | `docs/ARCHITECTURE.md` |
| Local dev setup | `docs/DEVELOPMENT.md` |
| Deploy process | `docs/DEPLOYMENT.md` |
| Made an architectural decision | `docs/DECISIONS.md` |
| Found/fixed a performance issue | `docs/PERFORMANCE.md` |
| Any code change at all | `CHANGELOG.md` |

## Commit Message Template

```
<action>: <what changed>

- <specific change 1>
- <specific change 2>

Docs updated: <list of doc files changed>
Tests: <X/X passed>
```

### Example

```
feat: add user authentication endpoints

- POST /auth/login with JWT token generation
- POST /auth/logout with token invalidation
- Middleware for protected routes

Docs updated: docs/ARCHITECTURE.md, CHANGELOG.md
Tests: 47/47 passed
```

## What NOT to Do

- Do not commit code without updating relevant docs
- Do not create a separate "docs update" commit after the code commit
- Do not skip the CHANGELOG
- Do not commit with failing tests
- Do not stage docs and code in separate commits
