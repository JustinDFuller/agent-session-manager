---
layout: doc
title: Resize Sections and Panes
description: Adjust the space used by the tab bar, notification sidebar, and terminal panes.
diataxis_type: how-to
permalink: /documentation/user-guide/resize-sections-and-panes/
---

Resize the tab bar, notification sidebar, or pane grid to give the active work more room while keeping the same tabs and terminal sessions.

## Resize a section

Drag the divider below the tab bar to change its height. Drag the divider beside the notification sidebar to change its width. The neighboring area gives up the same amount of space, and the sidebar keeps its preferred width when you hide and show it.

To set section sizes directly, open **Settings → Panes → Layout** and use **Tab Bar Height** or **Notification Sidebar Width**. Choose **Reset Section Sizes** to restore the default 44-point tab bar and 240-point sidebar.

## Resize the pane grid

Drag a divider between pane rows or columns. The divider changes the two adjoining tracks across the grid; other tracks keep their sizes. Empty cells remain in their existing positions, and panes keep their running terminal sessions.

Double-click a divider or choose **Reset Resize ... Size** from its context menu to equalize just its two adjoining tracks. The tracks keep their combined space, and every other track stays the same. Choose **Reset Pane Sizes** from the grid context menu to reset all rows and columns in the current tab.

You can also resize from the active terminal with the default **⌘⌥ arrow** shortcuts. Each shortcut moves the divider by four points. Use **⌘⌥⇧ arrow** for a sixteen-point step. At an outside edge, the shortcut uses the divider on the other side of the active pane. If that divider reaches its limit, movement stops there.

In a middle column, the left and right shortcuts select the dividers on either side of that column, so either neighbor can give space to the active pane. To give space back across a divider, activate the pane on the other side and use the shortcut that points back across that same divider. The selected divider highlights while keyboard resizing is active.

## Change pane resize shortcuts

Open **Settings → Shortcuts → Pane Resizing** and select a shortcut button. Press a letter, number, or arrow key with Command and any optional modifiers. Press Escape to cancel capture. Choose **Disable** to stop that combination from resizing panes.

Each of the four directions has a normal and a larger-step shortcut. Settings rejects keys that conflict with another app or pane resize shortcut and keeps the previous assignment. Pane resize shortcuts act while a terminal pane has keyboard focus.

## Resize a pane's status line

Drag the thin handle above a pane's status line to change its visible height. The terminal keeps at least 64 points of space. If the pane becomes too short, the status line keeps its preferred height for later and shows a scrollable viewport; resizing the pane larger restores more of that preferred height. Double-click the handle or choose **Reset Resize status line for ... Size** from its context menu to return to content-based height. This changes only that pane and does not change the status-line rows saved in Settings or its profile.

## Related documentation

- [Keyboard Shortcuts]({{ '/documentation/user-guide/shortcuts/' | relative_url }})
- [Tabs and Panes]({{ '/documentation/user-guide/tabs-and-panes/' | relative_url }})
- [Focus Pane]({{ '/documentation/user-guide/focus-pane/' | relative_url }})
