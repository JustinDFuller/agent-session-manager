# Proposal

## Why

Every launch of Agent Session Manager opens a second, blank window titled "AgentSessionManagerDev Settings" on top of the main window. It is not the real Settings window, which is opened with Cmd+, and titled "AgentSessionManager Settings". It is an empty placeholder that the app's SwiftUI layer opens on its own since the dashboards moved out of SwiftUI on October 10 (#379), when it became the only scene SwiftUI knows about. The existing launch UI tests pass on current code even though the blank window appears, and the UI test workflow is skipped on every pull request, so the regression shipped unnoticed. The fix therefore adds a launch test that fails while the bug exists.

## What Changes

- A fresh launch, and a relaunch after quitting with any window open, shows only the main window. No blank Settings window appears.
- Cmd+, and the Settings… menu item keep opening the real Settings window, unchanged.
- **BREAKING**: The minimum supported macOS rises from 14 to 26. macOS 26 is the first version the app is validated on, and it provides the scene setting that keeps the placeholder from opening at launch. Earlier macOS versions can no longer run new releases.
- The toolchain floor rises to Swift 6.2 and Xcode 26, which building for macOS 26 requires.
- CI jobs that build or test the app move to macOS 26 runners, and the Linux Swift jobs move to a Swift 6.2 container.
- The public install and download pages say "macOS 26 or later".

## Capabilities

### New Capabilities

- `app-launch-windows`: which windows the app shows at launch and after a relaunch, and that the real Settings window opens only on request.

### Modified Capabilities

None. The existing `native-pane-interactions` requirement that dashboards stay closed at launch is unchanged and remains the sibling of this one.

## Impact

- Code: the placeholder scene in `Sources/AgentSessionManager/ContentView.swift`, and availability checks that the new floor makes unnecessary in `Sources/AgentSessionManager/Controllers/TerminalController.swift`, `Sources/AgentSessionManager/Models/TracingService.swift`, and `Tests/TerminalControlReturnTests.swift`.
- Build: `Package.swift`, `project.yml`, the generated Xcode project, `scripts/check-toolchain.sh`, and the runner labels in the four macOS workflows and the Swift container in the two Linux workflows under `.github/workflows/`.
- Documentation: `documentation/how-to/install.md`, `documentation/how-to/download.md`, `documentation/features/dev-build.md`, `AGENTS.md`, and the current-state toolchain lines in `AGENTIC_CONTROL.md`.
- Users: anyone on macOS 14 or 15 stays on their last release. Updates will not install for them.
- Dependencies: no package changes.

## Out of Scope

- Replacing the SwiftUI app definition with a fully AppKit menu bar and lifecycle. That is a larger rewrite and is not needed for this fix.
- Changing the real Settings window, its contents, or its shortcut.
- Changing how dashboards or the main window open, close, or restore.
- Enabling the UI test workflow by setting the `ENABLE_MACOSX_JOBS` repository variable. That is a repository setting, recorded below as a follow-up rather than done here.
- Raising the Swift language mode or adopting other macOS 26 only APIs.

## Follow-ups after merge

- Decide whether to turn on the `ENABLE_MACOSX_JOBS` repository variable so the launch UI tests run on pull requests.
