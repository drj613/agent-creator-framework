# Generator Templates

Starter templates for generated project files. All `{{discovery.*}}` placeholders are filled in by the setup agent during framework setup (Step 2–7 of the framework guide).

## Structure

```
templates/
├── commands/           # Slash command files → {{agent_dir}}/commands/
│   ├── dev.md          # /dev — start dev servers
│   ├── plan_w_team.md  # /plan_w_team — create implementation plan
│   ├── build.md        # /build — execute a plan with agent team
│   ├── review.md       # /review — parallel domain-specialist code review
│   ├── verify-browser.md  # /verify-browser — Playwright UI verification
│   ├── test.md         # /test — run tests and report
│   └── audit-docs.md   # /audit-docs — documentation health check
├── context/
│   └── CLAUDE.md       # Context file template → {{agent_dir}}/CLAUDE.md or AGENTS.md
├── rules/
│   ├── commit-workflow.md      # → {{agent_dir}}/rules/commit-workflow.md
│   └── documentation-rules.md  # → {{agent_dir}}/rules/documentation-rules.md
└── skills/
    └── onboard/
        └── SKILL.md    # Onboarding skill → {{agent_dir}}/skills/onboard/SKILL.md
```

## Usage

During setup, the agent copies the relevant template, replaces all `{{discovery.*}}` placeholders with actual values from the discovery context, and writes the result to the target location.

**Feature gates** (from `discovery.features`):
- `commands/dev.md` — only if `features.dev_command` is true
- `commands/plan_w_team.md` + `commands/build.md` — only if `features.plan_build` is true
- `commands/review.md` — only if `features.review` is true
- `commands/fix.md` — only if `features.review` is true
- `commands/verify-browser.md` — only if `features.verify_browser` is true
- `commands/test.md` — only if `features.test` is true
- `commands/audit-docs.md` — only if `features.audit_docs` is true
- `rules/commit-workflow.md` — only if `features.commit_workflow` is true
- `rules/documentation-rules.md` — only if `features.documentation_structure` is true
- `skills/onboard/SKILL.md` — only if `features.onboarding_skill` is true

See the framework step guides (`03-commands.md`, `02-context-file.md`, `06-rules.md`, `07-skills.md`) for full adaptation instructions.
