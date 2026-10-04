# QA: fix-claude-background-work-alerts

## Reviewed implementation and validation boundary

Initial validation and the owned Dev run used `69c3bddd7094d0c197fbaf19413555cfba4d6d91`. The prior queue/bounds revision was `df853ac1f9f49ef3ae57af6d6034ddd83e17ddd8`. The final behavior/test revision is `a946804233641200e14d81f0891f6f70e1a5c147`: it additionally compacts consumed attention records under the appenders' lock, preserves partial suffixes and concurrent appends, traces open failures, and hashes all payload bytes for deduplication. The full unit retry, build, docs, policies, strict change validation, whitespace checks, and Dev UI-test compilation passed for that revision on 2026-10-04. `28408a715674e6f93dc58cdc89c3254af88ce22d` removes one blank test line; formatting, lint, and the 97-test focused suite passed at that revision. Subsequent QA commits change only this record and task completion. The release-publishing check passed on the initial revision; release behavior is unchanged. The final proposal contract is `62559dda82f4d39cf47f81da2a4ee4849938df87` in #373. The isolated checkout preserves the unrelated dirty main checkout.

| Command | Result |
| --- | --- |
| `CFFIXED_USER_HOME=/private/tmp/agent-session-manager-unit-compaction-retry-home swift test --skip-build` | Passed: 1,175 XCTest tests and 123 Swift Testing tests in 11 suites. Unit-test app support was isolated from production. |
| `CFFIXED_USER_HOME=/private/tmp/agent-session-manager-unit-compaction-retry-home swift test --filter 'PaneActivityInvariantTests|StatusLineMonitorHook'` | Passed: 97 tests, including incomplete reports, recovery, selected PreToolUse tools, duplicate handling, and completion-grace races. |
| `swift build` | Passed. |
| `swift-format lint --recursive --strict Sources Tests UITests` | Passed. |
| `swiftlint lint --strict` | Passed, zero violations. |
| `node .github/scripts/no-code-comments.mjs --root .` | Passed, including the staged new UI test. |
| `node .github/scripts/fixed-width-prose.mjs --root .` | Passed. |
| `make docs-check` | Passed: rendered documentation and local links. |
| `scripts/test-release-publishing.sh` | Passed. |
| `openspec validate fix-claude-background-work-alerts --strict --no-interactive` | Passed. |
| `git diff --cached --check` | Passed. |

The regression matrix covers either missing list with an empty/nonempty remaining list, both missing, null fields, complete empty lists, supported and future pending task types, recurring/nonrecurring crons, exactly-once completion, and StopFailure/teardown. Question/plan attention is tested while unknown, working, stopped, and waiting on background work. Direct `Stop(empty) → idle_prompt` and `Stop(empty) → Stop(pending)` during the completion grace period cancel the queued finished alert. Repeated idle events deduplicate within one turn and recover again after a new prompt. The final trace-contract regressions confirm `scheduled` for a completion candidate even when the resumed prompt cancels delivery, and `ignored_not_working` for a duplicate Stop; they assert callback counts independently. An oversized Unicode report verifies at most 16 sampled type values, at most 64 UTF-8 bytes per value without malformed boundaries, and the full task count; suppression still classifies the entire report. Generated-script/file-watcher regressions cover question→idle while background work is pending, question→plan order, identical-input deduplication without generated timestamps, consumed-offset replay prevention, split records, and continued event arrivals while the queue drains. Oversized control-character/100-task/100-cron reports verify 32-entry log samples, field limits, full/omitted counts, and a bounded encoded record; full counts preserve pending state and never override missing-list fallback. Additional component regressions verify same-file compaction removes consumed history, preserves a partial next event and future appends, and delivers all 30 distinct records in order while a separate process runs generated hooks concurrently with the reader. They also verify an unreadable queue produces `statusline.attention.read_failed` with pane/tab context. Hashing every payload byte avoids the existing `Data` hash treating distinct same-length records as duplicates. These are component tests, not actual-Claude UI evidence. The background UI scenario continuously asserts no notification row for three seconds after the pending Stop, beyond the 1.8-second completion grace.

The first final full-unit invocation stalled in unrelated Agent Control test execution; a sample showed XCTest waiting, and only that run's test child was terminated. A retry using a fresh isolated app-support root and the already-built a946804 test bundle passed the entire suite in 57 seconds. The initial lint pass identified one blank line before the new test class's closing brace; 28408a7 removes that line, and strict lint/format checks pass. No raw attention payloads were captured for diagnosis.

## Real-flow Dev validation: incomplete

Current installed Claude Code was rechecked after the final component validation as **2.1.289**; the earlier owned Dev pane showed **2.1.216**, and its authentication status is `loggedIn=false`, `authMethod=none`. The documented field-availability floor is **2.1.145**, as established by [Anthropic's changelog](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md#21145). The earlier **2.1.286** payload below is historical evidence, not the version tested in this revision.

`make test-ui-dev` was attempted with Dev isolation and failed before tests at SwiftTerm package-plugin trust validation. An invocation-only `-skipPackagePluginValidation` retry resolved newer dependencies and failed compiling swift-collections. Copying the repository's `Package.resolved` into the generated Xcode workspace and passing `-onlyUsePackageVersionsFromResolvedFile` fixed that dependency drift; the Dev build-for-testing passed with the committed UI test class and was repeated successfully for the final a946804 behavior revision. Runtime execution remains blocked as described below. No tracked dependency lock or global Xcode trust setting was changed.

The focused retry used `xcodebuild test-without-building -project AgentSessionManager.xcodeproj -scheme AgentSessionManager -configuration Dev -destination 'platform=macOS' -derivedDataPath .build/DerivedData -resultBundlePath .build/noisy-alerts-ui-final.xcresult -only-testing:AgentSessionManagerUITests/ClaudeNotificationFlowTests`. The app bundle identifier was verified as `com.justinfuller.agent-session-manager.xcode-dev`. It failed before any test case executed: **the test runner timed out while enabling automation mode**. This is environment failure, not an application assertion failure or a passing/skipped scenario result. The broad Dev UI suite has no passing result.

Four actual-Claude UI scenarios were added: pending background shell through real completion, AskUserQuestion while background work is pending, ExitPlanMode while background work is pending, and foreground Bash interrupted with Esc followed by a real idle notification. They use the normal sheets and actual hook/transcript files, with no fabricated state or test-only production behavior. When automation can initialize, they explicitly skip if Claude remains signed out. The screenshot target and inventory include their four captures; none of those feature screenshots has been produced.

A separately owned Dev run, `19c9417a-c016-4f88-8a1a-ac2e0ce2314a`, verified source commit `69c3bdd`, PID 87375, the isolated runtime manifest, and exact window title `Agent Session Manager (Dev · 19c9417a)`. Computer Use dismissed onboarding, created a real tab for the review checkout, enabled Debug Mode through Settings, and attached the existing checkout without taking over worktree management. The real Claude pane displayed **Claude Code v2.1.216** and **Not logged in · Run /login**. Safe screenshots are retained locally under `.build/recursive-development/19c9417a-c016-4f88-8a1a-ac2e0ce2314a/screenshots/` as `tab.png` and `claude-signed-out.png`. They prove tab/pane startup and the sign-in blocker, not alert correctness.

The bounded collector returned 25 correlated global spans, zero malformed lines, no candidate pane trace files, and no selected-pane spans. Alert telemetry and invariant acceptance therefore remain unverified. Performance was sampled without an acceptance threshold. The owned PID was stopped and the UUID support directory removed; the existing checkout was retained. Production app state was not used for UI testing.

Task 3.3 remains **unchecked**. Required follow-up is an authenticated Claude pane and working macOS UI automation, followed by the actual four scenarios, real feature screenshots, and a passing `make test-ui-dev`. Hosted macOS build, unit, and UI jobs are currently skipped and supply no runtime proof. The archive transition remains pending while this validation is incomplete; strict archived-task validation must not be represented as passing.

## Historical payload evidence carried forward

The hook script body was extracted verbatim from `writeHookLogScript()` on the implementation branch, with only the log path pointed at a scratch file under `/tmp`. It was registered as the `UserPromptSubmit` and `Stop` hook for a real `claude -p` run on Claude Code 2.1.286.

The logged lines, with `session_id` and `transcript_path` removed:

```json
{"hook_event_name": "UserPromptSubmit", "notification_type": null, "message": null, "agent_id": null, "agent_type": "coordinator", "timestamp": 1790860425.749839}
{"hook_event_name": "Stop", "notification_type": null, "message": null, "agent_id": null, "agent_type": "coordinator", "timestamp": 1790860436.192406, "background_tasks": [], "session_crons": []}
```

This shows that a real Claude Code `Stop` carries both lists, that the script records them under the keys the app decodes, and that events without the lists (`UserPromptSubmit`) record no list keys. A `Stop` with both lists empty is the "finished" golden path.

## Historical limitation

A live run with a background task still running at `Stop` was not captured. The attempt to launch a nested Claude Code run that starts a background shell command was blocked by the session's permission check. The non-empty-list behavior is covered by unit tests that use the documented payload shape from the Claude Code hooks reference.
