## 1. Background-work detection on Stop

- [x] 1.1 Pass bounded filtered `background_tasks` and `session_crons` through the hook log with full and omitted counts, record `notification_type`, remove only the counter's `Task|Agent` and `SubagentStop` registrations, and decode the new fields; verify the generated script and remaining attention matcher.
- [x] 1.2 Replace the counter with complete reported lists and independent pending-work confirmation retained across resumed prompts; test supported task types, persistent shells, recurring/nonrecurring crons, empty lists, StopFailure, teardown, exactly-once completion, and scheduled/ignored hook decisions without claiming delivery.
- [x] 1.3 Report `claude.stop.background_state` when either list is absent, clear pending-work confirmation, and finish the active turn even if the remaining list is nonempty; test either/both missing lists and empty/nonempty remaining lists.

## 2. Attention and idle recovery

- [x] 2.1 Suppress idle attention only for confirmed pending background work; otherwise recover a working pane to stopped and forward one idle event without a finished alert. Preserve deduplication, cancel delayed completion on recovery, and verify suppression/recovery traces with pane/tab context.
- [x] 2.2 Recognize `PreToolUse` `AskUserQuestion` and `ExitPlanMode` regardless of lifecycle or pending work, preserve the registration and deduplication, and test distinct sources/reasons and unrelated tools. Queue every complete attention record by offset; test bursts, split records, and deduplication without overwriting earlier events. Compact consumed records under the writer lock, preserve partial/unread data, and test sustained concurrent appends and read-failure diagnostics. Retry transient failures without another append using bounded backoff; test lock contention, recovery exactly once, backoff reset, and teardown cancellation.

## 3. Documentation and validation

- [x] 3.1 Update notifications, activity indicators, tracing, the harness matrix, canonical invariants, and the status-line invariant table; document v2.1.145 field introduction separately from tested versions, persistent servers, and stale-report cancellation limits. Verify `make docs-check` and `scripts/test-release-publishing.sh`.
- [x] 3.2 Run build, unit tests, format, lint, repository policies, strict change validation, and whitespace checks; record commands and tested commit SHAs in QA evidence.
- [x] 3.3 Add real-flow Dev UI coverage with actual Claude panes for pending background work, question/plan prompts, and Esc-to-idle recovery; run `make test-ui-dev` and the focused class, and record actual passes, failures, authentication skips, commands, and tested revisions. Prepare the four-scenario manual acceptance and real screenshot checklist for Justin Fuller after merge and release, as requested on 2026-10-08. Completing this task records the automated evidence and deferred handoff; it does not claim the live scenarios, skipped tests, or screenshots passed.
