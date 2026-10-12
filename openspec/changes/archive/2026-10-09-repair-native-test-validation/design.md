## Context

The app supports macOS 14 and later, owns its main window through AppKit, and uses SwiftUI for sheets and settings. The failing suite exposed mismatches between the generated Xcode dependency graph and SwiftPM, independent presentation booleans and their data, implicit dashboard scene creation, and terminal setup paths that omitted real behavior during testing. Loading and error regressions use a delayed Git checkout hook and a conflicting non-worktree directory in disposable repositories to exercise the real setup path. Issue #221 tracks the broader removal of fake evidence; this change repairs the flows encountered by the suite.

## Goals / Non-Goals

**Goals:** Make dependency resolution reproducible; exercise genuine pane, notification, and restart behavior; populate sheets on first opening; keep dashboards closed until requested; and produce reviewable Dev test evidence with explicit prerequisites.

**Non-Goals:** Complete every remaining fake-test migration, authenticate a harness, change provider alert semantics, upgrade packages, deploy a release, or change production account data.

## Decisions

### Share the resolved dependency graph

Copy the root `Package.resolved` into the generated Xcode workspace and require resolved versions for builds, tests, and captures. A temporary XcodeGen fixture checks fresh generation, stale-lock replacement, and missing-lock failure. Re-resolving a second graph would preserve the original failure mode.

### Use the normal runtime paths

Configure Agent Control even when a Dev test skips session restoration, and remove the existing `Tab.addPane` terminal bypass. Process launch stays deferred until the terminal view has a stable frame. Agent Control unit fixtures stop their status monitors during cleanup so background providers cannot contaminate subsequent trace captures. Connect the in-memory lifecycle fixture's receiving transport before the client sends initialization, because that transport discards messages while disconnected; the test still exercises real authenticated HTTP sessions and teardown. Bind notifications when `openShellPane` creates its real terminal, using the same handlers as harness panes. The unit regression sends OSC 777 through SwiftTerm's parser, while the UI flow types the real shell command and verifies its sidebar row.

### Present data and sheets together

Use item-driven presentation for pane settings and refresh selection. Queue refresh configuration until the confirmation sheet dismisses. Give the scrollback editor its selected limit at creation and keep its local draft inside the sheet. This removes independent state that could be absent or stale when SwiftUI first constructs the content, while retaining cancellation and reduction confirmations.

### Own auxiliary windows explicitly

Create each dashboard with a retained native window controller on an explicit menu or settings request. Disable restoration, pass the configured trace and invariant directories, and reuse a closed window within the same process. This provides the same behavior across the supported macOS versions without implicit SwiftUI window scenes. Record explicit opens and retain the launch invariant and relaunch regression.

### Expose real controls and targets

Expose the native terminal as an accessibility group with a pane-specific identifier. Keep nested sheet controls within accessibility containers, give bounded profile option lists stable identifiers, and give the status-line row menus stable identifiers. Make the icon row's full label a hit area. Tests locate native dialogs, scroll actual lists, and follow the confirmation and configuration flows instead of relying on obsolete identifiers or unpopulated sheets.

### Separate environment prerequisites from regressions

Keep Claude signed out as requested. Require a Cursor status result that can fetch live account details before asserting a real MCP connection; stored credentials alone are insufficient. Notification coverage uses a real merged PR after validating repository access through the configured GitHub CLI wrapper. Missing prerequisites report explicit skips and cannot supply screenshot evidence. Local validation hooks clear inherited Git command-configuration variables before invoking checks, preventing hook recursion in disposable Git fixtures. A shell regression makes actual nested commits and local pushes under both Git configuration mechanisms; command shims isolate that regression from native runtime evidence. The pre-push hook delegates to the canonical isolated Dev command.

## Risks / Trade-offs

Native dashboard controllers retain their content within a process, so directory settings take effect when a dashboard is first created; launch isolation and custom initial paths have regression coverage. Live service integration depends on account and network availability, so reported skips must remain visible in the handoff. Removing the terminal bypass can expose further real harness prompts; tests must handle their user flows or report a real prerequisite rather than add another fake. The broader issue #221 migration remains open.
