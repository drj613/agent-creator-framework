#!/usr/bin/env bash
# agents.sh — Generate builder.md and validator.md agent instruction files
# Sourced by generate.sh; do not run directly.

generate_agents() {
  local agent_dir
  agent_dir="$(jq_read '.agent_dir')"

  generate_builder_md "$agent_dir"
  generate_validator_md "$agent_dir"
  generate_questioner_md "$agent_dir"
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Return tool names for the body based on tool_name_style
# Usage: _tool_name <PascalCase_name> <lowercase_name>
_tool_name() {
  local pascal="$1"
  local lower="$2"
  local style
  style="$(jq_read '.platform_capabilities.tool_name_style')"
  if [[ "$style" == "lowercase" ]]; then
    echo "$lower"
  else
    echo "$pascal"
  fi
}

# Build the PostToolUse hooks list for the builder body
_build_hooks_body_list() {
  local linter_count type_checker_count
  linter_count="$(jq '.linters | length' <<< "$DISCOVERY_JSON")"
  type_checker_count="$(jq '.type_checkers | length' <<< "$DISCOVERY_JSON")"

  if (( linter_count + type_checker_count == 0 )); then
    echo ""
    return
  fi

  local list=""
  for (( i=0; i<linter_count; i++ )); do
    local name cmd
    name="$(jq_read ".linters[$i].name")"
    cmd="$(jq_read ".linters[$i].cmd")"
    list+="- **${name}** — \`${cmd}\`"$'\n'
  done
  for (( i=0; i<type_checker_count; i++ )); do
    local name cmd
    name="$(jq_read ".type_checkers[$i].name")"
    cmd="$(jq_read ".type_checkers[$i].cmd")"
    list+="- **${name}** — \`${cmd}\`"$'\n'
  done
  # Trim trailing newline
  printf '%s' "${list%$'\n'}"
}

# Return a slash-separated list of all checker names (linters then type checkers)
_all_checker_names() {
  local linter_count type_checker_count
  linter_count="$(jq '.linters | length' <<< "$DISCOVERY_JSON")"
  type_checker_count="$(jq '.type_checkers | length' <<< "$DISCOVERY_JSON")"

  local names=()
  for (( i=0; i<linter_count; i++ )); do
    names+=("$(jq_read ".linters[$i].name")")
  done
  for (( i=0; i<type_checker_count; i++ )); do
    names+=("$(jq_read ".type_checkers[$i].name")")
  done

  if (( ${#names[@]} == 0 )); then
    echo "Linter"
  else
    local result="${names[0]}"
    for (( i=1; i<${#names[@]}; i++ )); do
      result+=" / ${names[$i]}"
    done
    echo "$result"
  fi
}

# ---------------------------------------------------------------------------
# Builder frontmatter builders
# ---------------------------------------------------------------------------

_builder_frontmatter_claude_code() {
  local agent_dir="$1"
  local model lc_name hook_lines
  model="$(jq_read '.models.standard')"

  # Build validator hook lines (Write|Edit matcher)
  hook_lines=""
  local linter_count type_checker_count
  linter_count="$(jq '.linters | length' <<< "$DISCOVERY_JSON")"
  type_checker_count="$(jq '.type_checkers | length' <<< "$DISCOVERY_JSON")"

  for (( i=0; i<linter_count; i++ )); do
    lc_name="$(lowercase_name "$(jq_read ".linters[$i].name")")"
    hook_lines+="        - type: command"$'\n'
    hook_lines+="          command: bash \$PROJECT_DIR/${agent_dir}/hooks/validators/${lc_name}_validator.sh"$'\n'
  done
  for (( i=0; i<type_checker_count; i++ )); do
    lc_name="$(lowercase_name "$(jq_read ".type_checkers[$i].name")")"
    hook_lines+="        - type: command"$'\n'
    hook_lines+="          command: bash \$PROJECT_DIR/${agent_dir}/hooks/validators/${lc_name}_validator.sh"$'\n'
  done

  # Trim trailing newline from hook_lines
  hook_lines="${hook_lines%$'\n'}"

  # Gate audit-docs-hook registration on feature flag — the script won't exist otherwise
  local audit_docs bash_hook_yaml=""
  audit_docs="$(jq_read '.features.audit_docs')"
  if [[ "$audit_docs" == "true" ]]; then
    bash_hook_yaml="    - matcher: \"Bash\"
      hooks:
        - type: command
          command: bash \$PROJECT_DIR/${agent_dir}/hooks/audit-docs-hook.sh"
  fi

  local frontmatter="---
name: builder
description: Executes a single assigned task — writes code, runs tests, marks complete
model: ${model}
color: cyan
disallowedTools: Task
hooks:
  PostToolUse:
    - matcher: \"Write|Edit\"
      hooks:
${hook_lines}"

  if [[ -n "$bash_hook_yaml" ]]; then
    frontmatter+="
${bash_hook_yaml}"
  fi

  frontmatter+="
---"

  printf '%s\n' "$frontmatter"
}

_builder_frontmatter_opencode() {
  local model test_cmd
  model="$(jq_read '.models.standard')"
  test_cmd="$(jq_read '.test_runner.cmd')"

  local allow_lines
  allow_lines="      - \"${test_cmd}*\""

  local linter_count type_checker_count
  linter_count="$(jq '.linters | length' <<< "$DISCOVERY_JSON")"
  type_checker_count="$(jq '.type_checkers | length' <<< "$DISCOVERY_JSON")"

  if (( linter_count > 0 )); then
    local linter_cmd
    linter_cmd="$(jq_read '.linters[0].cmd')"
    # Extract just the base command (first word)
    local base_cmd="${linter_cmd%% *}"
    allow_lines+=$'\n'"      - \"${base_cmd}*\""
  fi
  if (( type_checker_count > 0 )); then
    local tc_cmd
    tc_cmd="$(jq_read '.type_checkers[0].cmd')"
    local base_cmd="${tc_cmd%% *}"
    allow_lines+=$'\n'"      - \"${base_cmd}*\""
  fi

  # $model and $test_cmd are pre-validated by validate.sh to exclude shell metacharacters.
  # The unquoted heredoc is intentional — these values are safe to interpolate.
  cat <<YAML
---
name: builder
description: Executes a single assigned task — writes code, runs tests, marks complete
model: ${model}
color: cyan
tools:
  write: true
  edit: true
  bash: true
  read: true
  grep: true
  glob: true
  task: false
  todowrite: true
  todoread: true
permission:
  bash:
    allow:
${allow_lines}
---
YAML
}

# ---------------------------------------------------------------------------
# Validator frontmatter builders
# ---------------------------------------------------------------------------

_validator_frontmatter_claude_code() {
  local model
  model="$(jq_read '.models.standard')"
  cat <<YAML
---
name: validator
description: Verifies a completed task — read-only, cannot modify files
model: ${model}
disallowedTools: Write, Edit
---
YAML
}

_validator_frontmatter_opencode() {
  local model
  model="$(jq_read '.models.standard')"
  cat <<YAML
---
name: validator
description: Verifies a completed task — read-only, cannot modify files
model: ${model}
tools:
  write: false
  edit: false
  bash: true
  read: true
  grep: true
  glob: true
  todowrite: true
  todoread: true
---
YAML
}

# ---------------------------------------------------------------------------
# Validator automated checks section
# ---------------------------------------------------------------------------

_validator_automated_checks() {
  local project_type test_cmd
  project_type="$(jq_read '.project_type')"
  test_cmd="$(jq_read '.test_runner.cmd')"

  local linter_count type_checker_count
  linter_count="$(jq '.linters | length' <<< "$DISCOVERY_JSON")"
  type_checker_count="$(jq '.type_checkers | length' <<< "$DISCOVERY_JSON")"

  echo "1. **Test suite:** \`${test_cmd}\` — if tests fail, report FAIL immediately."

  if [[ "$project_type" == "monorepo" ]]; then
    local ws_count
    ws_count="$(jq '.workspaces | length' <<< "$DISCOVERY_JSON")"
    echo "2. **Per-workspace checks** (for each workspace with changed files, run from the workspace directory):"
    for (( i=0; i<ws_count; i++ )); do
      local ws_name ws_path ws_lang
      ws_name="$(jq_read ".workspaces[$i].name")"
      ws_path="$(jq_read ".workspaces[$i].path")"
      ws_lang="$(jq_read ".workspaces[$i].language")"

      local tools_desc=""
      # Find matching linter
      for (( l=0; l<linter_count; l++ )); do
        local lint_lang lint_cmd lint_name
        lint_lang="$(jq_read ".linters[$l].language")"
        lint_cmd="$(jq_read ".linters[$l].cmd")"
        lint_name="$(jq_read ".linters[$l].name")"
        if [[ "$lint_lang" == "$ws_lang" ]]; then
          tools_desc+=" run \`${lint_cmd}\`"
        fi
      done
      # Find matching type checker
      for (( t=0; t<type_checker_count; t++ )); do
        local tc_lang tc_cmd tc_name
        tc_lang="$(jq_read ".type_checkers[$t].language")"
        tc_cmd="$(jq_read ".type_checkers[$t].cmd")"
        if [[ "$tc_lang" == "$ws_lang" ]]; then
          [[ -n "$tools_desc" ]] && tools_desc+=" and"
          tools_desc+=" \`${tc_cmd}\`"
        fi
      done

      if [[ -n "$tools_desc" ]]; then
        echo "   - **${ws_name}** (\`${ws_path}\`):${tools_desc} from \`${ws_path}\`"
      else
        echo "   - **${ws_name}** (\`${ws_path}\`): no matching linter/type checker for language \`${ws_lang}\`"
      fi
    done
    echo "3. **UI verification:** Use \`playwright-cli\` if the task involved user-visible changes (see \`/verify-browser\`)."
  else
    # Non-monorepo: match linters/type_checkers to backend/frontend by language
    local backend_lang frontend_lang backend_root frontend_root
    backend_lang="$(jq_read '.directories.backend_lang')"
    frontend_lang="$(jq_read '.directories.frontend_lang')"
    backend_root="$(jq_read '.directories.backend_root')"
    frontend_root="$(jq_read '.directories.frontend_root')"

    local step=2
    local backend_lint="" backend_tc="" frontend_lint="" frontend_tc=""

    for (( l=0; l<linter_count; l++ )); do
      local lang cmd
      lang="$(jq_read ".linters[$l].language")"
      cmd="$(jq_read ".linters[$l].cmd")"
      if [[ -n "$backend_lang" && "$lang" == "$backend_lang" ]]; then
        backend_lint="$cmd"
      elif [[ -n "$frontend_lang" && "$lang" == "$frontend_lang" ]]; then
        frontend_lint="$cmd"
      fi
    done
    for (( t=0; t<type_checker_count; t++ )); do
      local lang cmd
      lang="$(jq_read ".type_checkers[$t].language")"
      cmd="$(jq_read ".type_checkers[$t].cmd")"
      if [[ -n "$backend_lang" && "$lang" == "$backend_lang" ]]; then
        backend_tc="$cmd"
      elif [[ -n "$frontend_lang" && "$lang" == "$frontend_lang" ]]; then
        frontend_tc="$cmd"
      fi
    done

    if [[ -n "$backend_lint" || -n "$backend_tc" ]]; then
      local cmds=""
      [[ -n "$backend_lint" ]] && cmds+="\`${backend_lint}\`"
      if [[ -n "$backend_tc" ]]; then
        [[ -n "$cmds" ]] && cmds+=", "
        cmds+="\`${backend_tc}\`"
      fi
      local dir_hint=""
      [[ -n "$backend_root" ]] && dir_hint=" (from \`${backend_root}/\`)"
      echo "${step}. **Backend lint + type check** (if backend files changed)${dir_hint}: ${cmds}"
      (( step++ ))
    fi

    if [[ -n "$frontend_lint" || -n "$frontend_tc" ]]; then
      local cmds=""
      [[ -n "$frontend_lint" ]] && cmds+="\`${frontend_lint}\`"
      if [[ -n "$frontend_tc" ]]; then
        [[ -n "$cmds" ]] && cmds+=", "
        cmds+="\`${frontend_tc}\`"
      fi
      local dir_hint=""
      [[ -n "$frontend_root" ]] && dir_hint=" (from \`${frontend_root}/\`)"
      echo "${step}. **Frontend lint + type check** (if frontend files changed)${dir_hint}: ${cmds}"
      (( step++ ))
    fi

    # If no backend/frontend split found but tools exist, emit them generically
    if [[ -z "$backend_lint" && -z "$backend_tc" && -z "$frontend_lint" && -z "$frontend_tc" ]]; then
      if (( linter_count + type_checker_count > 0 )); then
        local cmds=""
        for (( l=0; l<linter_count; l++ )); do
          local cmd
          cmd="$(jq_read ".linters[$l].cmd")"
          [[ -n "$cmds" ]] && cmds+=", "
          cmds+="\`${cmd}\`"
        done
        for (( t=0; t<type_checker_count; t++ )); do
          local cmd
          cmd="$(jq_read ".type_checkers[$t].cmd")"
          [[ -n "$cmds" ]] && cmds+=", "
          cmds+="\`${cmd}\`"
        done
        echo "${step}. **Lint + type check** (if source files changed): ${cmds}"
        (( step++ ))
      fi
    fi

    echo "${step}. **UI verification:** Use \`playwright-cli\` if the task involved user-visible changes (see \`/verify-browser\`)."
  fi
}

# Validation report section varies by project type
_validator_report_checks_section() {
  local project_type
  project_type="$(jq_read '.project_type')"

  local linter_count type_checker_count
  linter_count="$(jq '.linters | length' <<< "$DISCOVERY_JSON")"
  type_checker_count="$(jq '.type_checkers | length' <<< "$DISCOVERY_JSON")"

  if [[ "$project_type" == "monorepo" ]]; then
    local ws_count
    ws_count="$(jq '.workspaces | length' <<< "$DISCOVERY_JSON")"
    echo "Test Suite: [X/X tests passed]"
    for (( i=0; i<ws_count; i++ )); do
      local ws_name
      ws_name="$(jq_read ".workspaces[$i].name")"
      echo "${ws_name}: [PASS/FAIL]"
    done
  else
    echo "Test Suite: [X/X tests passed]"

    local backend_lang frontend_lang
    backend_lang="$(jq_read '.directories.backend_lang')"
    frontend_lang="$(jq_read '.directories.frontend_lang')"

    local has_backend=false has_frontend=false
    for (( l=0; l<linter_count; l++ )); do
      local lang
      lang="$(jq_read ".linters[$l].language")"
      [[ -n "$backend_lang" && "$lang" == "$backend_lang" ]] && has_backend=true
      [[ -n "$frontend_lang" && "$lang" == "$frontend_lang" ]] && has_frontend=true
    done
    for (( t=0; t<type_checker_count; t++ )); do
      local lang
      lang="$(jq_read ".type_checkers[$t].language")"
      [[ -n "$backend_lang" && "$lang" == "$backend_lang" ]] && has_backend=true
      [[ -n "$frontend_lang" && "$lang" == "$frontend_lang" ]] && has_frontend=true
    done

    [[ "$has_backend" == "true" ]] && echo "Backend: [PASS/FAIL]"
    [[ "$has_frontend" == "true" ]] && echo "Frontend: [PASS/FAIL]"
  fi

  echo "UI: [specific checks if applicable]"
}

# ---------------------------------------------------------------------------
# generate_builder_md
# ---------------------------------------------------------------------------

generate_builder_md() {
  local agent_dir="$1"
  local hook_mechanism
  hook_mechanism="$(jq_read '.platform_capabilities.hook_mechanism')"

  local frontmatter
  if [[ "$hook_mechanism" == "typescript_plugin" ]]; then
    frontmatter="$(_builder_frontmatter_opencode)"
  else
    frontmatter="$(_builder_frontmatter_claude_code "$agent_dir")"
  fi

  # Tool names for the body
  local t_taskget t_taskupdate t_taskcreate t_write t_edit t_bash t_todoread t_todowrite
  t_taskget="$(_tool_name "TaskGet" "todoread")"
  t_taskupdate="$(_tool_name "TaskUpdate" "todowrite")"
  t_taskcreate="$(_tool_name "TaskCreate" "todowrite")"
  t_write="$(_tool_name "Write" "write")"
  t_edit="$(_tool_name "Edit" "edit")"
  t_bash="$(_tool_name "Bash" "bash")"

  local test_cmd
  test_cmd="$(jq_read '.test_runner.cmd')"

  # PostToolUse hooks list
  local linter_count type_checker_count
  linter_count="$(jq '.linters | length' <<< "$DISCOVERY_JSON")"
  type_checker_count="$(jq '.type_checkers | length' <<< "$DISCOVERY_JSON")"

  local hooks_section=""
  if (( linter_count + type_checker_count > 0 )); then
    hooks_section="$(_build_hooks_body_list)"
  fi

  local all_checkers
  all_checkers="$(_all_checker_names)"

  # Build the hooks body section (conditionally included)
  local hooks_body_section=""
  if (( linter_count + type_checker_count > 0 )); then
    hooks_body_section="## PostToolUse Hooks (Automatic)

Every ${t_write}/${t_edit} triggers these validators automatically:
${hooks_section}

If a hook returns \`{\"decision\": \"block\", \"reason\": \"...\"}\`, you MUST fix the reported issue before continuing.
If a hook returns \`{\"reason\": \"...\"}\` without a \`decision\` field, read the message for context but continue without retrying — this is an advisory notification, not a blocker."
  fi

  local body
  body="# Builder

You are a focused coding agent. Your job is to execute ONE assigned task — write code, run tests, and mark it complete. You do not coordinate, plan, or spawn other agents.

## Your Constraints

- You can write and edit files (${t_write} and ${t_edit} tools)
- You CANNOT dispatch other agents or expand scope beyond the assigned task
- Every file you write is automatically validated by PostToolUse hooks (see below)
- You MUST run the full test suite before marking any task complete

## Your Workflow

### Step 0: Test baseline

Before implementing, run the test suite once: \`${test_cmd}\`

If tests already fail, report to the orchestrator via TaskUpdate with status \`blocked — pre-existing test failures\` and stop. Do not implement until the orchestrator resolves the baseline.

1. **Read the task:** If a task ID was provided, retrieve it via \`${t_taskget}\` to get the full description and acceptance criteria.
2. **Read the plan:** If the task references a plan file, read the plan's acceptance criteria and your task's specific instructions. The plan is your source of truth — not just the ${t_taskcreate} description.
3. **Implement:** Write code to fulfill the task. When a PostToolUse hook blocks you with a lint or type error, fix the issue immediately before continuing.
4. **Test:** Run the full test suite: \`${test_cmd}\`. All tests must pass. Fix failures in code you wrote. If a test failure is in code you did not touch, report it to the orchestrator via ${t_taskupdate} rather than modifying pre-existing code.
5. **Report:** Mark the task complete via \`${t_taskupdate}\` with a summary following the format below.

## Information Priority

When task descriptions and plan instructions conflict, follow this priority:
1. Plan's \`## Acceptance Criteria\` (canonical requirements)
2. Plan's \`## Step by Step Tasks / <your task>\` section (detailed instructions)
3. \`${t_taskcreate}\` description (summary — may be abbreviated)

${hooks_body_section}

## Task Tool Reference

See \`orchestration-reference.md\` for ${t_taskget}, ${t_taskupdate}, and other tool documentation.

## Report Format

When marking a task complete, include this summary:

\`\`\`
## Task Complete
Task: [name]
What was done: [bullets]
Files changed: [file — what changed]
Test Results: [X/X passed]
Hook Validation: ${all_checkers} [pass/fail]
\`\`\`"

  local content
  content="$(printf '%s\n%s' "$frontmatter" "$body")"

  write_file "${PROJECT_DIR}/${agent_dir}/agents/team/builder.md" "$content"
  info "Generated: ${agent_dir}/agents/team/builder.md"
}

# ---------------------------------------------------------------------------
# generate_validator_md
# ---------------------------------------------------------------------------

generate_validator_md() {
  local agent_dir="$1"
  local hook_mechanism
  hook_mechanism="$(jq_read '.platform_capabilities.hook_mechanism')"

  local frontmatter
  if [[ "$hook_mechanism" == "typescript_plugin" ]]; then
    frontmatter="$(_validator_frontmatter_opencode)"
  else
    frontmatter="$(_validator_frontmatter_claude_code)"
  fi

  local test_cmd
  test_cmd="$(jq_read '.test_runner.cmd')"

  local t_bash t_taskget t_todoread
  t_bash="$(_tool_name "Bash" "bash")"
  t_taskget="$(_tool_name "TaskGet" "todoread")"

  local automated_checks
  automated_checks="$(_validator_automated_checks)"

  local report_checks
  report_checks="$(_validator_report_checks_section)"

  # Platform-appropriate enforcement text (just the tool restriction expression, no wrapping)
  local enforcement_tool_ref
  if [[ "$hook_mechanism" == "typescript_plugin" ]]; then
    enforcement_tool_ref="\`tools: { write: false, edit: false }\`"
  else
    enforcement_tool_ref="\`disallowedTools: Write, Edit\`"
  fi

  local body
  body="# Validator

You are a read-only verification agent. Your job is to verify ONE completed task by checking that acceptance criteria are met and all automated checks pass. You CANNOT modify any files — this is enforced at the tool level (${enforcement_tool_ref}), not just instructed.
Never use ${t_bash} to write, create, or modify files. Use ${t_bash} only for read-only operations: running tests, linting, type checking, and reading file contents.

## Your Workflow

### Step 1: Intent Verification (Acceptance Criteria Check)

Before running any automated checks, read the plan's \`## Acceptance Criteria\` section and verify each criterion individually.

For each acceptance criterion, assess:
- **MET** — with specific evidence (file path, test name, observable behavior)
- **NOT MET** — with explanation of what is missing or incorrect
- **CANNOT VERIFY** — with reason (e.g., requires manual testing, external service, etc.)

**Decision rule:**
- If ANY criterion is NOT MET → overall status is **FAIL**, regardless of whether tests pass.
- If all criteria are MET → overall status is **PASS**. Proceed to Step 2.
- If all criteria are MET or CANNOT VERIFY (none NOT MET) → overall status is **PASS (with caveats)**. Proceed to Step 2, but include caveats in the report.
- If more than half the criteria are CANNOT VERIFY → add a warning: \"Most acceptance criteria could not be verified automatically. Recommend manual validation before merge.\"
- CANNOT VERIFY items must be listed in the report for human follow-up.

### Step 2: Automated Checks

Run **all** checks below and collect results for each. Do not stop early — complete every check even if earlier ones fail. Report the complete set of failures in Step 3.

${automated_checks}

### Step 3: Report

Use this format for every validation report:

\`\`\`
## Validation Report
Task: [name]
Status: PASS | PASS (with caveats) | FAIL

### Acceptance Criteria
- [criterion 1]: MET — [evidence]
- [criterion 2]: NOT MET — [explanation]
- [criterion 3]: CANNOT VERIFY — [reason]

### Automated Checks
${report_checks}

Issues Found: [list or \"none\"]
\`\`\`

## Task Tool Reference

See \`orchestration-reference.md\` for ${t_taskget} and other tool documentation."

  local content
  content="$(printf '%s\n%s' "$frontmatter" "$body")"

  write_file "${PROJECT_DIR}/${agent_dir}/agents/team/validator.md" "$content"
  info "Generated: ${agent_dir}/agents/team/validator.md"
}

# ---------------------------------------------------------------------------
# generate_questioner_md
# ---------------------------------------------------------------------------

_questioner_frontmatter_claude_code() {
  local model
  model="$(jq_read '.models.simple')"
  cat <<YAML
---
name: questioner
description: Asks naive questions about code changes — fresh eyes, no domain expertise
model: ${model}
disallowedTools: Write, Edit, Bash, Task
---
YAML
}

_questioner_frontmatter_opencode() {
  local model
  model="$(jq_read '.models.simple')"
  cat <<YAML
---
name: questioner
description: Asks naive questions about code changes — fresh eyes, no domain expertise
model: ${model}
tools:
  write: false
  edit: false
  bash: false
  task: false
  read: true
  grep: true
  glob: true
---
YAML
}

generate_questioner_md() {
  local agent_dir="$1"
  local hook_mechanism
  hook_mechanism="$(jq_read '.platform_capabilities.hook_mechanism')"

  local frontmatter
  if [[ "$hook_mechanism" == "typescript_plugin" ]]; then
    frontmatter="$(_questioner_frontmatter_opencode)"
  else
    frontmatter="$(_questioner_frontmatter_claude_code)"
  fi

  # shellcheck disable=SC2016  # single-quoted heredoc — $ intentionally unexpanded
  local body
  body="$(cat <<'GENEOF'
# Questioner

You are reviewing a code change with fresh eyes. You have never worked in this codebase
and have no expertise in its specific technologies. Other reviewers handle security,
architecture, and test quality. Your role is to ask the questions a smart but unfamiliar
developer would ask when reading these changes for the first time.

Surface the assumptions, undocumented choices, and edge cases that experts miss because
they are too close to the code.

## What to Look For

- **Edge cases** — "What happens if X is null, empty, or an unexpected type?"
- **Unexplained choices** — "Why this approach rather than the simpler alternative?"
- **Scope** — "This appears to do three things — is that intentional?"
- **User-facing impact** — "What does this error message communicate to the user?"
- **Backward compatibility** — "Does this affect existing data, API consumers, or callers?"
- **Test gaps** — "What test covers this edge case?"
- **Implicit dependencies** — "Where else is this used — are those call sites safe with this change?"
- **Clarity** — "Is the intent of this code clear to someone who didn't write it?"

## Rules

- Ask only questions. Do not recommend solutions, evaluate quality, approve, or block.
- Each question must be one sentence.
- Maximum 10 questions.
- Reference the code only enough to make each question specific.

## Report Format

```
## Questions

1. [question]
2. [question]
...
```
GENEOF
)"

  local content
  content="$(printf '%s\n%s' "$frontmatter" "$body")"

  write_file "${PROJECT_DIR}/${agent_dir}/agents/team/questioner.md" "$content"
  info "Generated: ${agent_dir}/agents/team/questioner.md"
}
