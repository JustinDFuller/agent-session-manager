# Design

## Context

AppKit owns every real window. `AppDelegate` creates the main window, the real Settings window (opened on Cmd+,), and, through `AuxiliaryWindowRegistry`, the dashboards. The SwiftUI `App` body exists only to attach the menu bar commands, and its single scene is `Settings { EmptyView() }`.

SwiftUI opens the first scene it is given at launch. While the dashboards were SwiftUI `Window` scenes, the `Settings` scene sat in front of them as a placeholder, which kept SwiftUI from opening a dashboard (#276). #379 moved the dashboards to AppKit and deleted those scenes, so the placeholder became the only scene and SwiftUI now opens it. It appears as a blank window titled "<ProductName> Settings". The real Settings window is a different window with its own title.

A fresh launch of the current code was observed with two windows: the main window and a 900x450 window titled "AgentSessionManagerDev Settings", which is SwiftUI's default size and differs from the real Settings window at 900x552. The existing UI tests `EmptyStateFlowTests.testEmptyStateFlow` and `SettingsFlowTests.testSettingsDoesNotAutoOpen` both pass on this code when run with `make test-ui-dev-launch`, so they do not detect the bug, and the UI test workflow is also skipped unless the `ENABLE_MACOSX_JOBS` repository variable is `true`. The fix adds a test that counts windows at launch. See proposal.md for the motivation.

## Goals / Non-Goals

**Goals:**

- Launch and relaunch show only the main window.
- The fix uses a documented scene setting rather than relying on scene ordering.
- The deployment floor and toolchain floor match what the fix and the validated environment need.

**Non-Goals:**

- Removing the SwiftUI app definition or rebuilding the menu bar in AppKit.
- Changing the real Settings window.

## Decisions

### Suppress the placeholder with scene settings

Add `.defaultLaunchBehavior(.suppressed)` and `.restorationBehavior(.disabled)` to the placeholder `Settings` scene. The first stops SwiftUI opening it at launch. The second stops macOS window restoration reopening it after a quit with it open. Both compile against a `Settings` scene at a macOS 26 target, checked in a throwaway package.

Alternatives considered:

- Keep macOS 14 and add a hidden second scene so the `Settings` scene is no longer first. This worked before #379 but depends on undocumented scene ordering that #276 had to call out explicitly. It would break again the next time a scene is removed.
- Replace the SwiftUI app definition and build the menu bar in AppKit. This removes the placeholder entirely but means rebuilding every menu, including the system Edit, Window, and Help menus, by hand. The risk outweighs the benefit for a fix.

### Raise the deployment floor to macOS 26

The scene settings need macOS 15. The floor goes to 26 instead, which is the user's decision, because 26 is the version the app is validated and used on. Consequences:

- SwiftPM only accepts `.macOS(.v26)` from tools version 6.2 (verified: tools 6.1 reports `'v26' is unavailable`), so `Package.swift` moves to `// swift-tools-version: 6.2`.
- `scripts/check-toolchain.sh` requires Swift 6.2 and Xcode 26, because building for macOS 26 needs the Xcode 26 SDK. The validated toolchain is already newer.
- `project.yml` deployment target and every `MACOSX_DEPLOYMENT_TARGET` become `26.0`, and the generated Xcode project is regenerated.
- The `actool --minimum-deployment-target` argument in `Tests/MacNotificationCoordinatorTests.swift` is set to `26.0` so the test icon compile matches the app.
- Availability checks that the floor makes always true are removed: `@available(macOS 15.0, *)` on the Control-Return override in `TerminalController.swift` with its `XCTSkip` guards in `Tests/TerminalControlReturnTests.swift`, and the `macOS 12` branch in `TracingService.swift` with its dead `SignPostIntegration` fallback.

### Move macOS CI jobs to macOS 26 runners

An app built for macOS 26 cannot launch on a macOS 15 runner, so `unit-tests.yml`, `ui-tests.yml`, `dependency-toolchain-compatibility.yml`, and `release.yml` change from `macos-15` to `macos-26`. The runner-images repository publishes a macOS 26 image. The two Linux jobs that run `swift package resolve` and `swift format` in a `swift:6.1` container move to `swift:6.2`, because a 6.1 toolchain cannot read a tools-6.2 manifest.

## Risks / Trade-offs

- [Users on macOS 14 or 15 cannot run new releases] → This is a deliberate, user-approved breaking change. Their installed version keeps working, and the install and download pages state the new requirement.
- [The `Settings` scene ignores a scene setting at runtime even though it compiles] → The new window-count launch UI test and Computer Use validation on a Dev build catch this before merge. If it fails, the fallback is a hidden `Window` scene with the same settings placed first, with commands attached to it.
- [The `macos-26` runner label or its Xcode differs from local] → Checked by the CI runs on this pull request, but only where `ENABLE_MACOSX_JOBS` is enabled, so the local `make` targets and a Dev build are the authoritative checks.
- [The UI tests stay skipped in CI] → Recorded as a follow-up in proposal.md. This change does not depend on it, because it runs `make test-ui-dev-launch` locally.

## Migration Plan

No data migration. Release notes for the next release should mention the macOS 26 requirement. Rollback is reverting the change, which restores the macOS 14 floor and the blank window.
