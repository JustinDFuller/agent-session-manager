# Proposal

## Why

Issue [#187](https://github.com/JustinDFuller/agent-session-manager/issues/187) requests control over space allocated to tabs, notifications, status information, and terminals. Fixed dimensions and equal pane sizes prevent people from giving their current task more room while retaining the tab-and-pane workflow.

## What Changes

- Add draggable boundaries below the tab bar, beside the notification sidebar, between pane rows and columns, and above each available status line.
- Define resizing as equal space exchanged between adjoining regions; move only the selected boundary, stop at usable size limits, and preserve the existing automatic grid and empty cells.
- Keep status-line fonts and configured rows unchanged; resize a scrollable viewport within its pane.
- Remember tab-bar height and notification-sidebar width globally, grid proportions per tab, and status-line height per pane across relaunches.
- Support native resize cursors, accessible adjustment, clickable size controls, and explicit reset actions.
- Add configurable directional shortcuts that resize the active pane while terminal input focus stays in place; move the divider on the requested side, falling back to the opposite divider at an outside edge.
- Default to Command–Option–arrows for four-point adjustments and Command–Option–Shift–arrows for sixteen-point adjustments, with key repeat, shared-track limits, and visible divider feedback.
- Expose separate normal and larger-step bindings for all four directions in Settings → Shortcuts, with key capture, disabling, conflict checks, and global persistence.
- Preserve custom proportions through window resizing, pane reordering, and focus transitions; reset only an axis whose track count changes.

## Capabilities

### New Capabilities

- `section-resizing`: Space redistribution, resize interactions, content reachability, saved dimensions, and layout recovery for the existing tab-and-pane interface.

### Modified Capabilities

None. The existing `native-pane-interactions` requirements remain compatible; they cover sheets, terminal attention, icon selection, and explicit dashboard opening rather than section dimensions.

## Impact

The implementation will affect root layout, pane grid geometry, status-line presentation, app settings, tab and pane models, and session/settings persistence. It will add unit and real-flow Dev UI coverage, resize telemetry, internal feature documentation and its skill, and user-facing resize instructions. Existing SwiftUI, AppKit, and SwiftTerm capabilities are sufficient; no new dependency or public service API is required.

## Deliberately Out of Scope

Independent splits within each row, a free-form split tree, filling existing empty grid cells, changes to pane capacity, cross-tab pane movement, drag-to-collapse, font scaling, automatic status-item reflow, harness invocation changes, terminal restart behavior, prefix-key sequences, pane-size shortcuts for global sections or status viewports, replacement of existing non-resize shortcut editors, and changes to release or merge-gate policy are excluded. This proposal PR contains planning artifacts only; implementation, real UI evidence, and the eventual archive transition belong to later work after review.
