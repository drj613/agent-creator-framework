---
description: Run tests and report results
argument-hint: [path-or-pattern]
model: {{discovery.models.simple}}
---

# Test

## Variables
TARGET: $ARGUMENTS

## Steps

### 1. Determine Scope

If TARGET is empty, run the full test suite:
`{{discovery.test_runner.cmd}}`

If TARGET is provided, pass it as a path or filter:
`{{discovery.test_runner.cmd}} TARGET`

### 2. Run Tests

Execute the test command. Capture full output.

### 3. Report

Parse the output and present:

| Metric | Count |
|--------|-------|
| Total  | N     |
| Passed | N     |
| Failed | N     |
| Skipped| N     |
| Wall time | Ns  |

**If all pass:** Report the summary and stop.

**If any fail:** For each failure:
- Test name and file:line location
- Error message / assertion that failed
- Likely cause (read the test and the code it tests)
- Do NOT auto-fix. Present the information and stop.

### 4. DO NOT
- Do not modify any test files
- Do not modify any source files
- Do not re-run failed tests automatically
- Do not suggest running with different flags unless the user asks
