---
layout: doc
title: Keyboard Shortcuts
description: Use and customize the shortcuts for common Agent Session Manager actions.
diataxis_type: reference
permalink: /documentation/user-guide/shortcuts/
---

Keyboard shortcuts open, close, and move through tabs and panes without leaving the terminal.

## Default shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘T | New Tab |
| ⌘P | New Pane in Current Tab |
| ⌘W | Close Active Pane |
| ⌘K | Close Active Tab |
| ⌘⇧S | Open Shell Here |
| ⌘R | Refresh Active Pane |
| ⌘1 through ⌘9 | Switch to a tab by position |

## Control-Return in a pane

On macOS 15 and later, while a terminal pane has keyboard focus, ⌃Return is sent to the program running in the pane instead of opening the pane's context menu. A program that has enabled extended keyboard reporting, such as Claude Code, receives it as a distinct Control+Enter, which Claude Code uses to send a queued message immediately. Other programs receive an ordinary Return. Right-click or Control-click a pane to open its context menu.

## Shortcut configuration

**Settings → Shortcuts** contains the configurable shortcut fields. Existing app shortcuts accept one key with their displayed modifiers, and the ⌘1 through ⌘9 tab-switching shortcuts are fixed.

The **Pane Resizing** group contains independently configurable shortcuts for four directions and two step sizes. Defaults use ⌘⌥ plus an arrow for a four-point step, and ⌘⌥⇧ plus an arrow for a sixteen-point step. Each binding accepts a letter, number, or arrow key with Command and optional modifiers. Press Escape during capture to cancel, or choose **Disable** to stop that combination from resizing panes. A key already assigned to another app or pane resize shortcut is rejected.

Pane-resize shortcuts act while a terminal pane has keyboard focus and move one shared grid divider at a time. The selected divider stays selected at its minimum or maximum; the shortcut does not continue by moving another divider. Status-line height is controlled with the handle above the status line.

| Action | Default | Step |
| --- | --- | --- |
| Resize Left | ⌘⌥← | 4 points |
| Resize Right | ⌘⌥→ | 4 points |
| Resize Up | ⌘⌥↑ | 4 points |
| Resize Down | ⌘⌥↓ | 4 points |
| Resize Left (Larger Step) | ⌘⌥⇧← | 16 points |
| Resize Right (Larger Step) | ⌘⌥⇧→ | 16 points |
| Resize Up (Larger Step) | ⌘⌥⇧↑ | 16 points |
| Resize Down (Larger Step) | ⌘⌥⇧↓ | 16 points |

## Terminal editing

⌘C and ⌘V copy and paste in the active pane. A pane's context menu contains the same **Copy** and **Paste** actions.

## Related documentation

- [Tabs and Panes]({{ '/documentation/user-guide/tabs-and-panes/' | relative_url }})
- [Resize Sections and Panes]({{ '/documentation/user-guide/resize-sections-and-panes/' | relative_url }})
- [Focus Pane]({{ '/documentation/user-guide/focus-pane/' | relative_url }})
- [Supported Tools]({{ '/documentation/reference/supported-tools/' | relative_url }})
