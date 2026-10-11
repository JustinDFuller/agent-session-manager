# Section Resizing

Section resizing allocates space across the existing tab bar, notification sidebar, pane grid, and each pane's status viewport. It preserves the automatic pane grid, terminal identities, pane order, and empty cells while each divider exchanges space only with its adjacent region or track.

This guide describes the approved complete feature. The foundations layer provides geometry and compatible preferences; later implementation layers provide user controls, grid interactions, and status resizing.

## Ownership

Tab-bar height and notification-sidebar width belong to `LayoutSettings` and persist globally in `layout-settings.json`. Resize shortcuts are stored beside those dimensions as eight independent bindings; missing or malformed entries use their defaults, explicit null entries disable one action, and conflicts disable every resize action involved while preserving existing app shortcuts.

Column and row proportions belong to each `Tab` as normalized positive weights and persist in `sessions.json`. The weights stay attached to grid positions during pane reordering. Adding, removing, or restoring panes resets only an axis whose track count changed; the other axis keeps its saved proportions. Effective track sizes are calculated from the saved weights and current available space without overwriting those preferences.

Status viewport height belongs to each `Pane` and persists with that pane's identity. An unset value means content-based sizing. Changing or resetting a pane's status height does not alter another pane, profile settings, or the configured status rows.

## Allocation Rules

Each divider exchanges equal space between its two adjacent regions. A positive movement grows the upper or left region and reduces the lower or right region. A grid divider changes the same shared track across all rows or columns; every unrelated track keeps its size. Double-clicking a grid divider or choosing its local reset command equalizes only that adjacent pair, preserving the pair's combined extent and every other track. The grid-wide reset equalizes every row and column. A three-column boundary does not push the second boundary when the neighboring track reaches its minimum.

Preferred grid weights scale with the available extent after padding and gutters. If a track would fall below its minimum, the track is held at that minimum and remaining space is divided among tracks that still have room to shrink. Saved weights remain unchanged while the window is constrained, so the preferred allocation returns when space grows.

The current proposed bounds are 44–96 points for the tab bar, 160–480 points for the notification sidebar, at least 160 points for each pane column, 64 points for terminal content, and 24–256 points for an explicitly sized status viewport. The 8-point status resize handle is also reserved outside the status viewport. Tab-bar minimums also account for the measured controls; root sections are further constrained by the active grid's minimum size. An empty tab reserves a 160-by-64-point body, while Focus Pane mode uses the focused pane's minimum rather than the hidden grid's minimum. Status content scrolls inside a constrained viewport instead of forcing the pane taller than the available window.

## Spatial Shortcuts

Directional pane-resize actions select a boundary beside the active pane. Left and Up select the previous track boundary when it exists; Right and Down select the following boundary when it exists. At an outer edge, the action selects the opposite adjoining boundary. It keeps that selected boundary when movement reaches a limit and never switches to another divider to find additional space. Empty cells participate through their shared row and column tracks.

The default bindings use Command–Option plus an arrow for a four-point step and Command–Option–Shift plus an arrow for a sixteen-point step. Each direction and step size is configured independently. Resizing applies to grid rows and columns only; the shortcuts do not change global sections or status viewport heights.

## Persistence and Recovery

Global dimension settings use atomic writes to `layout-settings.json`; tab proportions and pane status heights use atomic session writes to `sessions.json`. Invalid global scalars, shortcut entries, grid axes, and status heights recover independently so an invalid preference does not discard valid sibling values or the rest of a session. Resetting global sections restores only the tab-bar and sidebar defaults, resetting pane sizes equalizes the current tab's rows and columns, and resetting one status viewport returns only that pane to content-based sizing.

## Telemetry

Resize records use bounded section, axis, input source, before/after allocation, and result values. Grid records include tab identity; status records include pane and owning-tab identity. Active-pane shortcut records also include the selected boundary, direction, and normal or larger-step action. Save failures surface through nonmodal app UI and emit `layout.resize.persistence_failed`; pointer-move samples and terminal contents are never recorded.
