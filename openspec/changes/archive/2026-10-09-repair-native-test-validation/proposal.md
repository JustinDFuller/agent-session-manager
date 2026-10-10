## Why

The native test suite fails before or during real user flows: Xcode can resolve a different package graph, first-open sheets can be empty, dashboard windows can open at launch, and shell attention never reaches the notification sidebar. Existing injected notification tests and a terminal bypass hide those failures, so the suite needs reproducible dependencies and genuine runtime evidence for issue #221.

## What Changes

- Use the repository dependency lockfile for generated Xcode builds, Dev UI runs, and screenshots, with regression coverage for regeneration and missing locks.
- Run the real terminal and Agent Control setup paths during isolated Dev tests and restoration.
- Populate pane settings, refresh, and scrollback sheets from their selected data and preserve confirmation and cancellation behavior.
- Open dashboard windows only on explicit request and prevent their restoration on a later launch.
- Bind notifications for shell panes and replace injected notification flows with real terminal attention and a real merged pull request.
- Make terminal interaction, icon selection, long option lists, and native dialogs reachable through the accessibility tree.
- Keep the pre-push UI check in the Dev environment and distinguish authentication-dependent skips from executed evidence.

The remaining fake-test migration in issue #221, harness sign-in, dependency upgrades, release deployment, and production account settings are deliberately out of scope.

## Capabilities

### New Capabilities

- `native-test-validation`: Reproducible Dev validation, real-flow evidence, and explicit environment prerequisites.
- `native-pane-interactions`: First-open sheet state, shell attention delivery, full-row icon selection, and explicit dashboard lifecycle.

### Modified Capabilities

None. The existing Claude alert contract remains unchanged.

## Impact

The changes affect the Makefile, Dev test workflow and pre-push hook, pane and auxiliary-window presentation, shell notification wiring, accessibility metadata, unit and UI tests, and internal feature documentation. Public harness commands and persisted configuration formats remain compatible. No package versions change.
