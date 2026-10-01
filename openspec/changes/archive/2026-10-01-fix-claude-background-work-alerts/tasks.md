## 1. Background-work detection on Stop

- [x] 1.1 Pass `background_tasks` and `session_crons` through the Claude hook log (keeping only `id`, `type`, `status` for tasks and `id`, `recurring` for crons), log the notification type as `notification_type`, remove the `PreToolUse` `Task|Agent` and `SubagentStop` hook registrations, and decode the new fields; verify with a test that runs the generated hook script on a real-shaped `Stop` payload and a hook settings test for the removed hooks.
- [x] 1.2 Replace the background agent counter with the reported lists: a `Stop` with any background task or session cron keeps the pane working and sends no alert, and a `Stop` with both lists empty stops the pane and alerts after the existing grace period; verify with tests for each of `subagent`, `shell`, `monitor`, a session cron, empty lists, and a prompt → pending `Stop` → `UserPromptSubmit` → empty `Stop` sequence that alerts exactly once.
- [x] 1.3 Add the `claude.stop.background_state` warning invariant and report it when a `Stop` lacks either list, treating the turn as finished; verify with a test that the invariant is recorded and the alert fires.

## 2. Idle alert

- [x] 2.1 Move the attention watcher body into `applyClaudeAttentionPayload(_:)` with a test hook, drop `idle_prompt` notifications while the pane is working, and trace the drop as `statusline.attention.suppressed` with reason `pane_working`; verify an `idle_prompt` produces no attention event while working and one after the pane has stopped.

## 3. Documentation and validation

- [x] 3.1 Update the notifications, tab and pane activity indicator, tracing, and agent harness feature matrix documentation for the new behavior; verify with `make docs-check` and `scripts/test-release-publishing.sh`.
- [x] 3.2 Run the unit test suite, `make no-code-comments`, `make no-fixed-width-prose`, `openspec validate fix-claude-background-work-alerts --type change --strict`, and `git diff --check`; verify all pass.
