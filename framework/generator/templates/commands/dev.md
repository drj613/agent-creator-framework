---
description: Start backend and frontend dev servers
argument-hint: [--flag]
---

# Dev Servers

## Variables
ARGS: $ARGUMENTS

## Steps
1. Parse ARGS for any flags (e.g. --cloud, --aws, --staging).
{{#if discovery.dev_servers.backend}}
2. Start backend dev server as background process.
   Command: `{{discovery.dev_servers.backend.cmd}}`
   Port: {{discovery.dev_servers.backend.port}}
{{/if}}
{{#if discovery.dev_servers.frontend}}
3. Start frontend dev server as background process.
   Command: `{{discovery.dev_servers.frontend.cmd}}`
   Port: {{discovery.dev_servers.frontend.port}}
{{/if}}
4. Verify each port is listening before reporting success.
5. Tell the user all URLs and remind them to use `/tasks` to monitor background jobs.
