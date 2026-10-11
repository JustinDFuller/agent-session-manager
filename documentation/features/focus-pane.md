# Focus Pane Mode

Focus Pane mode enlarges one terminal pane inside its tab so long output is easier to read. The macOS window, tab bar, active tab, terminal process, scrollback, pane status line, and pane header remain intact.

## Using Focus Mode

Focus mode is available when a tab has at least two panes:

1. Double-click a pane header, or right-click the pane and choose **Focus This Pane**.
2. The selected pane fills the tab body. Sibling panes remain mounted but are hidden from display, input, and accessibility.
3. Click **Show All Panes**, double-click the focused pane header, or right-click and choose **Show All Panes** to restore the grid.

The focused pane header keeps the activity indicator, pane name, and close button. A small bordered **Show All Panes** button with a grid icon appears immediately before close. Pane dragging is disabled while focused.

Focus Pane keeps the selected pane's status-line resize handle available. Pane-grid dividers and grid-resize shortcuts are hidden or inactive while focused; returning to **Show All Panes** restores the saved grid proportions.

The tab bar remains visible so tabs can still be switched. The native macOS green traffic-light button also remains unchanged: it controls the app window, while Focus Pane mode controls the layout inside one tab.

## Automatic Grid Restoration

Agent Session Manager restores the pane grid when:

- A new pane is created.
- A shell pane is opened.
- The focused pane is closed.
- An in-app or macOS notification navigates to a pane.

Canceling a managed-worktree cleanup prompt leaves the focused pane open and focused.

## Settings

Open **Settings → Panes → Focus Mode**:

| Setting | Default | Behavior |
|---|---|---|
| When Switching Tabs | Remember Focus | Return to a tab's focused pane during the current app run. Choose **Show All Panes** to restore the grid whenever you leave a tab. |
| Hide Notification Sidebar | On | Hide the notification sidebar while a pane is focused so the terminal receives the full tab-body width. |

Settings are persisted in `focus-mode-settings.json`. The currently focused pane is intentionally transient and is not written to `sessions.json`, so relaunch always starts with normal grids.

## Telemetry

Focus transitions emit `pane.focus_mode.changed` with pane and tab IDs and names, `state` (`focused` or `grid`), and a bounded `reason`.
