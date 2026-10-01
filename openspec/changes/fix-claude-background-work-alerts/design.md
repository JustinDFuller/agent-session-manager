## Context

The app learns about Claude activity from hooks that append lines to a log, which `StatusLineMonitor` decodes into `ClaudeActivityPayload`. Today `Stop` handling consults `outstandingBackgroundAgents`, a counter incremented by a `PreToolUse` `Task|Agent` hook and decremented by a `SubagentStop` hook. A separate attention watcher forwards `Notification` events, including `idle_prompt`, to the alert path without consulting pane state.

Traces from a real session showed the counter reaching zero while two agents were still running, because `SubagentStop` also fires for agent IDs the app never counted. They also showed the `idle_prompt` banner appearing while both agents ran, because that path never checks for background work. Coming back already works: when background work finishes, Claude restarts its turn and `UserPromptSubmit` returns the pane to working.

## Goals / Non-Goals

Goals:

- Use Claude Code's own report of background work as the single source of truth for whether a session is finished.
- Silence both the `Stop` alert and the `idle_prompt` alert while the pane is working.
- Surface a missing report as an invariant violation rather than adding fallback logic.

Non-goals:

- Other harnesses, permission or question alerts, and manual-cancellation detection.

## Decisions

### Read the lists on `Stop` instead of counting

The `Stop` event carries `background_tasks` and `session_crons`. The app treats the turn as not finished when either list has any entry. This removes the counter and the `PreToolUse` and `SubagentStop` hooks. The hook script keeps only `id`, `type`, and `status` for tasks and `id` and `recurring` for crons, which is enough for tracing without logging task content.

### Recurring schedules count as pending work

"Finished" means the session will not do anything else on its own. A repeating `/loop` or recurring `CronCreate` will wake the session again, so any `session_crons` entry, recurring or not, keeps the pane working and silent. The alternative of alerting between loop iterations was rejected because it would send an alert for every iteration of an intentionally long-running session.

### Missing lists are an invariant violation

Claude Code versions or failure modes that omit either list are not given a fallback. The `Stop` handler first asserts both lists are present. When they are not, it records the warning invariant `claude.stop.background_state` with trace event `statusline.claude.stop_background_state_missing`, then treats the turn as finished, matching today's behavior. This follows the same reporting path as `statusLineWorktreeName`.

### Drop `idle_prompt` while the pane is working

The attention watcher body moves into `applyClaudeAttentionPayload(_:)`, with a test hook like the existing `testApplyClaudeActivityPayload`. Before forwarding, a `Notification` with `notification_type` `idle_prompt` is dropped when the pane lifecycle is working. The drop is traced as `statusline.attention.suppressed` with reason `pane_working`. Other notification types are unaffected.

### Trace vocabulary

The `Stop` trace decision becomes `suppressed_background_work` with `background_task_types` and `session_cron_count` attributes replacing `outstanding_count`. The final decision when nothing is pending remains `fired`.

## Risks / Trade-offs

- If the user cancels background work by hand and Claude does not resume, the pane stays working until the next prompt and no finished alert arrives. Accepted and documented.
- A long-lived recurring schedule keeps the pane working indefinitely, by design.
- The behavior depends on Claude Code v2.1.284 or later reporting the lists. Older versions raise the invariant warning and behave as before.
