## Why

Claude panes send a "finished" alert when the main agent ends its turn, but a turn can end while Claude is still waiting on background work such as a background agent, a background shell command, a Monitor, a workflow, or a scheduled wakeup (`/loop`, `ScheduleWakeup`, `CronCreate`). The session is not finished, so the alert is noise.

Two problems cause this today. First, the app counts background agents itself by adding one per `Agent`/`Task` launch and subtracting one per `SubagentStop`. In a real session two background agents were launched, unrelated `SubagentStop` events dropped the count to zero, and both agents were still running for roughly two more minutes. Second, Claude Code's own `idle_prompt` notification ("Claude is waiting for your input") arrives about 60 seconds after a turn ends and is posted as a banner without checking for background work at all.

Claude Code now reports background work directly. Every `Stop` hook event includes `background_tasks` (one entry per running task, with a `type` such as `subagent`, `shell`, `monitor`, or `workflow`) and `session_crons` (one entry per pending wakeup or cron, with a `recurring` flag). Claude Code documents these lists as the way to tell "session is done" apart from "session is paused waiting for background work".

## What Changes

- Stop counting background agents in the app. Read `background_tasks` and `session_crons` from each Claude `Stop` event instead.
- A `Stop` with any running background task or any pending session cron leaves the pane working and sends no alert. This includes repeating schedules such as `/loop 5m`, so a pane with a repeating loop stays working and silent until the loop is stopped or expires.
- A `Stop` with both lists empty behaves as it does today: the pane becomes stopped and the alert fires after the existing grace period.
- Drop Claude Code's `idle_prompt` notification while the pane is working, which covers the waiting-on-background-work case. When the pane is stopped it behaves as today.
- A `Stop` that arrives without both lists is reported as a new warning invariant, `claude.stop.background_state`, and treated as finished, which is today's behavior.
- Remove the `PreToolUse` `Task|Agent` and `SubagentStop` hooks that only fed the count.
- Fix the hook log so it records the notification type under the key Claude Code actually sends (`notification_type`), and keeps the task and cron details needed for tracing.
- Update the notifications, pane activity indicator, tracing, and harness feature matrix documentation.

## Capabilities

### New Capabilities

- `claude-stop-alerts`: When a Claude pane is considered finished, when its "finished" and idle alerts are sent or withheld, and how a missing background-work report is surfaced.

### Modified Capabilities

None. No notification capability spec exists yet.

## Impact

Code changes are limited to the Claude hook script and registration, Claude hook payload decoding, `Stop` and attention handling in `StatusLineMonitor`, the invariant catalog, and the matching tests and documentation. There are no new dependencies and no changes to other harnesses.

## Deliberately Out of Scope

- Cursor, Codex, and OpenCode panes.
- Permission prompt, question, and plan approval alerts, which genuinely need the user and keep alerting.
- Detecting background work that the user cancels by hand without Claude resuming. The pane stays working until the next prompt. This is a known limitation.
- Changing the existing grace period before a finished alert fires.
- A distinct pane indicator for "waiting on background work". The existing working indicator is used.
