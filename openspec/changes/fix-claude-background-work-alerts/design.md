## Context

The app learns about Claude activity from hooks that append lines to a log, which `StatusLineMonitor` decodes into `ClaudeActivityPayload`. Today `Stop` handling consults `outstandingBackgroundAgents`, a counter incremented by a `PreToolUse` `Task|Agent` hook and decremented by a `SubagentStop` hook. A separate attention watcher forwards `Notification` events, including `idle_prompt`, to the alert path without consulting pane state.

Traces from a real session showed the counter reaching zero while two agents were still running, because `SubagentStop` also fires for agent IDs the app never counted. They also showed the `idle_prompt` banner appearing while both agents ran, because that path never checks for background work. Coming back already works: when background work finishes, Claude restarts its turn and `UserPromptSubmit` returns the pane to working.

## Goals / Non-Goals

Goals:

- Use Claude Code's own report of background work as the single source of truth for whether a session is finished.
- Silence completion and idle alerts while a complete `Stop` report confirms pending background work, while recovering interrupted foreground turns on an idle notification.
- Surface incomplete reports as warning invariants and finish the active turn.
- Forward question and plan approval attention events regardless of background work.

Non-goals:

- Other harnesses, changing permission alerts, and detecting manual cancellation of previously reported background work without another lifecycle report.

## Decisions

### Read the lists on `Stop` instead of counting

The `Stop` event carries `background_tasks` and `session_crons`. The app suppresses completion only when both lists are present and either has entries. This removes the counter and only the `PreToolUse` `Task|Agent` and `SubagentStop` registrations; the question and plan approval registration stays. The hook script keeps only `id`, `type`, and `status` for tasks and `id` and `recurring` for crons, which is enough for tracing without logging task content.

### Recurring schedules count as pending work

"Finished" means the session will not do anything else on its own. A repeating `/loop` or recurring `CronCreate` will wake the session again, so any `session_crons` entry, recurring or not, keeps the pane working and silent. The alternative of alerting between loop iterations was rejected because it would send an alert for every iteration of an intentionally long-running session.

### Missing lists are an invariant violation

Claude Code versions or failure modes that omit either list use the existing finished-turn fallback. The `Stop` handler first asserts both lists are present. When they are not, it records the warning invariant `claude.stop.background_state` with trace event `statusline.claude.stop_background_state_missing`, then clears prior pending-work confirmation and treats the active turn as finished, even if the other list is nonempty. This follows the same reporting path as `statusLineWorktreeName`.

### Confirm pending work independently of pane lifecycle

The monitor retains a boolean confirmation from the latest `Stop`: true only for a complete report containing pending work, false for complete empty or incomplete reports. `StopFailure` and monitor teardown clear it. `UserPromptSubmit` starts working and cancels delayed completion, but retains the confirmation because a new foreground turn does not establish that earlier background work disappeared.

### Recover on idle unless background work is confirmed

The attention watcher body moves into `applyClaudeAttentionPayload(_:)`, with the existing testing entry point. An `idle_prompt` is suppressed only when pending background work is confirmed. Trace the drop as `statusline.attention.suppressed` with reason `background_work_pending`. Otherwise, if the pane is working, cancel delayed completion, transition it to stopped, record `pane.activity.changed` with source `claude_idle_prompt` and `statusline.attention.recovered` with reason `idle_without_background_work`, then forward the idle attention event through the existing deduplication path. Do not invoke the finished-alert callback. This recovers an interrupted foreground turn without observing keyboard input or assuming that every Esc keypress interrupted Claude.

### Questions and plan approvals always request attention

`PaneAttentionEvent.claudeHook` recognizes `PreToolUse` only for `AskUserQuestion` and `ExitPlanMode`, producing sources `claude_question` and `claude_plan_approval` with reasons "Claude has a question" and "Claude needs plan approval". The registered hook matcher remains `AskUserQuestion|ExitPlanMode`. These events bypass idle suppression and retain existing deduplication and notification settings. Other tools do not produce attention.

### Trace vocabulary

A complete pending report records `suppressed_background_work` with `background_task_types`, `background_task_count`, and `session_cron_count` attributes replacing `outstanding_count`. Record only the first 16 task types, each truncated to at most 64 UTF-8 bytes at a valid character boundary; the full task count preserves report size without unbounded telemetry. These trace bounds do not alter pending-work classification. A Stop outside an active turn records `ignored_not_working`; an active finishing Stop records `scheduled`, indicating only a completion candidate queued for the grace period. A resumed prompt, later pending Stop, forwarded idle event, or teardown can cancel that candidate. Hook-processing decisions do not claim notification delivery; exactly-once callback tests validate delivery separately.

## Risks / Trade-offs

- If previously reported background work is cancelled without a later lifecycle report, idle alerts remain suppressed until a new report or monitor teardown clears the confirmation. Accepted and documented.
- A long-lived recurring schedule or persistent background shell such as a dev server keeps the pane working indefinitely, by design.
- [Claude Code v2.1.145 introduced the two lists](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md#21145). Reports depend on registry availability, so newer versions can also omit fields. Existing live evidence is limited to v2.1.286; the documented introduction version is not a claim of a live test on v2.1.145.

### Bounded hook records and lossless attention transport

Hook records retain at most 32 task entries and 32 cron entries, with bounded identifier/type/status strings. Full list counts and omitted-entry counts are recorded separately; the monitor uses full counts when available so truncation never turns pending work into completion. Both lists must still be present. Scalar diagnostic fields are bounded, and task descriptions/commands and cron prompts are excluded.

The existing attention registrations invoke the generated hook script in attention mode. It appends bounded JSONL records to the per-pane attention file under an exclusive lock shared with the reader, with a stable fingerprint of the original input and no generated timestamp in the attention record. The watcher consumes every complete record by byte offset, retains an unfinished line, and applies the existing payload deduplication and idle gate independently. Debounce coalesces reads, never events. After reading all available bytes under that lock, the reader compacts consumed complete records in place on the same inode, preserves the unfinished suffix, and resets its offset to that suffix length. Writers append under the same lock, so unread appends cannot be overwritten by compaction. Successful reads leave no consumed history on disk; queued unread records remain until drained. Open, lock, read, and compaction failures use the attention read-failure diagnostic. Teardown clears offsets and buffers. This preserves a question or plan request even when a subsequent idle event is suppressed.
