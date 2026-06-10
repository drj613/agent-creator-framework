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

