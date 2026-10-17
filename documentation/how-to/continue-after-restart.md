---
layout: doc
title: Continue After Restart
description: Reopen saved tabs and panes after Agent Session Manager restarts.
diataxis_type: how-to
permalink: /documentation/user-guide/continue-after-restart/
---

## What it is

Agent Session Manager saves open tabs and agent panes so it can restore them after the app is relaunched. A pane is restored only when its Git worktree still exists on disk.

## Why you might use it

Session restoration lets you close the app or restart your Mac without rebuilding your project layout manually. The **Continue on Restart** setting can also resume supported agent conversations.

## Before you start

Keep the Git worktrees used by your panes on disk. If you delete a worktree, the related pane cannot be restored, although its branch remains available in Git.

## How to use it

1. Open **Settings**.
2. Select **Panes**.
3. In the **Cleanup** section, enable or disable **Continue on Restart**.
4. Quit and reopen Agent Session Manager.

The app restores tabs and panes whose working copies still exist. With **Continue on Restart** enabled, Claude Code and Cursor use `--continue`, OpenCode uses its available session-resume behavior, and Codex attempts to resume the exact foreground conversation recorded for each pane. Codex panes without a recorded conversation start fresh; if a saved conversation is unavailable, the pane offers **Retry** or **Start New Conversation**.

For a Codex pane, **Refresh and Continue** resumes that pane's exact foreground conversation when it is available. **Refresh with New Settings…** starts a fresh Codex conversation. If continuation is unavailable, choose **Retry** to check again or **Start New Conversation** to continue in a new session.

## What you should see

The saved tabs reappear when their project directories can be restored, with each restorable pane starting in its saved Git worktree. Panes whose project directory or worktree is missing are left out of the restored session.

## If it does not work

- If a tab or pane is missing, confirm that its project directory and Git worktree still exist.
- If the project path contains spaces and the tab does not return, update to a build containing the current session-restore fix or recreate the tab.
- If the pane reopens but the conversation does not resume, check **Settings → Panes → Continue on Restart** and the selected tool's own session behavior.
- If Codex offers recovery for a saved conversation, confirm that the configured shell's exported `CODEX_HOME` points to the Codex data containing that conversation. The app checks this shell value first, then the launch environment's `CODEX_HOME`, then `~/.codex`.
- If you intentionally deleted the worktree, create a new pane from the relevant branch or worktree.

## Related tasks

- [Project Isolation]({{ '/documentation/user-guide/project-isolation/' | relative_url }})
- [Worktree Cleanup]({{ '/documentation/user-guide/worktree-cleanup/' | relative_url }})
- [Tabs and Panes]({{ '/documentation/user-guide/tabs-and-panes/' | relative_url }})
