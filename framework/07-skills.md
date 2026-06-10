# Step 7: Skills

> **Part of Conversation 4.** Discovery context should already be loaded from `.discovery-context.json` at the start of this conversation (loaded during `06-rules.md`). If not already in context, re-read `{{agent_dir}}/.discovery-context.json`.

> **Feature gate:** Only create the onboarding skill if `{{discovery.features.onboarding_skill}}` is true. The skills directory and skill creation guide are always created.

## Prerequisites

- Discovery context from Step 1

## Overview

Skills live in `{{discovery.agent_dir}}/skills/<name>/SKILL.md`. They are loaded on demand rather than being always-on context. Use skills for:

- Large instruction sets that shouldn't inflate every session's context (e.g. a 500-line design system guide)
- Specialized workflows triggered by specific requests (e.g. "build a UI component")
- Onboarding flows that run once per new developer or agent

## Directory to Create

```
{{discovery.agent_dir}}/skills/
└── onboard/
    └── SKILL.md
```

## When to Create a Skill vs a Command

- **Command:** short, frequently used, takes arguments (`/dev`, `/build`, `/test`)
- **Skill:** large context payload loaded for a specific type of work (design guide, onboarding walkthrough, specialized domain instructions)

---

## Skill Frontmatter

```yaml
---
name: skill-name
description: When to use this skill (shown in skill picker)
allowed-tools: [Bash, Read, Glob]    # optional — restrict available tools
disable-model-invocation: true        # optional — for pure workflow skills
---
```

---

## Onboarding Skill

Every project should have an `onboard` skill. Its job is to get any person or agent from zero to a running application, then offer a code walkthrough. It should be fully automated — run commands, check results, fix common issues, don't just list steps.

### `skills/onboard/SKILL.md` Template

```markdown
---
name: onboard
description: Automated project setup — installs dependencies, checks environment, runs tests, starts servers
allowed-tools: [Bash, Read, Glob]
---

# Onboarding

Your goal is to get the project running on this machine automatically. Run each step,
check the result, and fix common issues before asking the user for help.

## Step 1: Check Prerequisites

Check required runtime versions:
{{#each discovery.languages}}
- {{.}}: verify installed and correct version
{{/each}}

If a required runtime is missing or wrong version, tell the user what to install and stop.
If all present, continue.

## Step 2: Check Environment File

Look for {{discovery.env_files.found | join(", ")}} or the project's equivalent:
- If found: print "✓ Environment file found"
- If missing: print "⚠ No .env file found"
  {{#if discovery.env_files.example_exists}}
  - Tell the user to copy it: `cp .env.example .env`
  {{/if}}
  - List any required variables the user needs to fill in
  - Do NOT create the file or fill in values automatically

## Step 3: Install Dependencies

{{#if discovery.workspaces}}
Install root dependencies:
`{{discovery.package_managers[0].install_cmd}}`

Verify each workspace has its dependencies installed:
{{#each discovery.workspaces}}
- **{{name}}** (`{{path}}`): check for expected dependency artifacts
{{/each}}

Report success or failure with the full output if any step fails.
{{else}}
{{#if discovery.directories.backend_root}}
### Backend
Check if dependencies are already installed.
If not, run: `{{discovery.package_managers[backend].install_cmd}}`
Report success or failure with the full output if it fails.
{{/if}}

{{#if discovery.directories.frontend_root}}
### Frontend
Check if dependencies are already installed (e.g. node_modules/ exists).
If not, run: `{{discovery.package_managers[frontend].install_cmd}}`
Report success or failure with the full output if it fails.
{{/if}}
{{/if}}

## Step 4: Run Tests

Run the full test suite:
`{{discovery.test_runner.cmd}}`

Report:
- Total tests / passed / failed
- If failures: show the failure output, identify likely cause, suggest fix
- Do NOT proceed past here if tests fail — a broken baseline means everything else is suspect

## Step 5: Start Dev Servers

{{#if discovery.workspaces}}
Start dev servers for each workspace that has one:
{{#each discovery.workspaces}}
{{#if dev_server}}
- **{{name}}**: `{{dev_server.cmd}}` — port {{dev_server.port}}
{{/if}}
{{/each}}
{{else}}
{{#if discovery.dev_servers.backend}}
Start backend server as background process:
`{{discovery.dev_servers.backend.cmd}}`
Port: {{discovery.dev_servers.backend.port}}
{{/if}}

{{#if discovery.dev_servers.frontend}}
Start frontend server as background process:
`{{discovery.dev_servers.frontend.cmd}}`
Port: {{discovery.dev_servers.frontend.port}}
{{/if}}
{{/if}}

Verify each port is listening before reporting success.
Print the URLs.

## Step 6: Offer Code Walkthrough

Once everything is running, offer:

> "The app is running. Want a code walkthrough? I can trace a request from the
> entry point through the full stack — showing you the key files, how data flows,
> and where the important logic lives."

If yes: read {{discovery.context_filename}} to understand the architecture, then walk through
a representative request end-to-end. Go file by file. Explain what each does and why it matters.
```

### Filling Instructions

Replace all `{{discovery.*}}` placeholders with concrete values from the discovery context. The template above uses pseudo-handlebars notation for conditionals and loops — in the actual generated file, these become real content or are omitted based on the project's stack.

For example, a Python-only backend project would not have a "Frontend" section in Step 3 or Step 5. A frontend-only project would not have a "Backend" section.

---

## Creating Additional Skills

To add more skills for the project, create a new directory under `{{discovery.agent_dir}}/skills/` with a `SKILL.md` file following the frontmatter format above.

**Common skill ideas:**
- **design-system** — UI component patterns, color tokens, typography rules
- **api-design** — REST or GraphQL conventions, request/response formats, versioning
- **database** — migration patterns, query optimization, schema conventions
- **testing** — test writing conventions, fixture patterns, what to mock vs. not
- **deployment** — step-by-step deploy procedures, rollback checklist

Each skill should be self-contained — when loaded, it provides everything the agent needs to work in that domain without referencing external docs.

