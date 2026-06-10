# Troubleshooting Guide

Common failure modes when running the agent-workflow-creator framework, with diagnosis and fix steps.

---

## 1. jq not found

**Symptom:**
```
ERROR: jq is required but not found. Install: brew install jq (macOS) or apt-get install jq (Linux)
```
`generate.sh` exits immediately after printing this message. The same error appears if you run `audit-docs.sh` directly.

**Cause:**
Both `generate.sh` and the generated `audit-docs.sh` explicitly check for `jq` with `command -v jq` before doing any work. `jq` is not bundled with macOS or most Linux distributions.

**Fix:**
```bash
# macOS
brew install jq

# Ubuntu / Debian
sudo apt-get install -y jq

# Fedora / RHEL
sudo dnf install -y jq

# Verify
jq --version   # should print jq-1.6 or later
```
Re-run `generate.sh` after installing.

---

## 3. Unresolved template markers

**Symptom:**
Generated files (context file, commands, rules, `WORKFLOW.md`) contain literal strings like `{{discovery.app_description}}`, `{{agent_dir}}`, or `{{discovery.linters[0].cmd}}` instead of real values. The literal string `null` may also appear in command positions (e.g., in frontmatter `command:` fields or hook script paths).

**Cause:**
The `{{discovery.*}}` syntax in step files 02–08 is pseudo-templating that the setup agent resolves by reading the discovery context. If Step 1 was skipped, the in-memory context was lost and `.discovery-context.json` was not reloaded, or a field in the JSON is `null` and the agent failed to apply the "omit null" rule, markers appear verbatim in output.

**Fix:**
1. Scan all generated files for unresolved markers:
   ```bash
   grep -rn '{{' .claude/
   grep -rn '{{' WORKFLOW.md CLAUDE.md 2>/dev/null
   # Also look for literal "null" in paths or commands
   grep -rn ': null' .claude/agents/ .claude/commands/ 2>/dev/null
   ```
2. For each unresolved marker, look up the correct value in the discovery context:
   ```bash
   jq . .claude/.discovery-context.json
   ```
3. If `.discovery-context.json` is missing or invalid, re-run Step 1 (discovery) to regenerate it, then re-run the affected setup steps.
4. Common fields that produce markers when `null`:
   - `{{discovery.directories.backend_root}}` — project has no backend split; omit the line entirely.
   - `{{discovery.formatter.cmd}}` — no formatter detected; `formatter` is `null`, omit the block.
   - `{{discovery.dev_servers.backend.cmd}}` — frontend-only project; omit the backend section.

For any `null` field, the correct behavior is to omit the entire line or block — not to output `"null"` or the marker text.

---

## 4. validate.sh: required field missing

**Symptom:**
```
ERROR: Missing required fields in discovery context: .agent_dir .models.complex
```
or
```
ERROR: features.post_tool_use_hooks is true but no linters or type_checkers are defined
```
`generate.sh` exits after the validation step before creating any files.

**Cause:**
`validate.sh` enforces a required-field checklist and conditional rules before generation runs. The discovery JSON is either incomplete (a mandatory field was omitted) or internally inconsistent (a feature was enabled without its dependency satisfied).

**Fix:**
1. Open the discovery context and locate the reported field:
   ```bash
   jq . .claude/.discovery-context.json
   ```
2. Required top-level fields that must be non-null:
   - `.agent_dir`, `.context_filename`, `.project_type`, `.primary_language`
   - `.test_runner.cmd`, `.test_runner.name`
   - `.models.complex`, `.models.standard`, `.models.simple`
3. Conditional requirements enforced by `validate.sh`:
   - `features.post_tool_use_hooks == true` requires at least one entry in `.linters` or `.type_checkers`
   - `project_type == "monorepo"` requires `.workspaces` to be a non-empty array
   - `features.audit_docs == true` requires `features.documentation_structure == true`
4. Array fields (`.linters`, `.type_checkers`) must be JSON arrays, never `null`:
   ```json
   "linters": [],
   "type_checkers": []
   ```
5. Edit `.discovery-context.json` to add the missing values, then re-run:
   ```bash
   bash framework/generator/generate.sh .claude/.discovery-context.json
   ```

---

## 5. agents.sh: malformed YAML

**Symptom:**
The generated `builder.md` or `validator.md` fails to load in the agent platform. Claude Code reports a YAML parse error on startup, or the agent does not appear in the agent list. Hooks defined in the frontmatter are silently ignored.

**Cause:**
`agents.sh` builds frontmatter YAML by string interpolation. If a discovery field contains characters that are special in YAML — colons, unquoted quotes, leading dashes, or newlines — most often in `models.standard`, linter `cmd` fields, or `agent_dir` — the generated YAML block will be syntactically invalid.

**Fix:**
1. Inspect the frontmatter of the generated file:
   ```bash
   head -40 .claude/agents/team/builder.md
   ```
2. Validate the frontmatter in isolation:
   ```bash
   sed -n '/^---$/,/^---$/p' .claude/agents/team/builder.md \
     | python3 -c "import sys, yaml; yaml.safe_load(sys.stdin) and print('YAML OK')"
   ```
3. Common causes and fixes:
   - **Colon in a model name** — wrap the value in quotes in `.discovery-context.json`: `"models.standard": "\"model-name:variant\""`.
   - **Spaces in `agent_dir`** — the hook `command:` line expands `$PROJECT_DIR/<agent_dir>/...`; a path with spaces breaks shell splitting. Use a path without spaces.
   - **Multiline linter `cmd`** — `cmd` must be a single line. Remove embedded newlines from the value in `.discovery-context.json`.
4. After correcting `.discovery-context.json`, regenerate:
   ```bash
   bash framework/generator/generate.sh .claude/.discovery-context.json
   ```

---

## 6. Hook path derivation fails in monorepos

**Symptom:**
A generated validator script resolves its project root incorrectly at runtime. The `cd "$SCRIPT_DIR/../.."` fallback lands inside a workspace subdirectory instead of the repository root, causing linter commands to run from the wrong directory or fail to find config files.

**Cause:**
`compute_fallback_depth` in `helpers.sh` calculates the `../` chain based on the depth of `<agent_dir>/hooks/validators/` below the project root. If `agent_dir` is set to a workspace-relative path (e.g., `apps/api/.claude`) rather than a root-relative path (e.g., `.claude`), the depth count is wrong and the fallback resolves to the wrong directory. The primary `git rev-parse --show-toplevel` path still works, but environments without git fall back to the broken `cd` chain.

Additionally, `resolve_target_dir` in `helpers.sh` matches a linter's `language` field against `directories.backend_lang` and `directories.frontend_lang`. If those fields are `null` (common in monorepos where language-to-dir mapping is workspace-level), the function returns an empty string and the validator runs from the project root instead of the relevant workspace.

**Fix:**
1. Confirm `agent_dir` is relative to the repository root, not to a workspace:
   ```bash
   jq '.agent_dir' .claude/.discovery-context.json
   # Correct: ".claude"
   # Incorrect: "apps/api/.claude"
   ```
2. Confirm `directories.project_root` is the absolute repository root:
   ```bash
   jq '.directories.project_root' .claude/.discovery-context.json
   ```
3. For workspace-specific linter targeting, verify `language` fields and directory mappings match exactly (case-sensitive):
   ```bash
   jq '{backend_lang: .directories.backend_lang, linter_langs: [.linters[].language]}' \
     .claude/.discovery-context.json
   ```
4. If a validator still resolves to the wrong directory, patch the `TARGET_DIR` assignment in the generated script directly as an immediate fix. Then correct `.discovery-context.json` and regenerate for the permanent fix:
   ```bash
   bash framework/generator/generate.sh .claude/.discovery-context.json
   ```

---

## 7. generate.sh exits 0 but no files created

**Symptom:**
`generate.sh` completes with exit code 0 and prints "Done. 0 file(s) created." or only prints dry-run output, but no files appear on disk in the expected location.

**Cause (a) — `--dry-run` left on:**
The `--dry-run` flag was passed (or persisted in a shell alias/script), so the generator prints what it would create without writing anything.

**Cause (b) — wrong `project_root`:**
`directories.project_root` in the discovery JSON points to a path other than the intended target. Files are written there (and `mkdir -p` silently creates it), just not where the user is looking.

**Fix for --dry-run:**
Check whether the flag is the cause by running with it intentionally, then remove it:
```bash
# Dry run shows "Dry run — showing files that would be created"
bash framework/generator/generate.sh .claude/.discovery-context.json --dry-run

# Real run — omit the flag
bash framework/generator/generate.sh .claude/.discovery-context.json
```

**Fix for wrong project root:**
```bash
# See where the generator thinks the project root is
jq '.directories.project_root' .claude/.discovery-context.json

# If null or wrong, set it to the current directory
jq --arg p "$(pwd)" '.directories.project_root = $p' \
  .claude/.discovery-context.json > /tmp/ctx.json \
  && mv /tmp/ctx.json .claude/.discovery-context.json

# Re-run from the repository root
bash framework/generator/generate.sh .claude/.discovery-context.json
```

When `project_root` is `null` or absent, `generate.sh` falls back to `$(pwd)` — always run from the repository root in that case.

---

## 8. Permission denied on generated scripts

**Symptom:**
```
bash: .claude/hooks/validators/eslint_validator.sh: Permission denied
```
Or a hook fires but Claude Code cannot execute the validator script because the executable bit is not set.

**Cause:**
`write_executable` in `helpers.sh` calls `chmod +x` after writing each hook script, but only when `DRY_RUN != "true"`. The bit is absent if: a dry run was done and files were then copied manually; the filesystem was restored from a backup that did not preserve permissions; or the generator was interrupted between writing a file and applying `chmod`.

**Fix:**
```bash
# Re-apply executable permission to all generated hook scripts
chmod +x .claude/hooks/*.sh
chmod +x .claude/hooks/validators/*.sh

# Verify
ls -la .claude/hooks/validators/
# Each .sh file should show -rwxr-xr-x (or similar with x bits)
```
Alternatively, rerun the generator — it re-applies `chmod +x` on every file it writes:
```bash
bash framework/generator/generate.sh .claude/.discovery-context.json
```

---

## 9. Context file not loaded by agent

**Symptom:**
The agent does not have project-specific knowledge — wrong test commands, generic tool names, project rules are ignored. Running `/dev` or `/build` produces responses that do not reflect the project setup. The context file exists on disk but appears to be ignored.

**Cause:**
Claude Code requires the context file to be named `CLAUDE.md` and to live inside `agent_dir` (e.g., `.claude/CLAUDE.md`). If the setup agent wrote it to the wrong path (e.g., project root), Claude Code silently starts without it.

**Fix:**
1. Check the discovery JSON for the context file settings:
   ```bash
   jq '{agent_dir}' .claude/.discovery-context.json
   ```
2. Verify the file exists at the correct path:
   ```bash
   ls .claude/CLAUDE.md
   ```
3. If the file is at the wrong path, move it:
   ```bash
   mv CLAUDE.md .claude/CLAUDE.md
   ```
