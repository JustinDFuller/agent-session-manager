# Group 2 QA

Group 2 is staged on `feat-issue-187-resize-global` in `/tmp/agent-session-manager-resize-stack-group2`, with Group 1 commit `c8babd7db7d12f270a4bba2717d268a4fdc0d9db` as its current parent. The proposal tip was `146061c757baf14140dbc19685b82af4b202ce73`; formal stack metadata has not been verified.

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --scratch-path /tmp/agent-session-manager-resize-group1-build` passed on 2026-10-11 in 70.76 seconds. This compile does not validate unit tests or runtime UI behavior.

The isolated pure-model test subset ran without launching GUI components: `swift test --skip-build --scratch-path /tmp/agent-session-manager-resize-group1-build --filter 'PaneGridMetricsTests|SectionResizingPersistenceTests' --skip testRestoreSkipsMissingPanesAndReconcilesOnlyChangedTopologyAxis` passed 25 XCTest cases in 0.006 seconds with 0 failures; log: `/tmp/agent-session-manager-resize-group1-pure-model-tests.log`.

The focused `testGenericSettingsPersistenceRoundTripsLayoutSettingsInIsolation` case passed one case with 0 failures at 2026-10-11 10:25:28 local time; it exercises generic settings save/load in isolated app support, checks custom dimensions and all eight binding states round-trip, and confirms `settings.json` is unchanged. Log: `/tmp/agent-session-manager-resize-group1-layout-settings-test.log`.

The partial-pane restore case `testRestoreSkipsMissingPanesAndReconcilesOnlyChangedTopologyAxis` passed one case with 0 failures in 0.110 seconds; log: `/tmp/agent-session-manager-resize-group1-partial-restore-test.log`. Together, these isolated Group 1 invocations passed 27 XCTest cases with 0 failures. Tasks 1.1 through 1.4 are checked in the task record; Group 2 task 2.3 owns the user-facing settings save trigger and error UI.

Group 2 source and test targets compiled with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --build-tests --scratch-path /tmp/agent-session-manager-resize-group2-build`; after synchronizing the latest Group 1 persistence test and current UI-test helper/selector corrections, the build passed in 24.78 seconds with no test execution; log: `/tmp/agent-session-manager-resize-group2-resynced-build.log`. Static checks passed after synchronization: `make lint`, `make no-code-comments`, `make no-fixed-width-prose`, `swiftlint lint --strict --config .swiftlint.yml`, and `git diff --check`. No Group 2 UI tests were executed in this worktree, so Group 2 runtime behavior remains unverified here.

The full Group 2 unit suite ran with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --scratch-path /tmp/agent-session-manager-resize-group2-build` and passed 1,231 XCTest cases in 75.517 seconds plus 123 Swift Testing cases in 11 suites in 0.209 seconds, with 0 failures; log: `/tmp/agent-session-manager-resize-group2-unit.log`. This validates unit behavior only and is not runtime UI proof.

The original full implementation worktree's Dev UI run ended with exit 65: 11 cases passed and 6 failed. This is original-tree evidence, not isolated Group 2 proof; the result includes failures outside Group 2 and must not be used to claim that Group 2 passed. A later Dev UI invocation for seven cases ended with exit 75 when the Mac session was screen-locked (`IOConsoleUsers` reported `CGSSessionScreenIsLocked`). Two app launches failed; setup for the third case was interrupted, so seven tests did not execute and this run provides no corrected-behavior proof. `make reset-app-state-dev` completed afterward. This is an infrastructure interruption, not a test pass or product failure.

The local explicit `validateCandidate` gate passed at position 3 of 6 against the immutable `c8babd7` baseline with `findings: []`; log: `/tmp/agent-session-manager-resize-group2-local-gate.log`. This is local candidate-gate evidence only; formal stack metadata and GitHub stack relationships remain unverified.

The public how-to covers only Group 2 tab-bar and notification-sidebar resizing. Pane-grid, shortcut-routing, and status viewport instructions are deferred until Group 3 implements those behaviors. The internal feature guide records the approved full target and identifies this staged implementation boundary.

`make lint`, `make no-code-comments`, `make no-fixed-width-prose`, `swiftlint lint --strict --config .swiftlint.yml`, and `git diff --check` passed in this worktree before the latest isolated Group 1 synchronization. Group 3 implementation or runtime evidence is not claimed.
