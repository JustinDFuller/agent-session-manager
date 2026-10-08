## Why

Claude panes send a "finished" alert when the main agent ends its turn, but a turn can end while Claude is still waiting on background work such as a background agent, a background shell command, a Monitor, a workflow, or a scheduled wakeup (`/loop`, `ScheduleWakeup`, `CronCreate`). The session is not finished, so the alert is noise.

Two problems cause this today. First, the app counts background agents itself by adding one per `Agent`/`Task` launch and subtracting one per `SubagentStop`. In a real session two background agents were launched, unrelated `SubagentStop` events dropped the count to zero, and both agents were still running for roughly two more minutes. Second, Claude Code's own `idle_prompt` notification ("Claude is waiting for your input") arrives about 60 seconds after a turn ends and is posted as a banner without checking for background work at all.

Claude Code now reports background work directly. A complete `Stop` hook report includes `background_tasks` (one entry per running task, with a `type` such as `subagent`, `shell`, `monitor`, or `workflow`) and `session_crons` (one entry per pending wakeup or cron, with a `recurring` flag). Claude Code documents these lists as the way to tell "session is done" apart from "session is paused waiting for background work".

## What Changes

- Stop counting background agents in the app. Read `background_tasks` and `session_crons` from each Claude `Stop` event instead.
- A `Stop` with both lists present and any running background task or any pending session cron leaves the pane working and sends no alert. This includes repeating schedules such as `/loop 5m`, so a pane with a repeating loop stays working and silent until the loop is stopped or expires.
- A `Stop` with both lists empty behaves as it does today: the pane becomes stopped and the alert fires after the existing grace period.
- Drop Claude Code's `idle_prompt` notification only when the latest `Stop` confirms pending background work. Otherwise, an idle notification recovers a stale working pane to stopped and alerts once, without a second finished alert.
- A `Stop` that omits either list reports the warning invariant `claude.stop.background_state` and finishes the active turn, even if the remaining list is nonempty. This clears any prior pending-work confirmation.
- Remove the `PreToolUse` `Task|Agent` and `SubagentStop` hooks that only fed the count.
- Fix the hook log so it records the notification type under the key Claude Code actually sends (`notification_type`), and keeps the task and cron details needed for tracing.
- Retry transient attention queue failures with bounded backoff while the watcher is active, retaining queued records without requiring another append; teardown cancels retries.
- Handle the registered `PreToolUse` `AskUserQuestion|ExitPlanMode` attention events so questions and plan approvals alert regardless of background work.
- Update notifications, pane activity indicators, tracing, the harness feature matrix, the canonical invariant catalog, and the status-line invariant table.

## Capabilities

### New Capabilities

- `claude-stop-alerts`: When a Claude pane is considered finished, when its "finished" and idle alerts are sent or withheld, and how a missing background-work report is surfaced.

### Modified Capabilities

None. No notification capability spec exists yet.

## Impact

Code changes are limited to the Claude hook script and registration, Claude hook payload decoding, `Stop` and attention handling in `StatusLineMonitor`, `PaneAttentionEvent`, the invariant catalog, and the matching unit tests, real-flow Dev UI tests, screenshots, and documentation. There are no new dependencies and no changes to other harnesses.

## Deliberately Out of Scope

- Cursor, Codex, and OpenCode panes.
- Changes to permission prompt behavior; permission requests keep alerting. Question and plan approval handling is explicitly included.
- Detecting cancellation of previously reported background work without a subsequent `Stop` or `StopFailure`. The confirmation remains across resumed prompts until a later report replaces it or the monitor tears down.
- Changing the existing grace period before a finished alert fires.
- Excluding persistent background shell commands such as dev servers. All background shells remain pending work and can suppress completion indefinitely.
- A distinct pane indicator for "waiting on background work". The existing working indicator is used.

## Validation handoff

On 2026-10-08, Justin Fuller requested that live Claude testing take place after merge and release. Implementation supplies real-flow Dev UI coverage, records the actual automated results and authentication skips, and prepares a four-scenario acceptance and real screenshot checklist in QA. Live acceptance and feature screenshots are a human post-release follow-up rather than an archive prerequisite. Failed automated tests remain documented with their attribution; this deferral does not turn failures or skipped scenarios into passes.
