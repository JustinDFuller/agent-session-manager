---
layout: doc
title: Worktree Cleanup
description: Delete finished worktrees safely when you close a pane or tab, and review the ones left behind.
diataxis_type: how-to
permalink: /documentation/user-guide/worktree-cleanup/
---

## What it is

Worktree cleanup removes the Git worktrees that Agent Session Manager created for your tasks, so they stop using disk space. It applies to worktrees managed by the app, not to every Git directory on your Mac. Before anything is deleted, the app checks for unsaved work and asks you first.

## Before you start

Check that the pane uses a worktree created or managed by Agent Session Manager. An unmanaged existing worktree is never removed. An existing worktree becomes managed when you choose **Manage** in the existing-worktree prompt.

## Choose cleanup behavior

1. Open **Settings**.
2. Select **Panes**.
3. In the **Cleanup** section, find **Worktree Cleanup**.
4. Choose **Ask**, **Always Keep**, or **Always Delete**.
5. Leave **Delete Branch With Worktree** on to delete the local branch when its worktree is deleted, or turn it off to keep branches.
6. Leave **Clean Up Leftovers at Launch** on to let the app remove safe leftovers each time it starts, or turn it off to review them yourself.

See the [worktree cleanup reference]({{ '/documentation/reference/worktree-cleanup/' | relative_url }}) for what each setting does.

## Close a pane and decide what happens to its worktree

1. Close the pane with ⌘W or its close button.
2. When **Ask** is selected, choose **Delete Worktree**, **Keep Worktree**, or **Cancel**.

![Managed worktree cleanup prompt in Agent Session Manager]({{ '/assets/img/docs/worktree-cleanup-alert.png' | relative_url }})

_Closing a managed pane gives you an explicit choice to keep, delete, or cancel._

## Handle unsaved work

If the worktree has modified files, untracked files, or commits that are on no remote, the **Worktree Has Unsaved Work** dialog lists them.

- Choose **Keep Worktree** to close the pane and leave the worktree as it is.
- Choose **Delete Anyway** to delete the worktree and its unsaved work. This cannot be undone.
- Choose **Cancel** to leave the pane open.

![Worktree Has Unsaved Work dialog listing one modified file]({{ '/assets/img/docs/worktree-unsaved-work-dialog.png' | relative_url }})

_The dialog names the findings, and Keep Worktree is the default._

## Close a tab that has worktrees

1. Close the tab with its close button, ⌘K, or **Delete This Tab**.
2. In **Close Tab With Worktrees**, choose **Delete Worktrees**, **Keep Worktrees**, or **Cancel**.

Worktrees without unsaved work are deleted. A worktree with unsaved work still shows the unsaved-work dialog.

![Close Tab With Worktrees dialog for a tab with two worktrees]({{ '/assets/img/docs/worktree-tab-close-dialog.png' | relative_url }})

_One dialog covers every managed worktree in the tab._

## Review and delete leftover worktrees

1. Open **Settings**, select **Panes**, and find **Leftover Worktrees** in the **Cleanup** section.
2. Read the reason shown under each entry, such as "It has unsaved work" or "It changed within the last 24 hours."
3. Select the entries you want to remove.
4. Choose **Delete Selected**.
5. Answer the unsaved-work dialog, or the **Delete Folder** confirmation for an entry marked **Not a git worktree**.

![Leftover Worktrees list in Settings with the reason each one was kept]({{ '/assets/img/docs/worktree-leftovers-list.png' | relative_url }})

_Each leftover shows its repository, size, and why it was not removed automatically._

## What you should see

The pane or tab closes. Deleted worktrees disappear from disk, and their local branches go with them when **Delete Branch With Worktree** is on. If anything was kept or could not be deleted, an alert names each worktree and the reason.

## If it does not work

- If **Worktree Cleanup Failed** appears, the message includes Git's reason. For example, a locked worktree must be unlocked first.
- If **Worktree Kept** says "Another pane is still using it.", close the other pane that uses the same worktree, then delete it from **Leftover Worktrees**.
- If no dialog appears, the pane may use an unmanaged existing worktree, or cleanup may be set to **Always Keep**.
- If a deleted task does not return after relaunch, create a new pane from its branch or worktree name.
- If you need the files later, choose **Keep Worktree** before closing the pane.

## Related tasks

- [Project Isolation]({{ '/documentation/user-guide/project-isolation/' | relative_url }})
- [Continue After Restart]({{ '/documentation/user-guide/continue-after-restart/' | relative_url }})
- [Tabs and Panes]({{ '/documentation/user-guide/tabs-and-panes/' | relative_url }})
