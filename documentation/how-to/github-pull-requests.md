---
layout: doc
title: GitHub Pull Requests
description: Show pull-request status and receive attention when a tracked pull request changes state.
diataxis_type: how-to
permalink: /documentation/user-guide/github-pull-requests/
---

## What it is

GitHub pull-request tracking finds the pull request for a pane's current Git branch and can show its status in the pane's status line. It can also notify you when a tracked pull request is merged or closed without merging.

## Why you might use it

Track build and review progress without leaving the pane where you are working.

## Before you start

Install the GitHub CLI (`gh`) and authenticate it in the shell selected in **Settings → Panes → Terminal**. The pane must use a Git branch with a GitHub pull request.

## How to use it

### Show pull-request status

1. Open **Settings → Status Line**.
2. In **GitHub PR Tracking**, enable **Track pull requests**.
3. Add **PR** to a status-line row with **Add Item**.

The **PR** item shows the pull-request number and state when one is found for the pane's current branch. While the first check is running it shows **Checking…**; a successful check with no pull request shows **No PR**.

### Configure state notifications

1. Open **Settings → Notifications**.
2. In **GitHub PR**, enable **PR Merged Notifications** or **PR Closed Notifications**.
3. Keep **Banner Notifications** enabled if you also want macOS banners.

When a tracked pull request changes to merged or closed, the app can add a sidebar notification and show a macOS banner. Selecting the notification opens the related pane and presents the available action prompt.

At the action prompt, choose **Close Pane** to remove the pane and keep its Git worktree. Choose **Close Pane and Clean Up Worktree** when the pane uses a worktree managed by Agent Session Manager and you also want that worktree removed. Choose **Cancel** to leave the pane open.

## What you should see

The **PR** item can show **Checking…**, a current pull request, **No PR**, or **Unavailable** when the pane has no supported GitHub remote or branch, or when its latest check failed. A successful query that finds no pull request shows **No PR** without an error; an authentication failure shows an error in the popover and offers **Retry**. Click the item to read the latest check status and the reason for an unavailable result. If a refresh fails after a pull request was found, the prior result remains visible with a **Stale** label.

## If it does not work

- If the PR item reports an error, click it and choose **Retry** after resolving the cause. The authentication message reads **GitHub CLI authentication failed. Authenticate the configured `gh`, then retry.** Restore authentication for the account you already use in that shell, then retry. Selecting **Retry** refreshes the shell context and query without restarting the pane.
- Confirm that `gh` is installed and authenticated in the configured shell. Running `gh auth status` there reports the current CLI authentication without switching accounts.
- Confirm that **Track pull requests** is enabled and that **PR** is in a status-line row.
- Confirm that the pane's current branch has a GitHub pull request.
- If banners do not appear, allow notifications for Agent Session Manager in **System Settings → Notifications**.

## Related tasks

- [Status Line]({{ '/documentation/user-guide/status-line/' | relative_url }})
- [Notifications]({{ '/documentation/user-guide/notifications/' | relative_url }})
- [Project Isolation]({{ '/documentation/user-guide/project-isolation/' | relative_url }})
