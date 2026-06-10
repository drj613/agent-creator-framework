# Step 2 — Context File, Bash Best Practices, and Workflow Guide

> **Part of Conversation 3.** At the start of this conversation, read `{{agent_dir}}/.discovery-context.json` to load the discovery context and `{{agent_dir}}/.setup-progress.json` to verify that `"discovery"` and `"generate"` are in `completed_steps`. If either is missing, **stop** and tell the user: "Prerequisites incomplete. Please run Conversation 1 first."
> **Skip if complete:** If `"context_file"` is already in `completed_steps`, skip this step and proceed to `03-commands.md`.

This step produces three files:

1. **Project Context File** (`{{discovery.context_filename}}`) — injected at the start of every agent session to orient the agent on the project.
2. **Bash Best Practices Reference** (`bash-best-practices.md`) — a comprehensive shell reference for reliable command execution by AI agents.
3. **Workflow Guide** (`WORKFLOW.md`) — a human-readable guide at the project root explaining the available commands, the development cycle, and the rules the workflow enforces.

**Prerequisites:** Completed `DISCOVERY_CONTEXT` from Step 1.

---

## Part A: Project Context File

### Purpose

The context file is the first thing the agent reads in every session. It provides a compact overview of the project so the agent can work without rediscovering the codebase each time. This is `CLAUDE.md`, inside `.claude/`.

### Location

```
{{discovery.agent_dir}}/{{discovery.context_filename}}  # e.g., .claude/CLAUDE.md
```

### How to Fill Each Section

**Project Overview**
Use `{{discovery.app_description}}` as the starting point. Read `README.md` and 2-3 key source files (entry points, main modules) to enrich it into a single paragraph that covers what the app does, who uses it, and the core technology.

**Common Commands**
Pull directly from discovery values. Do not guess — use the exact commands recorded in the context:
- Install: `{{discovery.package_managers[0].install_cmd}}`
- Test: `{{discovery.test_runner.cmd}}`
- Dev server: `{{discovery.dev_servers.backend.cmd}}` / `{{discovery.dev_servers.frontend.cmd}}`
- Lint: `{{discovery.linters[0].cmd}}`
- Type check: `{{discovery.type_checkers[0].cmd}}`
- Format: `{{discovery.formatter.cmd}}` (if present)

**Architecture**
Read the source tree. For each top-level directory and key file, write a one-line description of its responsibility. Do not go deeper than two levels unless the project is small.

**Key Patterns**
Identify from reading code: naming conventions, error handling patterns, import style, state management approach, API design patterns. Write as a bullet list.

**Testing**
Run the test suite once. Record the total count, pass/fail breakdown, and document any markers, flags, or categories (e.g., `pytest -m slow`, `vitest --project unit`).

**Commit Workflow**
Pointer to the rules file. Keep this section short — the rules live in their own file.

**Documentation**
Pointer to the docs index. Keep this section short.

### Adaptation Rules

- **frontend-only** projects: omit the Backend subsection under Common Commands.
- **backend-only** projects: omit the Frontend subsection under Common Commands.
- **library** projects: omit dev server commands entirely; add a Build/Publish section instead.
- **monorepo** projects: add a Workspaces section using `{{discovery.workspaces}}` — see the conditional block in the Full Template below.

### Context File Reference

Add this line near the top of the context file, after the Project Overview:

```markdown
> Shell command reference: `{{discovery.agent_dir}}/bash-best-practices.md`
```

This points agents to the bash best practices document when they need to construct reliable shell commands.

### Full Template

````markdown
# {{discovery.context_filename}}

## Project Overview

{{discovery.app_description — enriched with details from README.md and source inspection.}}

> Shell command reference: `{{discovery.agent_dir}}/bash-best-practices.md`

## Common Commands

{{#if discovery.workspaces}}
### Root
```bash
{{discovery.package_managers[0].install_cmd}}    # install all dependencies
{{discovery.test_runner.cmd}}                     # run all tests
{{discovery.linters[0].cmd}}                      # lint all
{{discovery.type_checkers[0].cmd}}                # type check all
```

{{#each discovery.workspaces}}
### {{name}} (`{{path}}`)
```bash
{{test_runner.cmd}}                               # run tests
{{#if dev_server}}
{{dev_server.cmd}}                                # start dev server (port {{dev_server.port}})
{{/if}}
```
{{/each}}
{{else}}
{{#if discovery.directories.backend_root}}
### Backend
```bash
{{discovery.package_managers[backend].install_cmd}}    # install dependencies
{{discovery.test_runner.cmd}}                                # run tests
{{discovery.dev_servers.backend.cmd}}                        # start dev server (port {{discovery.dev_servers.backend.port}})
{{discovery.linters[backend].cmd}}                           # lint
{{discovery.type_checkers[backend].cmd}}                     # type check
```
{{/if}}

{{#if discovery.directories.frontend_root}}
### Frontend
```bash
{{discovery.package_managers[frontend].install_cmd}}    # install dependencies
{{discovery.dev_servers.frontend.cmd}}                       # start dev server (port {{discovery.dev_servers.frontend.port}})
<detected build command>                                     # production build
{{discovery.linters[frontend].cmd}}                          # lint
{{discovery.type_checkers[frontend].cmd}}                    # type check
```
{{/if}}
{{/if}}

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

{{#if discovery.workspaces}}
## Workspaces

| Workspace | Path | Language | Test Command | Dev Server |
|-----------|------|----------|-------------|------------|
{{#each discovery.workspaces}}
| {{name}} | `{{path}}` | {{language}} | `{{test_runner.cmd or '—'}}` | {{#if dev_server}}`{{dev_server.cmd}}` (port {{dev_server.port}}){{else}}—{{/if}} |
{{/each}}
{{/if}}

{{#if discovery.features.deep_discovery}}
## Module Documentation

When modifying code, consult the relevant module doc before planning changes. See [docs/modules/ROUTING.md](docs/modules/ROUTING.md) for the full routing table.

Cross-cutting: `docs/ARCHITECTURE.md` for system-level changes, `docs/DECISIONS.md` for ADRs.
{{/if}}

## Key Patterns

- Example: all API handlers return `{data, error}` shape
- Example: errors are thrown as custom `AppError` classes with status codes
- Example: database access goes through repository pattern, never direct queries in handlers
- Example: components use composition over inheritance
- Example: environment config loaded once at startup via `config.ts`

_(Replace with actual patterns identified from reading the codebase.)_

## Testing

- **Total tests:** <count from running test suite>
- **Runner:** {{discovery.test_runner.name}} (`{{discovery.test_runner.cmd}}`)
- **Markers/flags:** <e.g., `-m slow` for slow tests, `--project unit` for unit only>
- **Coverage:** <if available, current percentage>

## Commit Workflow

Full rules in `{{discovery.agent_dir}}/rules/commit-workflow.md`.
Documentation must be updated BEFORE every commit.

## Documentation

Master index: `docs/README.md` — see the "When to Update" table for where changes belong.
````

---

## Part B: Bash Best Practices Reference

### Purpose

A comprehensive shell reference for AI agents. This file is not a rule file — it is a reference document that agents consult when constructing shell commands. It is especially important because agents have constraints that human developers do not: no persistent shell state, no interactive input, output size limits, and timeout constraints.

### Location

```
{{discovery.agent_dir}}/bash-best-practices.md
```

### Full Template

````markdown
# Bash Best Practices for AI Agents

Reference document for writing reliable shell commands. Not a rule file — consult when constructing non-trivial shell commands.

## Quick Index

| Section | Topic | When to consult |
|---------|-------|----------------|
| §1 | Quoting & Variable Expansion | Variable handling, word splitting, glob issues |
| §2 | Error Handling | `set -e` pitfalls, `trap`, `pipefail` |
| §3 | Command Substitution | `$()` usage, local masking bug |
| §4 | Pipeline Best Practices | `PIPESTATUS`, subshell variable loss |
| §5 | Multiline Strings & Heredocs | Heredoc syntax, delimiter quoting |
| §6 | Process Management | Background processes, PID tracking, port readiness |
| §7 | Temporary Files | `mktemp`, cleanup traps |
| §8 | Portability | macOS bash 3.2, GNU vs BSD, zsh differences |
| §9 | JSON Handling | `jq` patterns, `--arg` injection safety |
| §10 | Common Anti-Patterns | `ls` parsing, `eval`, `rm -rf` safety |
| **§11** | **Agent-Specific Pitfalls** | **No persistent state, no interactive input, timeouts, output limits** |
| Appendix | Quick Reference | Script headers, cleanup patterns, wait-for-server |

> **For AI agents:** Start with §11 (Agent-Specific Pitfalls) — it covers failure modes unique to tool-call execution that don't apply to human interactive use.

---

## 1. Quoting and Variable Expansion

### 1.1 Always double-quote variable expansions

**Why:** Unquoted variables undergo word splitting and glob expansion, causing silent breakage on filenames with spaces or special characters.

```bash
# Bad
cp $file $dest
for f in $files; do echo $f; done

# Good
cp "$file" "$dest"
for f in "${files[@]}"; do echo "$f"; done
```

### 1.2 Use ${var} braces for clarity and safety

**Why:** Without braces, the shell may interpret adjacent characters as part of the variable name.

```bash
# Bad — tries to expand $filename_backup, which is unset
echo "$filename_backup"

# Good — clearly expands $filename then appends _backup
echo "${filename}_backup"
```

### 1.3 Use "$@" not $* for argument forwarding

**Why:** `"$@"` preserves each argument as a separate word. `$*` merges them into one string.

```bash
# Bad — arguments with spaces get split
run_command $*

# Good — each original argument stays intact
run_command "$@"
```

### 1.4 Always quote command substitutions

**Why:** The output of command substitution undergoes word splitting if unquoted.

```bash
# Bad — breaks if path contains spaces
current_dir=$(pwd)
cd $current_dir

# Good
current_dir="$(pwd)"
cd "$current_dir"
```

### 1.5 Single quotes prevent all expansion; double quotes allow $, backticks, \

**Why:** Choosing the wrong quote type either unexpectedly expands variables or fails to expand them.

```bash
# Single quotes: literal string, no expansion
echo 'The value of $HOME is not expanded'

# Double quotes: variables and command substitutions expand
echo "Home directory is $HOME"
echo "Current date: $(date)"
```

### 1.6 Use $HOME not ~ in scripts

**Why:** Tilde expansion is unreliable in some contexts (variable assignments in some shells, inside double quotes).

```bash
# Bad — tilde may not expand in all contexts
config_dir="~/config"

# Good
config_dir="$HOME/config"
```

### 1.7 Use arrays for lists, not space-separated strings

**Why:** Space-separated strings break on entries that contain spaces.

```bash
# Bad — breaks if any filename has spaces
files="file one.txt file two.txt"
for f in $files; do echo "$f"; done

# Good
files=("file one.txt" "file two.txt")
for f in "${files[@]}"; do echo "$f"; done
```

---

## 2. Error Handling

### 2.1 set -e (errexit): understand where it silently disables

**Why:** `set -e` exits on error, but is silently disabled in several common constructs. Relying on it alone creates a false sense of safety.

Places where `set -e` does NOT cause an exit:
- Inside `if` conditions: `if command_that_fails; then ...`
- Left side of `&&` or `||`: `command_that_fails && echo "ok"`
- Commands in `$()` when assigned with `local`: `local result=$(failing_command)`
- Subshells in pipelines (without pipefail)

```bash
# The "local" masking bug — set -e does NOT catch this failure
set -e
my_function() {
    local result=$(failing_command)   # exit code masked by local
    echo "This still runs even if failing_command failed"
}

# Fix: separate declaration and assignment
my_function() {
    local result
    result=$(failing_command)          # now set -e catches the failure
    echo "$result"
}
```

### 2.2 set -u (nounset): catches typos

**Why:** Unset variable references become errors instead of silent empty strings.

```bash
set -u
echo "$UNSET_VARIABLE"   # Error: UNSET_VARIABLE: unbound variable

# Use default values for optional variables
echo "${OPTIONAL_VAR:-default_value}"
```

**Quirk:** On bash 3.2 (macOS default), `"${empty_array[@]}"` triggers an unbound variable error even if the array is declared but empty. Workaround: `${array[@]+"${array[@]}"}`.

### 2.3 set -o pipefail: essential but has edge cases

**Why:** Without pipefail, a pipeline's exit status is only the last command's status. `set -o pipefail` makes it the rightmost failing command's status.

```bash
set -o pipefail
# Without pipefail: exits 0 (grep succeeds)
# With pipefail: exits 1 (curl fails)
curl https://unreachable.example.com | grep "pattern"
```

**Edge case:** SIGPIPE from early pipeline exit can cause false failures.

```bash
# This can fail with pipefail because seq gets SIGPIPE when head closes
seq 1000000 | head -1
```

### 2.4 Prefer explicit error handling over set -e

**Why:** Explicit checks give meaningful error messages and predictable behavior.

```bash
# Relying on set -e — fails silently with no context
set -e
cd /some/directory
make build

# Explicit — clear error messages per step
cd /some/directory || { echo "ERROR: Cannot cd to /some/directory" >&2; exit 1; }
make build || { echo "ERROR: Build failed" >&2; exit 1; }
```

### 2.5 Use trap for cleanup on exit

**Why:** Ensures cleanup runs regardless of how the script exits (success, error, signal).

```bash
cleanup() {
    rm -f "$tmpfile"
    kill "$server_pid" 2>/dev/null
}
trap cleanup EXIT

tmpfile="$(mktemp)"
# ... work with tmpfile — cleanup runs automatically on exit
```

### 2.6 Route error messages to STDERR

**Why:** STDOUT is for data output. Error messages on STDERR keep output pipeable.

```bash
echo "Processing data..." >&2
echo "actual output data"
```

### 2.7 Standardized error function

**Why:** Consistent error reporting with timestamp and source location.

```bash
err() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ERROR: $*" >&2
}

err "Failed to connect to database on port 5432"
```

---

## 3. Command Substitution

### 3.1 Use $() not backticks

**Why:** `$()` nests cleanly and is far more readable than backticks.

```bash
# Bad — backtick nesting is unreadable
result=`echo \`date\``

# Good — nesting is clear
result=$(echo "$(date)")
```

### 3.2 Quotes work independently inside $()

**Why:** The inside of `$()` is a fresh quoting context.

```bash
# This works — inner quotes do not conflict with outer quotes
result="$(grep "pattern" "$file")"
```

### 3.3 Command substitution strips trailing newlines

**Why:** Can cause issues when capturing content that ends with newlines.

```bash
# The trailing newline from echo is stripped
content=$(echo "hello")
# $content is "hello", not "hello\n"

# If you need to preserve trailing newlines, append a sentinel
content="$(cat "$file"; echo x)"
content="${content%x}"
```

### 3.4 Separate local declaration from command substitution

**Why:** `local` always returns 0, masking the exit status of the command substitution.

```bash
# Bad — local masks the exit status of failing_command
local result=$(failing_command)

# Good — assignment failure is detectable
local result
result=$(failing_command)
```

---

## 4. Pipeline Best Practices

### 4.1 PIPESTATUS for per-command exit status

**Why:** `$?` only gives the last command's status. `PIPESTATUS` gives each.

```bash
curl -s https://api.example.com | jq '.data'
# Capture immediately — PIPESTATUS is overwritten by the next command
curl_status=${PIPESTATUS[0]}
jq_status=${PIPESTATUS[1]}
```

### 4.2 Avoid useless use of cat

**Why:** An extra process and pipe for no benefit.

```bash
# Bad
cat file.txt | grep "pattern"

# Good
grep "pattern" file.txt
```

### 4.3 Use process substitution to avoid subshell variable loss

**Why:** In a pipeline, the right side runs in a subshell. Variables set there are lost.

```bash
# Bad — $count is lost after the pipeline
count=0
cat file.txt | while read -r line; do
    ((count++))
done
echo "$count"   # prints 0

# Good — process substitution avoids the subshell
count=0
while read -r line; do
    ((count++))
done < <(cat file.txt)
echo "$count"   # prints the actual count
```

### 4.4 Use mapfile/readarray for safe output-to-array

**Why:** Correctly handles lines with spaces and special characters.

```bash
# Bash 4+
mapfile -t lines < <(some_command)

# Bash 3.x fallback
lines=()
while IFS= read -r line; do
    lines+=("$line")
done < <(some_command)
```

### 4.5 Use -print0 / -0 for null-delimited filenames

**Why:** Newlines are valid in filenames. Null bytes are the only safe delimiter.

```bash
# Safe iteration over files with any characters in names
find /path -name "*.txt" -print0 | while IFS= read -r -d '' file; do
    echo "Processing: $file"
done
```

---

## 5. Multiline Strings and Heredocs

### 5.1 Use heredocs for multiline content

**Why:** More readable and maintainable than chained echo statements or escaped newlines.

```bash
cat > /tmp/config.yaml <<EOF
server:
  host: localhost
  port: 8080
  debug: true
EOF
```

### 5.2 Quote the delimiter to prevent expansion

**Why:** Unquoted delimiters cause `$variables` and `$(commands)` inside the heredoc to expand.

```bash
# Variables WILL expand — $HOME becomes /Users/username
cat <<EOF
Home is $HOME
EOF

# Variables will NOT expand — literal $HOME in output
cat <<'EOF'
Home is $HOME
EOF
```

### 5.3 Use <<- for indented heredocs (tabs only)

**Why:** Allows the heredoc content and closing delimiter to be indented with tabs for readability inside functions or loops.

```bash
if true; then
	cat <<-EOF
	This content can be indented with tabs.
	The leading tabs are stripped from output.
	EOF
fi
```

Note: Only tabs are stripped, not spaces. This is a common source of bugs.

### 5.4 Use descriptive delimiter names

**Why:** `EOF` is ambiguous when multiple heredocs exist in one script.

```bash
# Bad — what does this EOF contain?
cat > config <<EOF
...
EOF

# Good — self-documenting
cat > /etc/nginx/site.conf <<NGINX_CONFIG
server {
    listen 80;
    server_name example.com;
}
NGINX_CONFIG

git commit -m "$(cat <<COMMIT_MSG
feat: add user authentication

Implements JWT-based auth with refresh tokens.
COMMIT_MSG
)"
```

### 5.5 echo does not read stdin — use cat for heredocs

**Why:** `echo` prints its arguments. It does not consume stdin.

```bash
# Wrong — echo ignores the heredoc entirely
echo <<EOF
This never gets printed
EOF

# Correct
cat <<EOF
This gets printed
EOF
```

### 5.6 Here-strings for single-line input

**Why:** Shorter than a heredoc for one line of input.

```bash
# Instead of echo + pipe
echo '{"key": "value"}' | jq '.key'

# Here-string
jq '.key' <<< '{"key": "value"}'
```

---

## 6. Process Management

### 6.1 Capture PIDs immediately with $!

**Why:** `$!` holds the PID of the last backgrounded process. It changes with the next background command.

```bash
my_server &
server_pid=$!
echo "Server started with PID $server_pid"
```

### 6.2 Use kill -0 to check if a process is running

**Why:** Sends no signal — just checks if the process exists and you have permission to signal it.

```bash
if kill -0 "$pid" 2>/dev/null; then
    echo "Process $pid is still running"
else
    echo "Process $pid has exited"
fi
```

### 6.3 Use wait to collect exit statuses

**Why:** Collects the exit status and prevents zombie processes.

```bash
background_task &
pid=$!
# ... do other work ...
wait "$pid"
echo "Background task exited with status $?"
```

### 6.4 Track PIDs in arrays, clean up with trap

**Why:** Multiple background processes need coordinated cleanup.

```bash
pids=()
cleanup() {
    for pid in "${pids[@]}"; do
        kill "$pid" 2>/dev/null
    done
}
trap cleanup EXIT

server_a &
pids+=($!)

server_b &
pids+=($!)
```

### 6.5 Never kill -9 first

**Why:** SIGKILL prevents cleanup handlers (temp files, lock release, connection close). Always try SIGTERM first.

```bash
# Bad — no chance for graceful shutdown
kill -9 "$pid"

# Good — graceful first, force only if needed
kill "$pid"                          # SIGTERM
sleep 2
if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid"                   # SIGKILL as last resort
fi
```

### 6.6 Do not parse ps output — use stored PIDs or pgrep

**Why:** `ps` output format varies across systems. Parsing it is brittle.

```bash
# Bad — fragile text parsing
pid=$(ps aux | grep "[m]y_server" | awk '{print $2}')

# Good — use stored PID from when you started it
my_server &
pid=$!

# Or use pgrep if you must find by name
pid=$(pgrep -f "my_server")
```

### 6.7 Verify server readiness by checking ports, not just PID

**Why:** A process can be alive (PID exists) but not yet listening on its port.

```bash
wait_for_port() {
    local port=$1
    local max_wait=${2:-30}
    local waited=0
    while ! nc -z localhost "$port" 2>/dev/null; do
        if (( waited >= max_wait )); then
            echo "ERROR: Port $port not ready after ${max_wait}s" >&2
            return 1
        fi
        sleep 1
        ((waited++))
    done
    echo "Port $port is ready (waited ${waited}s)" >&2
}

# Usage
node server.js &
server_pid=$!
wait_for_port 3000 30 || { kill "$server_pid"; exit 1; }
```

---

## 7. Temporary Files

### 7.1 Always use mktemp

**Why:** Prevents race conditions and name collisions. Secure by default.

```bash
# Bad — predictable name, race condition
tmpfile="/tmp/myapp_output.txt"

# Good
tmpfile="$(mktemp)"
tmpdir="$(mktemp -d)"
```

### 7.2 Set trap BEFORE creating temp files

**Why:** If creation succeeds but something fails before the trap is set, the temp file leaks.

```bash
# Bad — temp file leaks if something fails between mktemp and trap
tmpfile="$(mktemp)"
# ... other code that might fail ...
trap "rm -f '$tmpfile'" EXIT

# Good — trap is set first
tmpfile=""
cleanup() { [[ -n "$tmpfile" ]] && rm -f "$tmpfile"; }
trap cleanup EXIT
tmpfile="$(mktemp)"
```

### 7.3 Single quotes in trap strings

**Why:** Double-quoted trap strings expand variables at trap-set time, not at trap-run time.

```bash
# Bad — $tmpfile expands NOW, so if it changes later, trap cleans up wrong file
trap "rm -f $tmpfile" EXIT

# Good — single quotes defer expansion to trap execution time
trap 'rm -f "$tmpfile"' EXIT

# Also good — function reference avoids the issue entirely
cleanup() { rm -f "$tmpfile"; }
trap cleanup EXIT
```

### 7.4 macOS-compatible mktemp

**Why:** macOS mktemp requires a template argument (GNU mktemp does not).

```bash
# Works on both macOS and Linux
tmpfile="$(mktemp /tmp/myapp.XXXXXX)"
tmpdir="$(mktemp -d /tmp/myapp.XXXXXX)"
```

---

## 8. Portability Concerns

### 8.1 macOS ships bash 3.2

**Why:** Apple cannot ship bash 4+ due to its GPLv3 license. Many modern bash features are unavailable.

Features NOT available in bash 3.2:
- Associative arrays (`declare -A`)
- `mapfile` / `readarray`
- `${var,,}` / `${var^^}` (case conversion)
- `**` globstar
- `coproc`
- `wait -n`
- Negative array subscripts (`${array[-1]}`)
- `&>>` (append stdout+stderr)

### 8.2 macOS default shell is zsh since Catalina

**Why:** Scripts with `#!/bin/bash` still use bash, but interactive shell behavior may differ from expectations.

### 8.3 Key zsh vs bash differences

| Feature | bash | zsh |
|---|---|---|
| Array indexing | 0-based | 1-based |
| Word splitting on unquoted vars | Yes | No (by default) |
| Regex match variable | `BASH_REMATCH` | `MATCH` / `match` |
| `echo` behavior | No escapes by default | Interprets escapes by default |
| Pipeline exit statuses | `PIPESTATUS` | `pipestatus` (lowercase) |
| Glob no-match behavior | Returns literal pattern | Error by default |

### 8.4 Use #!/usr/bin/env bash for portability

**Why:** bash may not be at `/bin/bash` on all systems (NixOS, Homebrew on macOS, etc.).

```bash
#!/usr/bin/env bash
set -euo pipefail
```

### 8.5 Avoid bashisms in #!/bin/sh scripts

**Why:** `/bin/sh` may be dash, ash, or another minimal shell that does not support bash extensions.

Common bashisms to avoid in sh scripts:
- `[[ ]]` — use `[ ]` instead
- `(( ))` — use `expr` or `$((  ))` instead
- Arrays — no equivalent in sh
- `source` — use `.` instead
- `function` keyword — use `name() { }` instead
- `echo -e` — use `printf` instead
- `<<<` (here-strings) — use `echo | ` instead

### 8.6 GNU vs BSD command differences

| Command | GNU (Linux) | BSD (macOS) |
|---|---|---|
| `sed` in-place | `sed -i 's/a/b/'` | `sed -i '' 's/a/b/'` |
| `grep` PCRE | `grep -P` | `grep -E` (no PCRE) |
| `readlink` canonical | `readlink -f` | `readlink` (no `-f`; use `realpath`) |
| `date` parsing | `date -d '2024-01-01'` | `date -j -f '%Y-%m-%d' '2024-01-01'` |
| `mktemp` | `mktemp` (no template required) | `mktemp /tmp/XXX.XXXXXX` (template required) |
| `xargs` empty | `xargs -r` (skip if empty) | No `-r` flag (runs anyway) |

---

## 9. JSON Handling

### 9.1 Always use jq for JSON — never grep/sed/awk

**Why:** JSON is a structured format. Regex-based extraction breaks on nested objects, escaped quotes, and reformatted output.

```bash
# Bad — breaks on multiline, nested, or escaped JSON
grep '"name"' response.json | sed 's/.*: "//' | sed 's/".*//'

# Good
jq -r '.name' response.json
```

### 9.2 Use --arg for safe variable injection

**Why:** Prevents shell injection and handles all special characters correctly.

```bash
# Bad — breaks if $username contains quotes or special chars
jq ".users[] | select(.name == \"$username\")" data.json

# Good
jq --arg name "$username" '.users[] | select(.name == $name)' data.json
```

### 9.3 Use --argjson for non-string values

**Why:** `--arg` always produces a JSON string. Numbers and booleans need `--argjson`.

```bash
# --arg would produce "42" (string) not 42 (number)
jq --argjson count 42 '.limit = $count' config.json
jq --argjson enabled true '.feature_flags.dark_mode = $enabled' config.json
```

### 9.4 Use -r (--raw-output) when capturing values

**Why:** Without `-r`, jq outputs JSON-encoded strings with surrounding quotes.

```bash
# Without -r: name contains "John" (with literal quotes)
name=$(jq '.name' data.json)

# With -r: name contains John (no quotes)
name=$(jq -r '.name' data.json)
```

### 9.5 Use -e (--exit-status) to detect null/false

**Why:** By default, jq exits 0 even when the result is `null` or `false`.

```bash
# Without -e: exits 0 even if .key does not exist (outputs "null")
jq '.key' data.json

# With -e: exits 1 if result is null or false
if jq -e '.key' data.json > /dev/null 2>&1; then
    echo "Key exists and is truthy"
else
    echo "Key is missing, null, or false"
fi
```

### 9.6 Use jq -n to construct JSON

**Why:** Building JSON with string concatenation produces broken JSON on special characters.

```bash
# Bad — breaks if variables contain quotes or special chars
echo "{\"name\": \"$name\", \"age\": $age}"

# Good
jq -n --arg name "$name" --argjson age "$age" \
    '{name: $name, age: $age}'
```

### 9.7 Validate API responses before parsing

**Why:** APIs return errors, HTML error pages, or empty bodies. Parsing these as JSON produces confusing failures.

```bash
response=$(curl -sf https://api.example.com/data) || {
    echo "ERROR: API request failed" >&2
    exit 1
}

# Validate it is actually JSON before parsing
echo "$response" | jq empty 2>/dev/null || {
    echo "ERROR: Response is not valid JSON" >&2
    echo "$response" | head -5 >&2
    exit 1
}

name=$(echo "$response" | jq -r '.name')
```

### 9.8 Use @sh for safe shell evaluation

**Why:** Produces properly shell-escaped output for eval.

```bash
# Generate shell-safe assignments from JSON
eval "$(jq -r '@sh "NAME=\(.name) AGE=\(.age)"' data.json)"
echo "Name: $NAME, Age: $AGE"
```

---

## 10. Common Anti-Patterns

### 10.1 Parsing ls output

**Why:** `ls` output is locale-dependent and not designed for machine consumption. Filenames with spaces, newlines, or special characters break parsing.

```bash
# Bad
for f in $(ls *.txt); do echo "$f"; done

# Good
for f in *.txt; do echo "$f"; done
```

### 10.2 Reading files line-by-line with for

**Why:** `for` splits on words, not lines. A file with spaces breaks.

```bash
# Bad — splits on whitespace, not newlines
for line in $(cat file.txt); do echo "$line"; done

# Good
while IFS= read -r line; do
    echo "$line"
done < file.txt
```

### 10.3 Using [ ] when [[ ]] is available

**Why:** `[[ ]]` handles unquoted variables, regex matching, and pattern matching safely. `[ ]` requires more careful quoting and has fewer features.

```bash
# Bad in bash — breaks if $var is empty
[ $var = "value" ]

# Good in bash
[[ $var = "value" ]]
[[ $var =~ ^[0-9]+$ ]]    # regex matching
```

### 10.4 cd without failure check

**Why:** If `cd` fails, subsequent commands run in the wrong directory.

```bash
# Bad — if cd fails, rm runs in current directory
cd /some/build/dir
rm -rf output/

# Good
cd /some/build/dir || { echo "ERROR: Cannot cd" >&2; exit 1; }
rm -rf output/
```

### 10.5 rm -rf with variable expansion

**Why:** If the variable is empty or unset, `rm -rf /` can result.

```bash
# DANGEROUS — if $BUILD_DIR is empty, this becomes rm -rf /
rm -rf "$BUILD_DIR/"

# Safer — set -u catches it, or add explicit check
set -u
: "${BUILD_DIR:?BUILD_DIR is not set}"
rm -rf "$BUILD_DIR/"
```

### 10.6 Using eval

**Why:** `eval` executes arbitrary strings as code. It is almost always avoidable and creates injection vulnerabilities.

```bash
# Bad — if $user_input contains "; rm -rf /", it executes
eval "echo $user_input"

# Good — use arrays for dynamic command construction
cmd=("echo" "$user_input")
"${cmd[@]}"
```

### 10.7 &&/|| as if/else

**Why:** `cmd1 && cmd2 || cmd3` is NOT equivalent to if/then/else. If `cmd2` fails, `cmd3` runs too.

```bash
# Bad — if grep succeeds but echo fails, rm still runs
grep "pattern" file && echo "found" || rm file

# Good
if grep "pattern" file; then
    echo "found"
else
    rm file
fi
```

### 10.8 Redirecting to the same file you read

**Why:** The shell truncates the output file before the reading command runs.

```bash
# Bad — file is empty because > truncates it before sort reads it
sort file.txt > file.txt

# Good — use a temp file or sponge
sort file.txt > file_sorted.txt && mv file_sorted.txt file.txt
# Or with moreutils:
sort file.txt | sponge file.txt
```

### 10.9 Use printf instead of echo for arbitrary data

**Why:** `echo` behavior varies across shells (flag handling, escape interpretation). `printf` is consistent.

```bash
# Bad — echo may interpret -n as a flag, or \n as escape
echo "$arbitrary_data"

# Good
printf '%s\n' "$arbitrary_data"
```

### 10.10 Wrong redirection order

**Why:** Redirections are processed left-to-right. Order matters.

```bash
# Bad — stderr goes to original stdout (terminal), not the file
command 2>&1 > file.txt

# Good — stdout goes to file, then stderr goes where stdout now points (file)
command > file.txt 2>&1
```

### 10.11 $RANDOM is not secure

**Why:** `$RANDOM` is a 15-bit PRNG, trivially predictable. Never use it for tokens, passwords, or security-sensitive values.

```bash
# Bad
token="session_$RANDOM"

# Good — cryptographically secure
token=$(openssl rand -hex 32)
# Or on Linux
token=$(head -c 32 /dev/urandom | xxd -p)
```

---

## 11. Agent-Specific Pitfalls

These pitfalls are unique to AI agents executing shell commands through tool calls. They do not apply to human interactive use.

### 11.1 No persistent shell state between tool calls

**Why:** Each tool call starts a fresh shell. Environment variables, working directory changes, aliases, and shell options from previous calls do not carry over.

**Rules:**
- Always use absolute paths.
- Set environment variables in the same command chain where they are used.
- Write state to files if it must persist across tool calls.

```bash
# Bad — two separate tool calls
# Call 1: cd /project && export API_KEY=abc123
# Call 2: npm test   <-- runs in $HOME, API_KEY is unset

# Good — single command chain
cd /project && API_KEY=abc123 npm test

# Good — absolute paths, inline env
API_KEY=abc123 npm test --prefix /project
```

### 11.2 No interactive input

**Why:** Tool calls cannot respond to prompts. Any command that waits for stdin hangs until timeout.

| Tool | Non-interactive flag |
|---|---|
| `apt-get` | `-y` |
| `npm init` | `--yes` or `--init-yes` |
| `pip install` | `--no-input` |
| `git commit` | `-m "message"` (never without `-m`) |
| `git rebase` | never use `-i` |
| `ssh` | `-o BatchMode=yes -o StrictHostKeyChecking=no` |
| `mysql` | `-e "SQL"` |
| `psql` | `-c "SQL"` |
| `rm` (aliased) | use full path `/bin/rm` or `command rm` |
| `cp` (aliased) | use full path or `command cp` |
| `yes/no prompts` | pipe `yes` or use tool-specific flags |

### 11.3 Timeout constraints

**Why:** Agent tool calls have execution time limits (typically 2 minutes). Long-running commands hang and fail.

```bash
# Bad — may exceed timeout
npm install   # can take minutes on slow networks

# Good — use timeout command
timeout 90 npm install || { echo "ERROR: npm install timed out" >&2; exit 1; }

# Good — scope work to fit in time budget
# Instead of running full test suite, run specific tests
pytest tests/unit/test_auth.py -x

# Good — background long operations
npm run build > /tmp/build.log 2>&1 &
build_pid=$!
# Check status in a later tool call
```

### 11.4 Output size limits

**Why:** Agent tool output is truncated beyond a size limit. Large outputs lose important content at the end (where errors usually appear).

```bash
# Bad — full test output may be megabytes
pytest

# Good — limit output to what matters
pytest --tb=short -q 2>&1 | tail -50

# Good — capture to file, read selectively
pytest > /tmp/test_results.txt 2>&1
tail -30 /tmp/test_results.txt

# Good — filter for failures only
pytest --tb=short -q 2>&1 | grep -E "(FAILED|ERROR|test session)"
```

### 11.5 Background processes need explicit verification

**Why:** Starting a background process does not mean it is ready. The agent must verify both that the process is alive AND that the service is reachable.

```bash
# Start server
node server.js > /tmp/server.log 2>&1 &
server_pid=$!
sleep 1

# Step 1: Check process is alive
if ! kill -0 "$server_pid" 2>/dev/null; then
    echo "ERROR: Server process died" >&2
    cat /tmp/server.log >&2
    exit 1
fi

# Step 2: Check port is open (not just PID alive)
for i in $(seq 1 30); do
    if curl -sf http://localhost:3000/health > /dev/null 2>&1; then
        echo "Server ready on port 3000"
        break
    fi
    if (( i == 30 )); then
        echo "ERROR: Server not ready after 30s" >&2
        tail -20 /tmp/server.log >&2
        kill "$server_pid" 2>/dev/null
        exit 1
    fi
    sleep 1
done
```

### 11.6 Avoid TTY-requiring commands

**Why:** Tool calls do not allocate a TTY. Commands that require one hang or fail.

| Avoid | Use instead |
|---|---|
| `vim`, `nano` | Write tool / Edit tool |
| `less`, `more` | `cat`, `head`, `tail` |
| `top`, `htop` | `ps aux`, `ps -eo pid,pcpu,pmem,cmd` |
| `git log` (pager) | `git --no-pager log` |
| `git diff` (pager) | `git --no-pager diff` |
| `man` | `command --help` or web search |
| `python` (REPL) | `python -c "code"` or `python script.py` |
| `mysql` (interactive) | `mysql -e "SELECT ..."` |

### 11.7 Working directory resets between calls

**Why:** Each tool call starts in the default working directory, not where the previous call left off.

```bash
# Bad — two separate calls
# Call 1: cd /project/frontend
# Call 2: npm test   <-- runs in wrong directory

# Good — combine in one call
cd /project/frontend && npm test

# Good — use -C or --prefix flags
npm test --prefix /project/frontend
git -C /project/frontend status
make -C /project/frontend build
```

### 11.8 Long && chains lose error context

**Why:** When a chain fails, the error message does not indicate which command failed.

```bash
# Bad — which step failed?
mkdir -p dist && cp -r src/* dist/ && npm run build && npm run test && echo "done"

# Good — explicit error messages per step
mkdir -p dist || { echo "ERROR: Failed to create dist/" >&2; exit 1; }
cp -r src/* dist/ || { echo "ERROR: Failed to copy source files" >&2; exit 1; }
npm run build || { echo "ERROR: Build failed" >&2; exit 1; }
npm run test || { echo "ERROR: Tests failed" >&2; exit 1; }
echo "done"
```

### 11.9 Prevent editor/pager spawning

**Why:** Git and other tools spawn interactive editors and pagers by default. These hang in non-interactive contexts.

```bash
# Set at the start of any command chain that uses git
export GIT_PAGER=cat
export GIT_EDITOR=true
export PAGER=cat
export EDITOR=true
export VISUAL=true

# Or per-command
git --no-pager log --oneline -20
git -c core.editor=true merge --no-edit
```

### 11.10 File watchers are invisible to agents

**Why:** File watchers (webpack-dev-server, nodemon, jest --watch) produce output over time, but tool calls only see output at the moment of completion.

```bash
# Bad — runs forever, tool call times out
npm run dev

# Good — background with output redirect, check output file
npm run dev > /tmp/dev_server.log 2>&1 &
server_pid=$!
sleep 5
tail -20 /tmp/dev_server.log
```

### 11.11 Handle empty globs

**Why:** By default in bash, a glob that matches nothing expands to the literal pattern string, causing unexpected behavior.

```bash
# Bad — if no .log files exist, this tries to rm the literal string "*.log"
rm /tmp/*.log

# Good — nullglob option
shopt -s nullglob
files=(/tmp/*.log)
if (( ${#files[@]} > 0 )); then
    rm "${files[@]}"
fi

# Good — explicit existence check
for f in /tmp/*.log; do
    [[ -e "$f" ]] || continue
    rm "$f"
done
```

---

## Appendix: Quick Reference for Agents

### Recommended Script Header

```bash
#!/usr/bin/env bash
set -euo pipefail
```

### Non-Interactive Environment Setup

Place at the beginning of command chains that invoke git or other tools with interactive defaults.

```bash
export GIT_PAGER=cat
export GIT_EDITOR=true
export PAGER=cat
export EDITOR=true
export VISUAL=true
export GIT_TERMINAL_PROMPT=0
export NPM_CONFIG_YES=true
export PIP_NO_INPUT=1
export DEBIAN_FRONTEND=noninteractive
```

### Reliable Cleanup Pattern

```bash
tmpfile=""
tmpdir=""
cleanup() {
    [[ -n "$tmpfile" ]] && rm -f "$tmpfile"
    [[ -n "$tmpdir" ]] && rm -rf "$tmpdir"
}
trap cleanup EXIT

tmpfile="$(mktemp /tmp/myapp.XXXXXX)"
tmpdir="$(mktemp -d /tmp/myapp_dir.XXXXXX)"
```

### Safe JSON Round-Trip

Read, modify, and write back a JSON file without corruption.

```bash
tmpfile="$(mktemp /tmp/json_edit.XXXXXX)"
trap 'rm -f "$tmpfile"' EXIT

# Read and modify
jq --arg version "2.0.0" '.version = $version' config.json > "$tmpfile" || {
    echo "ERROR: jq transformation failed" >&2
    exit 1
}

# Validate the output is valid JSON
jq empty "$tmpfile" 2>/dev/null || {
    echo "ERROR: Produced invalid JSON" >&2
    exit 1
}

# Write back
mv "$tmpfile" config.json
```

### Wait-for-Server Function

```bash
wait_for_port() {
    local port=$1
    local max_wait=${2:-30}
    local waited=0
    echo "Waiting for port $port..." >&2
    while ! nc -z localhost "$port" 2>/dev/null; do
        if (( waited >= max_wait )); then
            echo "ERROR: Port $port not ready after ${max_wait}s" >&2
            return 1
        fi
        sleep 1
        ((waited++))
    done
    echo "Port $port ready after ${waited}s" >&2
}

# Alternative using curl (for HTTP services)
wait_for_http() {
    local url=$1
    local max_wait=${2:-30}
    local waited=0
    echo "Waiting for $url..." >&2
    while ! curl -sf "$url" > /dev/null 2>&1; do
        if (( waited >= max_wait )); then
            echo "ERROR: $url not ready after ${max_wait}s" >&2
            return 1
        fi
        sleep 1
        ((waited++))
    done
    echo "$url ready after ${waited}s" >&2
}

# Usage
node server.js > /tmp/server.log 2>&1 &
server_pid=$!
wait_for_port 3000 30 || { kill "$server_pid" 2>/dev/null; exit 1; }
```

---

## Project-Specific Patterns

This section is filled from discovery context during setup. It captures project-specific shell patterns such as:

- Virtual environment activation paths (e.g., `source .venv/bin/activate`)
- Runtime-specific commands (e.g., `uv run pytest` instead of `pytest`)
- Project-specific conventions (e.g., `make dev` instead of separate commands)
- CI/CD command equivalents for local testing
- Database migration commands
- Seed/fixture loading commands

_(Populated by the setup agent based on `DISCOVERY_CONTEXT` values.)_
````

---

## Part C: Workflow Guide

### Purpose

A human-readable reference for developers (and agents in future sessions) explaining what the workflow provides, how to use each command, and what rules are in effect. Unlike the context file (which is agent-oriented and loaded every session), this is a standalone document that a new team member can read to understand the project's development conventions.

### Location

```
WORKFLOW.md    ← project root
```

### How to Fill Each Section

**Available Commands** — list only the commands enabled in `{{discovery.features}}`. Pull the description from each command's frontmatter.

**Development Cycle** — adapt the cycle diagram to the project type. Libraries won't have `/dev` or `/verify-browser`. Backend-only projects skip browser verification.

**Agent Team** — describe the builder and validator roles, and explain what the hooks do.

**Rules** — summarize the commit workflow and documentation rules. Link to the full rule files.

### Full Template

````markdown
# Workflow Guide

This project uses an AI-assisted development workflow. This guide explains the available commands, the development cycle, and the rules the workflow enforces.

## Available Commands

{{#if discovery.features.dev_command}}
### `/dev`
Start backend and frontend dev servers in the background. Verifies ports are listening before reporting success.
{{/if}}

{{#if discovery.features.plan_build}}
### `/plan_w_team [requirement]`
Analyze a requirement, explore the codebase, and save a detailed implementation plan to `specs/`. No code is written — output is a spec document that `/build` consumes.

### `/build [path-to-plan]`
Pre-flight check a plan (verify agents exist, check dependency graph), then execute it by dispatching the builder and validator agent team. Includes error recovery with a single-retry limit.
{{/if}}

{{#if discovery.features.review}}
### `/review [commit-range or --staged]`
Run three parallel specialist reviewers (security, architecture, test coverage) against the diff, then synthesize findings into a prioritized report with must-fix, should-fix, and consider categories.
{{/if}}

{{#if discovery.features.verify_browser}}
### `/verify-browser [number-of-commits]`
Inspect recent commits for user-visible changes, build a verification checklist, then use Playwright to walk through each item in the browser.
{{/if}}

{{#if discovery.features.test}}
### `/test [path-or-pattern]`
Run the test suite and present structured results. Read-only — never modifies source or test files.
{{/if}}

{{#if discovery.features.audit_docs}}
### `/audit-docs [--fix]`
Audit `docs/` and `specs/` for staleness, orphaned files, and drift from the codebase. With `--fix`, auto-cleans obvious temporary files and archives completed specs.
{{/if}}

## Development Cycle

The typical workflow follows this sequence:

```
/plan_w_team "describe the feature or fix"
  ↓
  review and edit the spec in specs/
  ↓
/build specs/<plan-name>.md
  ↓
  builder writes code (auto-validated by lint/type-check hooks on every save)
  validator checks acceptance criteria + runs full test suite
  ↓
/review
  ↓
  address any findings
  ↓
/test
  ↓
  commit (documentation updated alongside code — see Rules below)
```

## Agent Team

{{#if discovery.features.plan_build}}
### Builder
Executes one assigned task at a time. Every file write triggers PostToolUse hooks that run the project's linters and type checkers automatically. If a hook finds an error, the builder must fix it before continuing. Runs the full test suite before marking any task complete.

### Validator
Read-only agent — cannot modify files (enforced at the tool level, not just instructed). Checks that acceptance criteria from the plan are met, then runs the test suite, linters, and type checkers independently.
{{/if}}

{{#if discovery.features.post_tool_use_hooks}}
### Validation Hooks

The builder agent has PostToolUse hooks that fire on every `Write` or `Edit`:
{{#each discovery.linters}}
- **{{name}}** — runs `{{cmd}}` on {{file_extensions}} files
{{/each}}
{{#each discovery.type_checkers}}
- **{{name}}** — runs `{{cmd}}` on {{file_extensions}} files
{{/each}}

If any validator returns an error, the agent is blocked until the issue is fixed. This catches problems immediately rather than letting them compound.
{{/if}}

## Rules

{{#if discovery.features.commit_workflow}}
### Commit Workflow

Documentation must be updated **before** every commit, not after. The sequence:

1. Complete code changes
2. Update the relevant documentation (see table below)
3. Update `CHANGELOG.md`
4. Run tests: `{{discovery.test_runner.cmd}}`
5. Stage everything (code AND docs together)
6. Commit

| You changed... | Update this file |
|----------------|-----------------|
| System architecture | `docs/ARCHITECTURE.md` |
| Local dev setup | `docs/DEVELOPMENT.md` |
| Deploy process | `docs/DEPLOYMENT.md` |
| Made an architectural decision | `docs/DECISIONS.md` |
| Found/fixed a performance issue | `docs/PERFORMANCE.md` |
| Any code change at all | `CHANGELOG.md` |
{{/if}}

{{#if discovery.features.documentation_structure}}
### Documentation Rules

- **Permanent docs** (`docs/ARCHITECTURE.md`, `DEVELOPMENT.md`, `DEPLOYMENT.md`, `DECISIONS.md`, `PERFORMANCE.md`) are updated in place — never create a new file when one of these covers the topic.
- **Temporary docs** (meeting notes, analysis summaries, versioned files) must be cleaned up after insights are extracted into permanent docs.
- Check the doc index (`docs/README.md`) before creating any new documentation file.
- Run `/audit-docs` periodically to catch drift between docs and code.
{{/if}}

## Project-Specific Commands

```bash
# Install dependencies
{{discovery.package_managers[0].install_cmd}}

# Run tests
{{discovery.test_runner.cmd}}

{{#if discovery.workspaces}}
# Start dev servers (per workspace)
{{#each discovery.workspaces}}
{{#if dev_server}}
{{dev_server.cmd}}    # {{name}} (port {{dev_server.port}})
{{/if}}
{{/each}}
{{else}}
# Start dev servers
{{#if discovery.dev_servers.backend}}
{{discovery.dev_servers.backend.cmd}}    # backend (port {{discovery.dev_servers.backend.port}})
{{/if}}
{{#if discovery.dev_servers.frontend}}
{{discovery.dev_servers.frontend.cmd}}   # frontend (port {{discovery.dev_servers.frontend.port}})
{{/if}}
{{/if}}

# Lint
{{discovery.linters[0].cmd}}

# Type check
{{discovery.type_checkers[0].cmd}}
```

## Key Files

| File | Purpose |
|------|---------|
| `{{discovery.agent_dir}}/{{discovery.context_filename}}` | Project context loaded every agent session |
| `{{discovery.agent_dir}}/commands/` | Slash command definitions |
| `{{discovery.agent_dir}}/agents/team/` | Builder and validator agent definitions |
| `{{discovery.agent_dir}}/hooks/` | Validation hooks and audit scripts |
| `{{discovery.agent_dir}}/rules/` | Commit and documentation rules |
| `docs/README.md` | Documentation index — "When to Update" table |
| `specs/` | Implementation plans from `/plan_w_team` |
````

### Adaptation Rules

- **Libraries:** omit `/dev`, `/verify-browser`, and dev server sections.
- **Backend-only:** omit frontend commands and `/verify-browser`.
- **Frontend-only:** omit backend commands.
- Only include sections for enabled features — conditionals in the template (the `{{#if}}` blocks) indicate which sections to include or omit.

