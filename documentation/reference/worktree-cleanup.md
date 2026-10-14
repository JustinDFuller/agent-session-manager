---
layout: doc
title: Worktree Cleanup Reference
description: Settings, dialogs, buttons, and rules for worktree cleanup in Agent Session Manager.
diataxis_type: reference
permalink: /documentation/reference/worktree-cleanup/
---

A worktree is a separate checkout of a Git repository. A managed worktree is one Agent Session Manager created in the repository's `.agent-session-manager/worktrees` folder. Only managed worktrees are ever deleted.

## Settings

Find these in **Settings → Panes → Cleanup**.

| Setting | Values | Default | Effect |
| --- | --- | --- | --- |
| **Worktree Cleanup** | **Ask**, **Always Keep**, **Always Delete** | **Ask** | What happens to a managed worktree when you close its pane or tab. |
| **Delete Branch With Worktree** | On, off | On | Also deletes the local branch when a worktree is deleted. A branch with commits that are on no remote is deleted only after you confirm, and the default branch is never deleted. |
| **Clean Up Leftovers at Launch** | On, off | On | When the app starts, deletes leftover worktrees that no pane uses, that have no unsaved work, and that have not changed in 24 hours. |

## Unsaved work

These count as unsaved work:

- Modified files.
- Untracked files.
- Commits that are on no remote, including commits on a detached HEAD.

Files that Git ignores, such as build folders, do not count.

## Dialogs and alerts

| Title | When it appears | Buttons |
| --- | --- | --- |
| **Close Worktree Pane** | Closing a pane with a managed worktree while **Ask** is selected. | **Delete Worktree**, **Keep Worktree**, **Cancel** |
| **Close Tab With Worktrees** | Closing a tab that has managed worktrees while **Ask** is selected. | **Delete Worktrees**, **Keep Worktrees**, **Cancel** (**Delete Worktree** and **Keep Worktree** for one worktree) |
| **Worktree Has Unsaved Work** | A worktree to delete has unsaved work. | **Keep Worktree** (default), **Delete Anyway**, **Cancel** |
| **Worktrees Have Unsaved Work** | Several worktrees to delete have unsaved work. | **Keep Worktrees** (default), **Delete Anyway**, **Cancel** |
| **Worktree Cleanup Failed** | Git could not delete a worktree. | **OK** |
| **Worktree Kept** | A worktree was kept, for example because another pane is using it. | **OK** |
| **PR Merged** or **PR Closed** | A tracked pull request finished. | **Close Pane**, **Close Pane and Clean Up Worktree**, **Cancel** |
| **Delete Folder?** or **Delete Folders?** | Deleting leftover entries marked **Not a git worktree**. | **Delete Folder** or **Delete Folders**, **Cancel** |

**Delete Anyway** deletes the worktree even though it has unsaved work, and the unsaved work cannot be recovered. **Close Pane and Clean Up Worktree** shows the unsaved-work dialog the same way.

## Ways to close a tab

The tab close button, ⌘K, and **Delete This Tab** behave the same. A tab without managed worktrees closes without a dialog.

## Leftover Worktrees list

The list is in **Settings → Panes → Cleanup**.

| Item | Meaning |
| --- | --- |
| Name and repository | The worktree folder and the repository it belongs to. |
| Size | The disk space it uses, shown after the row appears. |
| Reason | Why it was not removed automatically, such as "It has unsaved work", "It is locked in git.", or "It changed within the last 24 hours." |
| **Not a git worktree** | A folder in a worktrees folder that Git does not know about. It is never deleted automatically. |
| **Delete Selected** | Deletes the selected entries with the same unsaved-work checks. |

The list shows "No leftover worktrees." when there is nothing to review.

## Launch cleanup conditions

A leftover is deleted at launch only when all of these are true:

- No open pane uses it.
- It has no unsaved work.
- It is not locked.
- It has not changed in the last 24 hours.

The sweep covers every repository you have opened a tab in. Anything that is not deleted stays in **Leftover Worktrees**.

## Related

- [Clean up worktrees]({{ '/documentation/user-guide/worktree-cleanup/' | relative_url }})
