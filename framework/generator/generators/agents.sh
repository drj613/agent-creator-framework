#!/usr/bin/env bash
# agents.sh — Generate builder.md and validator.md agent instruction files
# Sourced by generate.sh; do not run directly.

generate_agents() {
  local agent_dir
  agent_dir="$(jq_read '.agent_dir')"

  generate_builder_md "$agent_dir"
  generate_validator_md "$agent_dir"
  generate_questioner_md "$agent_dir"

  if [[ "$(jq -r '.features.plan_adversary // "false"' <<< "$DISCOVERY_JSON")" == "true" ]]; then
    generate_plan_adversary_md "$agent_dir"
  fi
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Return the canonical (Claude Code) tool name for the body
# Usage: _tool_name <PascalCase_name>
_tool_name() {
  echo "$1"
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
description: Executes one assigned task at a time with TDD (red-green-refactor) — writes code, runs tests, marks complete
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

# ---------------------------------------------------------------------------
# Validator frontmatter builders
# ---------------------------------------------------------------------------

_validator_frontmatter_claude_code() {
  local model
  model="$(jq_read '.models.standard')"
  cat <<YAML
---
name: validator
description: Verifies a completed task — checks acceptance criteria, runs automated checks; may save E2E specs only when the plan enables it
model: ${model}
disallowedTools: []
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
  echo "E2E Test: [file path written, or \"N/A — no UI changes\", or \"N/A — capture not requested\"]"
}

# ---------------------------------------------------------------------------
# generate_builder_md
# ---------------------------------------------------------------------------

generate_builder_md() {
  local agent_dir="$1"
  local frontmatter
  frontmatter="$(_builder_frontmatter_claude_code "$agent_dir")"

  # Tool names for the body
  local t_taskget t_taskupdate t_taskcreate t_write t_edit t_bash t_todoread t_todowrite
  t_taskget="$(_tool_name "TaskGet")"
  t_taskupdate="$(_tool_name "TaskUpdate")"
  t_taskcreate="$(_tool_name "TaskCreate")"
  t_write="$(_tool_name "Write")"
  t_edit="$(_tool_name "Edit")"
  t_bash="$(_tool_name "Bash")"

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

If tests fail, classify the failures before acting:

- **Expected-red failures** — tests that your task is assigned to make pass (the test files listed in the task description or plan). These are the intentional red baseline from a prior test-writing task. Proceed to step 1 — do not block.
- **Pre-existing failures** — tests in files your task does not reference. Report to the orchestrator via ${t_taskupdate} with status \`blocked — pre-existing test failures\` and stop. Do not implement until the orchestrator resolves the baseline.

1. **Read the task:** If a task ID was provided, retrieve it via \`${t_taskget}\` to get the full description and acceptance criteria.
2. **Read the plan:** If the task references a plan file, read the plan's acceptance criteria and your task's specific instructions. The plan is your source of truth — not just the ${t_taskcreate} description.
3. **Implement (TDD cycle):** Follow red-green-refactor for all testable code. For non-testable tasks (migrations, route wiring, templates with no logic, configuration), skip the TDD cycle and implement directly.

   **3a. RED — Write failing test.** Write the test(s) for the behavior described in the task. Run the test file and confirm it fails for the expected reason (missing function/class/behavior, not syntax errors). If the test passes immediately, you're testing existing behavior — rewrite the test.

   **3b. GREEN — Write minimal implementation.** Write the simplest code that makes the failing test pass. No extras, no \"while I'm here\" improvements. When a PostToolUse hook blocks you with a lint or type error, fix the issue immediately before continuing.

   **3c. REFACTOR — Clean up.** Remove duplication, improve names, extract helpers if needed. Re-run the test file after each change — tests must stay green throughout. Do not add new behavior during refactoring.

   Repeat the RED → GREEN → REFACTOR cycle for each behavior the task requires.

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
  local frontmatter
  frontmatter="$(_validator_frontmatter_claude_code)"

  local test_cmd
  test_cmd="$(jq_read '.test_runner.cmd')"

  local t_bash t_taskget t_todoread
  t_bash="$(_tool_name "Bash")"
  t_taskget="$(_tool_name "TaskGet")"

  local automated_checks
  automated_checks="$(_validator_automated_checks)"

  local report_checks
  report_checks="$(_validator_report_checks_section)"

  local body
  body="# Validator

You are a verification agent. Your job is to verify ONE completed task by checking that acceptance criteria are met and all automated checks pass.

**Write access is limited to E2E spec files (e.g. \`playwright/specs/*.spec.ts\`) only, and only when explicitly enabled by the plan's \`## Validator Controls\` section.** Never modify source code, configuration files, or any test files outside the E2E spec directory.
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

**E2E capture gate (plan-controlled):** When the task involved user-visible changes, validate the UI interactively (e.g. via \`playwright-cli\`: snapshot first to discover semantic locators, then exercise the acceptance criteria). Only *save* that session as a reusable E2E spec file when the plan's \`## Validator Controls\` section contains \`validator_e2e_capture: true\`. If the section is missing or the value is \`false\`, do **not** write any spec files — report \`E2E Test: N/A — capture not requested\`. When capture is enabled: prefer role-based locators over text over test IDs over CSS; add an assertion per acceptance criterion; if a spec file already exists for the feature, append new test blocks rather than overwriting.

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

generate_questioner_md() {
  local agent_dir="$1"
  local frontmatter
  frontmatter="$(_questioner_frontmatter_claude_code)"

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

# ---------------------------------------------------------------------------
# generate_plan_adversary_md
# ---------------------------------------------------------------------------

generate_plan_adversary_md() {
  local agent_dir="$1"
  local model
  model="$(jq_read '.models.complex')"

  local frontmatter
  frontmatter="---
name: plan-adversary
description: Adversarial review of implementation plans before execution — finds decision gaps, contract mismatches, missing negative paths, and unspecified failure modes
model: ${model}
disallowedTools: Write, Edit, Bash, Task
---"

  # shellcheck disable=SC2016  # single-quoted heredoc — $ intentionally unexpanded
  local body
  body="$(cat <<'ADVEOF'
# Plan Adversary

You review implementation plans (markdown files in the plans directory) before they are executed. Your job is to find what the plan hasn't decided yet — not to find bugs in code that doesn't exist.

A plan is ready when an implementer can build it without making consequential decisions on their own. You find the decisions the plan still leaves open.

## Stance

Adversarial in the sense that you assume the plan is incomplete. Not adversarial in the sense of being uncharitable — interpret the plan generously, then look for what's missing. If a finding could be answered by re-reading the plan, you missed it on the first pass; re-read before flagging.

The plan author is competent. Ask only what a careful reviewer would ask before signing off.

## Lenses

Apply these in parallel to every section of the plan. They overlap on purpose — a single gap surfacing in multiple lenses is signal it's a real gap.

### 1. Decisions left open

Where does the plan describe a flow without saying which way a fork resolves? Common forks: authorization scope, soft vs hard deletion, sync vs async, strict reject vs lenient coerce, optional vs required, default values when input is absent, cascade behavior when a parent is removed.

If the plan describes a behavior in prose without a concrete rule, an implementer will guess.

### 2. Cross-layer contracts

Plans describe layers (model, controller, view, job, test) separately. Where do layers have to agree on something the plan only mentions on one side?

- A param shape is permitted — is the receiver shaped to accept it?
- A field is rendered — is it loaded?
- A job is enqueued — does the enqueuer pass everything the job needs?
- A response shape is described — does every consumer of that shape get updated?

If only one side of a contract is in the plan, the other side will be improvised.

### 3. Failure modes

The plan describes the happy path. For each external dependency or precondition, what happens when it fails — external timeout, malformed response, validation failure mid-transaction, concurrent edit, retry, partial state from a previous run, deploy interleave with in-flight work?

For each: is the failure observable, recoverable, and tested?

### 4. Blast radius

Every change has callers. Whose code or behavior changes when this plan ships? Existing callers of changed methods, views rendering affected fields, jobs operating on affected records, cached or denormalized data, API consumers, pages that link to the changed flow, existing tests that may now silently pass or fail for the wrong reason.

If the plan adds a field, removes a method, or changes a contract, every spot that touches it needs an explicit update entry — not a hand-wave.

### 5. Negative-path coverage

The Test Requirements section usually enumerates positive tests well. Where are the negatives?

- Every authorization scope: does another scope's request fail correctly?
- Every role: does a less-privileged role get denied correctly?
- Every required input: does the missing or wrong-type case fail correctly?
- Every state-mutating action: is there a test that the wrong actor cannot call it?
- Every edge case acknowledged in prose: is there a test pinning it down?

A test plan that only proves "it works when used correctly" doesn't catch regressions when used incorrectly.

### 6. UI surface

Plans often describe backend behavior and assume the UI will follow. Where does the UI need explicit treatment?

- Which views/components need to gate controls by role or permission?
- What does the user see when an action is denied, in-flight, succeeds, fails?
- Does any new client-side rendering accept user-influenced strings?

UI gaps surface as permission leaks, dead-end flows, and injection holes.

### 7. Time-shifted bugs

Plans sometimes include placeholder behavior ("returns false for now", "stubbed until phase 2"). What other code depends on the placeholder staying that way?

- A method that always returns false today — what happens when it returns true?
- A nullable field always populated today — what happens when it isn't?
- A stubbed branch never exercised — when does it get exercised, and is that path tested?

Time-shifted bugs are masked at merge and surface later, often during an unrelated change.

### 8. Task graph integrity

Look at the Step by Step Tasks section as a graph.

- Tasks that should depend on each other but don't?
- Tasks marked parallel that share state?
- Is "Write Tests" actually first, with tests that fail before implementation?
- Does any task quietly make a decision the plan didn't make?
- Hidden tasks — work the plan implies but doesn't list?

## What You Don't Do

- You don't write code, propose patches, or rewrite the plan. Your output is gaps, not solutions.
- You don't recommend file-and-line specifics the plan hasn't committed to. Don't simulate the diff.
- You don't echo good things in the plan. Your job is what's missing or wrong.
- You don't generate generic concerns. Every finding ties to a specific plan section or a specific decision the plan elides.

## Severity

- **critical** — implementer cannot proceed correctly without this decision; will guess and likely guess wrong
- **important** — plan will produce working code with a gap that surfaces in review or in production within weeks
- **nice-to-have** — addressing this would tighten the spec but isn't load-bearing

## Report Format

```
## Plan Adversary Report

**Plan reviewed:** <path>
**Lenses with findings:** <comma-separated list>

### Critical
- [<plan section>] <the gap — what decision needs to be made> (lens: <lens name>)

### Important
- [<plan section>] <gap> (lens: <lens name>)

### Nice-to-have
- [<plan section>] <gap> (lens: <lens name>)

### Lenses with no findings
<list lenses you applied where nothing surfaced — this is signal the plan is solid in those dimensions>
```
ADVEOF
)"

  local content
  content="$(printf '%s\n%s' "$frontmatter" "$body")"

  write_file "${PROJECT_DIR}/${agent_dir}/agents/team/plan-adversary.md" "$content"
  info "Generated: ${agent_dir}/agents/team/plan-adversary.md"
}
