# Worktree Cleanup

Agent Session Manager removes worktrees it created through one cleanup pipeline. The pipeline checks for unsaved work, removes the worktree, optionally deletes its local branch, and reports every failure. The pane close flow, the tab close flow, the pull request alert, the agent-control `panes_delete` and `tabs_delete` tools, the launch sweep, and the Leftovers list all use it (`Controllers/WorktreeCleanup.swift`).

## Managed vs. external worktrees

- **Managed worktrees** are created by Agent Session Manager under `<repo>/.agent-session-manager/worktrees/<name>`. Only these are eligible for cleanup. The launch sweep and the Leftovers list also look in the legacy `<repo>/.tree` folder.
- **External worktrees** are pre-existing checkouts that were listed by `git worktree list` when you attached to them. The app never removes these.

## The pipeline

1. **Assess** (`WorktreeCleanup.assess`) reports modified files, untracked files, commits that are on no remote (including on a detached HEAD), the branch name, whether the worktree is locked, and whether another pane uses the checkout. Git-ignored files such as `.build` are not unsaved work.
2. **Remove** (`WorktreeCleanup.remove`) runs `git worktree remove`, with `--force` only after you choose Delete Anyway, then prunes stale registrations. When **Delete Branch With Worktree** is on it also deletes the local branch with `git branch -D`, except that a branch with commits on no remote is deleted with `-d` unless you chose Delete Anyway, so git refuses to drop unpushed commits on its own. It never deletes the default branch or a branch checked out in another worktree.
3. **Report** returns `deleted`, `kept` with a reason, or `failed` with git's message. Failures are never silent, and a failed git command records an error status in the trace.

Deletion is limited to the managed folders. A checkout outside them, such as one in `/tmp`, is never removed.

## Closing a pane

Closing a pane with ⌘W or the pane's close button follows the **Worktree Cleanup** setting in Settings → Panes → Cleanup:

- **Ask** (default) shows **Delete Worktree**, **Keep Worktree**, and **Cancel**.
- **Always Keep** closes the pane and keeps the worktree.
- **Always Delete** runs the pipeline without asking.

The pane closes first. Before removal the app waits, for at most 2 seconds, for the pane's processes to exit.

If another open pane, such as a shell pane, uses the same checkout, the worktree is kept and an alert says "Another pane is still using it."

The pull request alert's **Close Pane and Clean Up Worktree** button uses the same pipeline as Delete Worktree. **Close Pane** keeps the worktree.

## Unsaved work

When the assessment finds modified files, untracked files, or commits on no remote, deleting stops at the **Worktree Has Unsaved Work** dialog. It lists each finding, for example "1 modified file" or "1 commit not on any remote on a detached HEAD". The buttons are:

- **Keep Worktree** (default) closes the pane and leaves the worktree.
- **Delete Anyway** removes it with `--force`. The branch is deleted too when the branch setting is on, and the dialog says so when the branch has unpushed commits.
- **Cancel** abandons the close.

This applies to Ask, Always Delete, and the pull request alert. With several worktrees at risk the title is **Worktrees Have Unsaved Work** and the keep button is **Keep Worktrees**.

## Closing a tab

The tab close button, ⌘K, and **Delete This Tab** share one close request (`WorktreeCloseFlow`). It assesses every managed worktree in the tab. A tab with no managed worktrees closes without a dialog.

With **Ask**, one **Close Tab With Worktrees** dialog covers the whole tab with **Keep Worktrees**, **Delete Worktrees**, and **Cancel**. **Always Keep** and **Always Delete** skip it. Worktrees without unsaved work are removed, and only the ones at risk reach the unsaved-work dialog.

## Failures and kept worktrees

When any worktree is kept or fails, one alert lists each one as "Kept <name>: <reason>" or "Could not delete <name>: <reason>". The title is **Worktree Cleanup Failed** when git failed and **Worktree Kept** otherwise. A locked worktree is an example of a git failure.

## Settings

All three are in **Settings → Panes → Cleanup**. Each is stored in a JSON file in `~/Library/Application Support/agent-session-manager/`.

| Setting | Default | File |
| --- | --- | --- |
| Worktree Cleanup | Ask | `worktree-cleanup.json` |
| Delete Branch With Worktree | On | `delete-branch-with-worktree.json` |
| Clean Up Leftovers at Launch | On | `clean-up-leftovers-at-launch.json` |

Reset App State clears all three, plus `known-repositories.json`.

## Launch cleanup

Worktrees left by earlier versions, or by a pane closed while the app was not running, are found by a sweep (`WorktreeLeftovers.sweep`). `known-repositories.json` records every repository root that has had a tab, added when a tab is created or restored. Missing folders are dropped, and the first launch seeds the list from the restored tabs.

When **Clean Up Leftovers at Launch** is on, the sweep runs once in the background after session restore, with no dialogs. In each known repository it prunes stale registrations, then removes a worktree only when all of these hold:

- No open pane uses it.
- It is clean and every commit is on a remote.
- It is not locked.
- Its git administrative `HEAD` and `index` files have not changed for 24 hours.

With **Delete Branch With Worktree** on, the branch goes with it. Each decision is recorded in the trace as `worktree.leftover.removed`, `worktree.leftover.skipped` (with the reason), or `worktree.leftover.failed`. Tracing records only when Debug tracing is enabled.

## Leftovers list

**Settings → Panes → Cleanup → Leftover Worktrees** lists everything in the managed folders that no pane uses: the repository name, the folder name, its size (loaded after the row appears, off the main thread), and why it was kept, for example "It changed within the last 24 hours." Folders git does not know about, such as the leftovers Xcode recreates, are marked **Not a git worktree**. **Refresh** rescans.

**Delete Selected** sends selected worktrees through the pipeline, so the unsaved-work dialog applies. Selected unregistered folders need a separate **Delete Folder** confirmation, and only folders directly inside a managed worktrees folder can be deleted. The sweep never deletes unregistered folders.

## Agent control

`panes_delete` and `tabs_delete` use the pipeline and report an outcome per worktree: `kept` (with the reason), `deleted`, or `failed`. A worktree with unsaved work is kept, and agent control cannot force a deletion. A mutation with a failed worktree has status `partial_failure`. Worktrees in use by another pane are kept.

## Session restore interaction

If you delete a worktree and later relaunch the app, the pane for that worktree will **not** be restored because the checkout directory no longer exists on disk (see session restore rules in [worktree-creation.md]({{ '/documentation/features/worktree-creation/' | relative_url }})).
