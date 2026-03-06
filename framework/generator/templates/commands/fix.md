---
description: Apply Must Fix findings from a review report
argument-hint: [review output or path to review file]
---

# Fix

## Variables
REVIEW_INPUT: $ARGUMENTS  # Paste review output, or provide a file path

## Workflow

### 1. Load Review Findings

If REVIEW_INPUT is a file path, read it. Otherwise treat REVIEW_INPUT as the review text directly.

If no input is provided, ask the user to paste the `/review` output or provide a path to it.

If the input contains no `### Must Fix` section, tell the user and stop — nothing to fix.

### 2. Filter to Must Fix Items

Extract only the `### Must Fix (blocks merge)` section. Ignore `Should Fix` and `Consider` items — those are out of scope for this command.

For each Must Fix finding, parse:
- **File and line** (if available): e.g. `src/auth/middleware.ts:42`
- **Description**: brief summary of the issue
- **Source tag**: `[security]`, `[architecture]`, or `[tests]`

Build a fix spec list:
```
Fix Spec:
1. [security] src/auth/middleware.ts:42 — Missing authorization check on admin route
2. [tests] src/services/TaskService.ts — No test for error path when task not found
...
```

### 3. Confirm Scope with User

Print the fix spec and ask the user to confirm before proceeding:

```
Found N Must Fix items in these files:
  - [list of files]

Scope: builder will be restricted to these files only.

Proceed? (yes to continue)
```

Wait for confirmation.

### 4. Dispatch Builder

Deploy the builder agent with:
- The fix spec as the task description
- An explicit scope restriction: "Only modify files listed in the fix spec above. Do not touch any other files."
- Instruction to run the full test suite and all linters after each fix

### 5. Report Results

After the builder completes, report:

```
## Fix Results

Applied fixes:
- [finding 1]: [what was changed]
- [finding 2]: [what was changed]

Files changed: [list]
Test Results: [X/X passed]

Remaining: [any findings the builder could not address, with reason]

Next step: Re-run /review to verify fixes and check Should Fix items.
```
