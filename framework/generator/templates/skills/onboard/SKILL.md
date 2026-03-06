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

### Backend
Check if dependencies are already installed.
If not, run: `{{discovery.package_managers[backend].install_cmd}}`
Report success or failure with the full output if it fails.

### Frontend
Check if dependencies are already installed (e.g. node_modules/ exists).
If not, run: `{{discovery.package_managers[frontend].install_cmd}}`
Report success or failure with the full output if it fails.

## Step 4: Run Tests

Run the full test suite:
`{{discovery.test_runner.cmd}}`

Report:
- Total tests / passed / failed
- If failures: show the failure output, identify likely cause, suggest fix
- Do NOT proceed past here if tests fail — a broken baseline means everything else is suspect

## Step 5: Start Dev Servers

Start backend server as background process:
`{{discovery.dev_servers.backend.cmd}}`
Port: {{discovery.dev_servers.backend.port}}

Start frontend server as background process:
`{{discovery.dev_servers.frontend.cmd}}`
Port: {{discovery.dev_servers.frontend.port}}

Verify each port is listening before reporting success.
Print the URLs.

## Step 6: Offer Code Walkthrough

Once everything is running, offer:

> "The app is running. Want a code walkthrough? I can trace a request from the
> entry point through the full stack — showing you the key files, how data flows,
> and where the important logic lives."

If yes: read {{discovery.context_filename}} to understand the architecture, then walk through
a representative request end-to-end. Go file by file. Explain what each does and why it matters.
