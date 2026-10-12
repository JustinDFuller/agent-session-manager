# Tab and Pane Reordering

## What

Tabs in the tab bar can be dragged left or right to change their order. Panes within a tab can be dragged to change their position in the grid.

## How

**Tabs:** Click and hold the tab label area and drag it horizontally to the desired position. A highlighted border indicates the drop target. Release to drop. The close (×) button is not a drag handle.

**Panes:** Click and hold the pane header label area and drag it to another pane's position within the same tab. A highlighted border indicates the drop target. Release to drop. The header label area shows an open-hand cursor and is the only drag handle. The close (×) button and terminal body are intentionally excluded so closing, text selection, and copy/paste work normally.

Both operations persist across app relaunches.

## Scope

Pane reordering is within a single tab only. Moving a pane to a different tab is not supported.

Pane-grid proportions belong to grid positions, so reordering panes does not move the saved column or row sizes with an individual pane. Adding or removing panes resets only an axis whose number of tracks changes; the other axis retains its proportions.
