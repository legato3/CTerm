# Roadmap Phase 2: Closing the Loop

All 10 phases of the original roadmap are complete. Claude can now control CTerm, see all agents, auto-approve tools, queue tasks, track file changes, and visualize the IPC mesh.

The remaining gap: **Claude edits code, but has no automatic awareness of whether it worked.** The user still acts as a relay — copying stderr, pasting test failures, re-explaining project context at the start of every session.

This phase closes those loops.

---

## Design Principles (unchanged)

1. **Claude controls CTerm, not the other way around.**
2. **The MCP surface is the primary API.** New capabilities are exposed as MCP tools first; UI second.
3. **Minimal friction.** Fewer clicks to get an agent running and productive.
4. **Visible state.** The user can always see what every Claude instance is doing.

---

## Tier 1 — Close the Feedback Loop

### Phase 11: Shell Error Routing

**The problem**: When a command fails, Claude doesn't know. The user must copy/paste stderr manually. During auto-accept runs, this breaks the autonomous loop entirely.

**The solution**: Monitor terminal output for failure signals. When a command fails, automatically route the error back to the active Claude pane.

**How it works**:
- `ShellErrorMonitor` watches each pane's surface output (similar to `AutoAcceptMonitor`)
- Detects failure patterns: shell prompts preceded by non-empty stderr, `error:` / `Error:` prefixes, `Command failed`, `FAILED`, `❌`, `exited with code [1-255]`, build failure markers
- In **auto-accept panes**: immediately routes error to Claude with a structured prompt:
  ```
  The last command failed:

  [stderr output]

  Please fix the error and continue.
  ```
- In **manual panes**: shows a subtle `⚠ Route to Claude` button in the tab chip; one click to send
- **Cooldown**: 10s per pane to avoid duplicate routing on multi-line error output
- **Configurable**: toggle per-pane or globally; pattern blocklist for noisy false positives

**MCP tools added**: `get_last_error(pane_id?)` — returns the most recent captured error output from any pane.

**UI**: Amber `⚠` badge on tab chip when an unrouted error is waiting. Clears when routed or dismissed.

---

### Phase 12: Agent Memory / Knowledge Base

**The problem**: Every Claude session starts from zero. Facts about the project — architecture decisions, conventions, work-in-progress context, "don't touch X" warnings — are lost between sessions.

**The solution**: A persistent, project-scoped knowledge base that Claude agents can read and write via MCP tools.

**Storage**: `~/.cterm/memories/{project-hash}.json` where project-hash is derived from the git remote URL or cwd path.

**MCP tools**:
| Tool | Description |
|---|---|
| `remember(key, value, ttl?)` | Store a fact. Optional TTL in days (default: forever) |
| `recall(query)` | Full-text search across all stored memories |
| `forget(key)` | Delete a specific memory by key |
| `list_memories()` | Return all memories with keys, values, and ages |

**Example usage by Claude**:
```
remember("auth-system", "Uses JWT with 7-day refresh tokens. Don't use session cookies.")
remember("avoid", "PaymentController — Sarah is rewriting it in the 'payment-v2' branch")
remember("test-command", "Use `make test-fast` not `make test` — the slow suite takes 20min")
recall("auth")  // → returns the auth-system entry
```

**UI**: New sidebar tab (brain icon) with:
- Searchable list of all memories
- Age indicator ("3 days ago")
- Manual edit / delete
- "Add memory" button (for user-written entries)
- Memory count badge on sidebar icon

---

### Phase 13: Test Runner Watch Mode

**The problem**: Claude edits code, tests run, tests fail — but Claude doesn't see the results. The user acts as the messenger between the test runner and Claude.

**The solution**: A sidebar panel that watches a running test process, shows live results, and routes failures to Claude automatically.

**How it works**:
- User specifies a watch command in the panel (e.g. `xcodebuild test -scheme CTermTests`, `npm test -- --watch`, `cargo watch -x test`)
- CTerm spawns this as a managed child process (not in a terminal pane)
- Output is parsed for pass/fail patterns per test framework (XCTest, Jest, pytest, cargo test, Go test)
- Results shown as a live checklist: ✅ `SplitTreeTests` / ❌ `WindowSessionTests`
- On failure: "Route to Claude" button per test, or "Route all failures" — injects structured failure context into the target pane
- On all-green: optionally auto-advances the task queue

**MCP tools**:
| Tool | Description |
|---|---|
| `get_test_results()` | Returns current pass/fail counts and list of failing tests with output |
| `run_tests(command?)` | Trigger a test run (uses saved command if not specified) |

**UI**: Sidebar tab (test tube icon) with:
- Watch command input + start/stop toggle
- Live pass/fail bar (green/red proportional strip)
- Collapsible test list with failure output inline
- "Route failures to Claude" button (disabled when all pass)
- Target pane picker

---

### Phase 14: Ambient Context Injection

**The problem**: Every new Claude session requires the user to re-explain the project. "We're working in Swift 6, using XcodeGen, don't use force unwraps..." — this is noise that should be automatic.

**The solution**: When a new peer registers via IPC, CTerm gathers live project context and makes it available via an MCP tool. Claude agents call this at session start as their first tool use.

**MCP tool**: `get_project_context()` returns:
```json
{
  "claude_md": "...",          // content of CLAUDE.md if present
  "branch": "feature/phase-11",
  "recent_commits": ["abc123 Add ShellErrorMonitor", ...],
  "dirty_files": ["CTerm/Features/IPC/IPCStore.swift"],
  "open_memories": [...],       // from Phase 12
  "failing_tests": [...],       // from Phase 13 if runner active
  "active_peers": [...],        // other connected agents
  "cwd": "/Users/chris/Developer/Xcode/Terminal"
}
```

**System prompt injection**: Optionally auto-prepend a context block to the first message in each new pane — user-toggleable. This works even without Claude calling the MCP tool explicitly.

**UI**: Settings toggle "Inject project context on session start". Preview button shows what would be injected.

---

## Tier 2 — Automation & Scale

### Phase 15: Trigger / Rule Engine

User-configurable "when X, do Y" automation rules. The automation glue that connects all the above.

**Triggers**:
- `command_fail` — any pane detects a failure (from Phase 11)
- `test_fail` — test runner reports a failure (from Phase 13)
- `agent_idle(seconds)` — a peer has been idle longer than N seconds
- `token_budget(percent)` — a pane's token HUD crosses a threshold (from Phase 9)
- `peer_connect` / `peer_disconnect` — IPC peer event
- `branch_match(pattern)` — current branch matches a glob pattern
- `file_change(pattern)` — a file matching a glob is saved

**Actions**:
- `route_to_pane(target, message)` — inject a message into a pane
- `run_command(command)` — inject a raw command
- `enable_feature(feature)` — toggle auto-accept, checkpoint mode, etc.
- `notify(title, body)` — desktop notification
- `advance_queue` — manually advance the task queue
- `remember(key, value)` — write to agent memory

**Storage**: `~/.cterm/triggers.json`

**UI**: Sidebar tab (lightning bolt icon) with rule list and inline editor. Each rule has an enable/disable toggle, trigger picker, action picker, and test button.

---

### Phase 16: Session Audit Log

Structured, append-only record of everything agents did in a session.

**Captures**:
- Commands injected (source: auto-accept, task queue, user, MCP tool)
- Files changed (from Phase 6's file change tracker)
- Errors routed (from Phase 11)
- Memories written/deleted (from Phase 12)
- Test results (from Phase 13)
- Tokens spent per pane (from Phase 9)
- Tasks completed (from Phase 10)

**Storage**: `~/.cterm/sessions/{date}-{session-id}.json`

**UI**: Sidebar tab (clock icon) with a timeline view. Filter by pane, event type, or time range. Export as markdown or JSON. Shows session summary: total tokens, files changed, tasks completed, errors encountered.

**MCP tool**: `get_session_summary()` — returns a concise summary of the current session that an agent can include in a final report or handoff message.

---

### Phase 17: Multi-Model Routing in Task Queue

Route different tasks to different Claude models based on complexity or cost.

**How it works**:
- Task queue items gain a `model` field (default: inherited from pane)
- Options: `auto`, `haiku`, `sonnet`, `opus`
- `auto` mode: CTerm infers based on task description keywords ("refactor" → sonnet, "explain" → haiku, "architect" → opus)
- When advancing to the next task, the `--model` flag is prepended to the injected prompt (Claude Code's `--model` flag)

**UI**: Per-task model picker dropdown in the task queue panel. Global default in settings.

---

### Phase 18: Semantic Terminal Search

Search across all terminal output — past and present, all panes — not just the current scroll buffer.

**How it works**:
- All terminal output is streamed into an SQLite FTS5 index as it's produced
- Indexed by: pane ID, timestamp, line content
- `cmd+shift+F` opens a global search overlay
- Results show pane name, timestamp, and matching line with context
- Click result → jump to that pane, scroll to that position (or show in a read-only history view if the buffer has scrolled past)

**MCP tool**: `search_terminal_output(query, pane_id?)` — returns matching lines from terminal history. Useful for agents to check if a previous command already ran or what the output was.

---

## Implementation Order

```
✅ Phase 11:  Shell error routing (ShellErrorMonitor + auto-route + ⚠ badge)
✅ Phase 12:  Agent memory (MCP tools + AgentMemoryStore + sidebar tab)
✅ Phase 13:  Test runner watch mode (process watcher + result parser + sidebar tab)
✅ Phase 14:  Ambient context injection (get_project_context MCP tool + auto-prepend)
✅ Phase 15:  Trigger / rule engine (TriggerEngine + rule editor sidebar tab)
✅ Phase 16:  Session audit log (SessionAuditLogger + timeline sidebar tab)
✅ Phase 17:  Multi-model routing in task queue (model picker + --model injection)
✅ Phase 18:  Semantic terminal search (SQLite FTS5 + global search overlay)
```

Start with Phase 11 — it closes the most important feedback loop and builds on infrastructure (surface monitoring, IPC routing) that's already proven in Phases 2 and 7.
