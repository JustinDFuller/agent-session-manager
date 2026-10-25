---
layout: doc
title: Status Line
description: Customize the information shown at the bottom of each terminal pane.
diataxis_type: how-to
permalink: /documentation/user-guide/status-line/
---

## What it is

The status line is the information bar at the bottom of a pane. It can show session details, model and usage information, duration, worktree changes, and other facts available for the selected tool.

## Why you might use it

Choose the information that helps you scan several panes quickly without interrupting the terminal session.

## Before you start

Open **Settings** and select **Status Line**. The global editor lists the status facts available to the app. Facts that are not supported by a pane's selected tool are filtered out when that pane renders its status line. A profile's custom status line filters its **Add Item** menu to that profile's harness.

## How to use it

1. Open **Settings → Status Line**.
2. Choose the display style, item alignment, and percentage display options in **Display**.
3. Add or remove rows with **Add Row** and the row controls.
4. Within a row, choose **Add Item** and select the facts you want to see.
5. Use the up and down controls to reorder rows and the minus controls to remove items.
6. Optionally choose **Add Custom Field** to run a command that supplies a value for the status line.
7. Open **SF Symbol** and type a label, keyword, or symbol name to filter the suggestions. If an SF Symbol available on this version of macOS is not suggested, enter its exact name and choose **Use exact symbol name “<symbol name>”**.
8. Open **Harnesses** and select every harness that should run the field. The checklist stays open while you make selections; choose **Done** or click outside it when finished. New custom fields target all harnesses by default.
9. Select **Add** or **Save**. Reopen a saved field without changing it and choose **Run Now** to run the saved command in matching panes that use the saved configuration and selected harness.
10. Global Status Line changes are saved as you edit the layout. In a profile editor, choose the profile’s **Save** button when you are finished.

Facts and custom fields that are not supported by a pane’s harness are omitted. A supported fact with no current value may show a dash until data is available.

Custom fields in a profile status-line override are independent from the global status line. When **Custom Status Line** is enabled for a profile, its panes use that profile’s saved custom field command; otherwise they inherit the global command. Run **Run Now** from the matching saved configuration when you want to refresh those panes.

### Show pull-request status

In **GitHub PR Tracking**, enable **Track pull requests** to show the current pull request status for a pane’s Git branch. This requires the GitHub CLI (`gh`) to be installed and authenticated in the configured shell. The same section controls polling and background refresh.

The PR item shows **Checking…** while a query is running and **No PR** after a successful query finds none. When a query fails, click the item for the error and **Retry**. If a previous PR result exists, it remains visible and is marked **Stale** until a successful refresh. Authentication errors tell you to authenticate the configured CLI before retrying.

Use **PR Polling Interval** to control how often foreground checks run, **Request Timeout** to limit an in-flight request, and **Background Refresh** to keep checking while the app is unfocused. **Background Polling Interval** controls the cadence for those background checks.

## What you should see

The configured rows appear at the bottom of each applicable terminal pane. The order in Settings matches the order in the pane, and custom fields refresh according to their configured interval.

![Agent Session Manager Status Line settings]({{ '/assets/img/docs/settings-status-line.png' | relative_url }})

_Status Line settings control the layout and pull-request tracking options._

## If it does not work

- If an item is missing from **Add Item**, it may not be supported for the selected harness or may already be in a row.
- If the status line is not visible, add at least one row and one item in **Settings → Status Line**.
- If a custom field does not produce a value, check that its harness selection includes the pane's harness, that the field is saved, and that the command, refresh interval, and timeout are correct. A profile status line can use a different saved command from the global status line.
- If **Run Now** starts a command but the displayed value does not change, check whether the command uses its own cache or refresh interval. **Run Now** starts the command immediately but does not bypass a cache policy implemented by the command.
- If an exact SF Symbol name is not available on this version of macOS, select a suggested icon instead.
- If pull-request status is missing, confirm that `gh` is installed and run `gh auth status` in the configured shell. This checks its current authentication without changing accounts.
- If the PR item reports an error, open it, resolve the displayed cause, then choose **Retry**.

## Related tasks

- [Profiles]({{ '/documentation/user-guide/profiles/' | relative_url }})
- [Agent Tools]({{ '/documentation/user-guide/agent-tools/' | relative_url }})
- [Tool Options]({{ '/documentation/user-guide/tool-options/' | relative_url }})
