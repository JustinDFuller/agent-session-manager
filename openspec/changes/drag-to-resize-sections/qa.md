# Group 1 QA

Group 1 is staged on `feat-issue-187-resize-foundations` from proposal tip `146061c757baf14140dbc19685b82af4b202ce73` in `/tmp/agent-session-manager-resize-stack-group1`.

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --scratch-path /tmp/agent-session-manager-resize-group1-build` passed on 2026-10-11 in 70.76 seconds. This compile does not validate unit tests or runtime UI behavior.

The isolated pure-model test subset ran without launching GUI components: `swift test --skip-build --scratch-path /tmp/agent-session-manager-resize-group1-build --filter 'PaneGridMetricsTests|SectionResizingPersistenceTests' --skip testRestoreSkipsMissingPanesAndReconcilesOnlyChangedTopologyAxis` passed 25 XCTest cases in 0.006 seconds with 0 failures; log: `/tmp/agent-session-manager-resize-group1-pure-model-tests.log`. This covers the Group 1 geometry requirements in task 1.1.

The focused command `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --skip-build --scratch-path /tmp/agent-session-manager-resize-group1-build --filter SectionResizingPersistenceTests.testGenericSettingsPersistenceRoundTripsLayoutSettingsInIsolation` passed 1 case with 0 failures at 2026-10-11 10:25:28 local time; it exercises the generic settings save/load API in isolated app support, checks custom dimensions and all eight binding states round-trip, and confirms `settings.json` is unchanged. Log: `/tmp/agent-session-manager-resize-group1-layout-settings-test.log`. This verifies storage only; Group 2 task 2.3 owns the user-facing save trigger and error UI.

The root agent ran `swift test --skip-build --scratch-path /tmp/agent-session-manager-resize-group1-build --filter SectionResizingPersistenceTests.testRestoreSkipsMissingPanesAndReconcilesOnlyChangedTopologyAxis` on 2026-10-11 at 10:21:11 local time; it passed 1 case with 0 failures in 0.110 seconds; log: `/tmp/agent-session-manager-resize-group1-partial-restore-test.log`. Together, the three invocations passed 27 XCTest cases with 0 failures. Task 1.2 is checked based on independent decoding, generic storage round-trip, reset-scope, and partial-restore coverage. Group 2 still owns the user-facing settings save trigger and error UI.

Tasks 1.3 and 1.4 are checked based on the isolated Dev cleanup entries and internal feature guide, referencing skill, and AGENTS.md feature entry.

No Group 2, Group 3, or integrated UI evidence is claimed by this record.
