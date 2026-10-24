# Tasks

## 1. Raise the deployment and toolchain floor

- [x] 1.1 Change `Package.swift` to `// swift-tools-version: 6.2` with `.macOS(.v26)`, set `deploymentTarget.macOS` and every `MACOSX_DEPLOYMENT_TARGET` in `project.yml` to `26.0`, and regenerate the Xcode project; verify `swift package describe` succeeds and `scripts/test-xcodeproj.sh` passes
- [x] 1.2 Raise `scripts/check-toolchain.sh` to require Swift 6.2 and Xcode 26 and update its messages; verify `scripts/check-toolchain.sh` and `scripts/check-toolchain.sh swift-only` both pass locally
- [x] 1.3 Set `--minimum-deployment-target` to `26.0` in `Tests/MacNotificationCoordinatorTests.swift`; verify that test passes
- [x] 1.4 Remove the availability checks the new floor makes always true: `@available(macOS 15.0, *)` in `Sources/AgentSessionManager/Controllers/TerminalController.swift`, the matching `#available` and `XCTSkip` guards in `Tests/TerminalControlReturnTests.swift`, and the `macOS 12` branch and `SignPostIntegration` fallback in `Sources/AgentSessionManager/Models/TracingService.swift`; verify `swift build` has no new warnings and `swift test` passes
- [x] 1.5 Change `runs-on` from `macos-15` to `macos-26` in `unit-tests.yml`, `ui-tests.yml`, `dependency-toolchain-compatibility.yml`, and `release.yml`, and change the `swift:6.1` container to `swift:6.2` in `swift-build-check.yml` and `format.yml` so the Linux jobs can read the new manifest; verify `grep -rnE "macos-15|swift:6\.1" .github/workflows` finds nothing and any workflow lint in `make lint` passes
- [x] 1.6 Update the floor in `documentation/how-to/install.md` and `documentation/how-to/download.md` to "macOS 26 or later", and the floor and toolchain text in `documentation/features/dev-build.md`, `AGENTS.md`, and the current-state lines of `AGENTIC_CONTROL.md`, following the Diataxis skill and leaving historical notes alone; verify `make docs-check` and `scripts/test-release-publishing.sh` pass
- [x] 1.7 Declare the new floor to updaters by adding `LSMinimumSystemVersion` `26.0` to `Info.plist` and to the `info` properties in `project.yml` so `make xcodeproj` keeps it and `sparkle:minimumSystemVersion` to each new appcast item in `scripts/update-appcast.sh`, and assert both in `scripts/test-release-publishing.sh`; verify `scripts/test-release-publishing.sh` passes and an appcast item generated with `scripts/update-appcast.sh` contains `<sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>`

## 2. Keep the placeholder scene from opening at launch

- [x] 2.1 Add a UI test in `UITests/` that launches the app and asserts the app has exactly one window, the main window, with no window whose title contains "Settings". The existing `testEmptyStateFlow` and `testSettingsDoesNotAutoOpen` pass on the buggy code, so this test guards the behavior directly. It passes on the old code when run through the Xcode-built test app, so it is a regression guard, and the real-app before and after in qa.md is the proof of the fix
- [x] 2.2 Extend that test to open the real Settings window with Cmd+,, quit the app with it open, relaunch, and assert only the main window exists, then press Cmd+, and assert a window titled "AgentSessionManager Settings" appears with its sections; verify it passes
- [x] 2.3 Add `.defaultLaunchBehavior(.suppressed)` and `.restorationBehavior(.disabled)` to the `Settings` scene in `Sources/AgentSessionManager/ContentView.swift`; verify the new UI test and `make test-ui-dev-launch` pass
- [x] 2.4 Run `make lint`, `make no-code-comments`, `make test-ui-dev-launch`, and `swift test`; verify all pass

## 3. Final validation with Computer Use on a Dev build

- [x] 3.1 Start a fresh owned Dev run with `scripts/recursive-development.sh start` from the implementation commit and confirm with Computer Use that the window title shows the Dev build for this branch and commit; verify with a screenshot of the title
- [x] 3.2 With Computer Use, take a screenshot immediately after launch; verify only the main window is visible and no "AgentSessionManagerDev Settings" window exists
- [x] 3.3 With Computer Use, press Cmd+, to open the real Settings window, quit the Dev app with it open, relaunch, and take a screenshot; verify only the main window is visible after the relaunch
- [x] 3.4 With Computer Use, press Cmd+, again and take a screenshot; verify the "AgentSessionManager Settings" window opens with its sections, and that pressing Cmd+, again closes it
- [x] 3.5 Stop the owned Dev run's PID and confirm the production app was untouched; record the screenshot links, commit, and run ID in the implementation pull request description
