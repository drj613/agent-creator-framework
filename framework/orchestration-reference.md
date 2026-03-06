# Orchestration Reference

Shared reference for task management tools used by `/plan_w_team` (during planning) and `/build` (during execution). Both commands use these tools to create, manage, and dispatch work to agent team members.

## Task Management Tools

**TaskCreate** — Create a task in the shared list:
```
TaskCreate({
  subject: "Implement user authentication",
  description: "...",
  activeForm: "Implementing authentication"  // shown in UI while in_progress
})
// Returns: taskId
```

**TaskUpdate** — Update status, owner, or dependencies:
```
TaskUpdate({ taskId: "1", status: "in_progress", owner: "builder-api" })
TaskUpdate({ taskId: "2", addBlockedBy: ["1"] })  // task 2 waits for task 1
```

**TaskList / TaskGet** — Monitor progress:
```
TaskList({})   // all tasks and status
TaskGet({ taskId: "1" })  // full details including description
```

**Task** — Deploy an agent:
```
Task({
  description: "Implement auth endpoints",
  prompt: "...",
  subagent_type: "builder",   // or any agent in TEAM_MEMBERS
  model: "opus",              // sonnet for simpler work
  run_in_background: true     // true to run in parallel with other agents
})
// Returns: agentId — store this to resume the agent later
```

**TaskOutput** — Retrieve output from a running or completed agent:
```
TaskOutput({ task_id: "agentId", block: true, timeout: 30000 })
// Returns: agent output text and completion status
// block: true waits for completion; false returns current status
```

**Resume pattern** — continue an agent with preserved context:
```
Task({ ..., resume: "agentId" })
```

## Orchestration Workflow

1. Create all tasks with `TaskCreate`
2. Set dependencies with `TaskUpdate` + `addBlockedBy`
3. Assign owners with `TaskUpdate` + `owner`
4. Deploy agents with `Task`
5. Monitor with `TaskList` and `TaskOutput`
6. Resume agents with `Task` + `resume` for follow-up work
7. Mark complete with `TaskUpdate` + `status: "completed"`

---

## OpenCode Tool Mapping

When `{{discovery.platform_capabilities.task_tools}} == "unified"` (i.e. OpenCode), the task management tools have different names but equivalent functionality:

| Claude Code | OpenCode | Notes |
|-------------|----------|-------|
| `TaskCreate({ subject, description, activeForm })` | `todowrite({ todos: [{ content, status }] })` | Creates task items. `content` combines subject + description. |
| `TaskUpdate({ taskId, status })` | `todowrite({ todos: [{ id, status }] })` | Updates existing task by ID. |
| `TaskList({})` | `todoread({})` | Returns all tasks with statuses. |
| `TaskGet({ taskId })` | `todoread({ id })` | Returns details for a specific task. |
| `Task({ prompt, subagent_type, ... })` | `task({ prompt, agent, ... })` | Dispatches a subagent. `subagent_type` → `agent`. |
| `Task({ resume: agentId })` | `task({ resume: agentId })` | Resume pattern is the same. |
| `TaskOutput({ task_id })` | *(returned by task)* | Output retrieval integrated into task tool response. |

### Key Differences

- **Task creation:** OpenCode's `todowrite` is a batch operation — pass an array of todos to create/update multiple at once.
- **Status values:** Both use `pending`, `in_progress`, `completed`.
- **Dependencies:** OpenCode uses `todowrite` with dependency fields rather than `addBlockedBy`.
- **Agent dispatch:** `task` replaces `Task` — same `prompt`, `run_in_background`, `resume` parameters. Use `agent` instead of `subagent_type`.

### Orchestration Workflow (OpenCode)

1. Create all tasks with `todowrite`
2. Set dependencies within the `todowrite` call
3. Deploy agents with `task`
4. Monitor with `todoread`
5. Resume agents with `task` + `resume`
6. Mark complete with `todowrite` + updated status
