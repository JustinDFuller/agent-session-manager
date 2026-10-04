## 1. Background-work detection on Stop

- [ ] 1.1 Pass filtered `background_tasks` and `session_crons` through the hook log, record `notification_type`, remove only the counter's `Task|Agent` and `SubagentStop` registrations, and decode the new fields; verify the generated script and remaining attention matcher.
- [ ] 1.2 Replace the counter with complete reported lists and independent pending-work confirmation retained across resumed prompts; test supported task types, persistent shells, recurring/nonrecurring crons, empty lists, StopFailure, teardown, exactly-once completion, and scheduled/ignored hook decisions without claiming delivery.
- [ ] 1.3 Report `claude.stop.background_state` when either list is absent, clear pending-work confirmation, and finish the active turn even if the remaining list is nonempty; test either/both missing lists and empty/nonempty remaining lists.

## 2. Attention and idle recovery

- [ ] 2.1 Suppress idle attention only for confirmed pending background work; otherwise recover a working pane to stopped and forward one idle event without a finished alert. Preserve deduplication, cancel delayed completion on recovery, and verify suppression/recovery traces with pane/tab context.
- [ ] 2.2 Recognize `PreToolUse` `AskUserQuestion` and `ExitPlanMode` regardless of lifecycle or pending work, preserve the registration and deduplication, and test distinct sources/reasons and unrelated tools.

## 3. Documentation and validation

- [ ] 3.1 Update notifications, activity indicators, tracing, the harness matrix, canonical invariants, and the status-line invariant table; document v2.1.145 field introduction separately from tested versions, persistent servers, and stale-report cancellation limits. Verify `make docs-check` and `scripts/test-release-publishing.sh`.
- [ ] 3.2 Run build, unit tests, format, lint, repository policies, strict change validation, and whitespace checks; record commands and tested commit SHAs in QA evidence.
- [ ] 3.3 Add and run real-flow Dev UI coverage with actual Claude panes for pending background work, question/plan prompts, and Esc-to-idle recovery; run `make test-ui-dev` and capture real screenshots. Record authentication/environment blockers explicitly and leave this task incomplete if validation is blocked.
