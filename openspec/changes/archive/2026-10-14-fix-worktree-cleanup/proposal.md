# Proposal

## Why

Worktrees that Agent Session Manager creates are not reliably removed, and they fill the disk. On 2026-10-12 the Data volume was at 100% with about 3 GB of stale worktrees, two of them holding SwiftPM `.build` folders of 8.2 GB and 1.8 GB. The app's own traces and the repositories' git state show three causes:

- **A failed delete is silent.** Closing a pane removes it from the window first and then runs `git worktree remove` in the background with the error discarded. Git refuses to remove a worktree that has modified or untracked files, so the worktree stays with no message. On 2026-10-12 at 09:01 the app ran the removal for `feat-issue-187-drag-to-resize`; the worktree is still registered with 25 changed files and 3 commits that are on no remote.
- **Closing a tab never cleans up.** The tab close button, ⌘K, and the Delete This Tab menu item close every pane without consulting the Worktree Cleanup setting. Four closed tabs (`ban-code-comments`, `ban-fixed-width-prose`, `justindfuller.com`, and `vector-arena`) left app-created worktrees behind, most of them clean and fully pushed.
- **Branches are never deleted.** Nothing removes the local branch, which leaves 276 local branches in this repository.

Nothing finds worktrees that no pane references any more, so leftovers from before this change stay until someone removes them by hand.

## What Changes

- Closing a tab follows the Worktree Cleanup setting for every managed worktree in that tab, with one dialog that covers the whole tab when the setting is Ask.
- Before any managed worktree is deleted, the app checks for changed files, untracked files, and commits that are on no remote, including on a detached HEAD. When it finds any, a dialog lists them, with Keep Worktree as the default and Delete Anyway as the alternative. This applies to Ask, Always Delete, the pull request merged or closed dialog, and agent-control deletion.
- A removal that fails is never silent. The app shows the worktree name and the reason, and records the failure in its traces.
- A new setting, Delete Branch With Worktree, is on by default. A successful worktree deletion also deletes the local branch. If the branch has commits that are on no remote, the warning says so before you confirm.
- The app keeps a worktree that another open pane still uses, such as a shell pane opened on the same checkout, and says why.
- A new setting, Clean Up Leftovers at Launch, is on by default. At launch the app removes leftover managed worktrees that are provably safe to delete, in every repository it has had a tab for, and prunes stale git registrations.
- Settings → Panes → Cleanup lists the leftovers that were not removed, with their size and the reason each was kept, and deletes the ones you select under the same warnings. When the launch setting is off, it lists every leftover.
- The agent-control `panes_delete` and `tabs_delete` tools use the same checks and report the outcome for each worktree.

## Capabilities

### New Capabilities

- `worktree-cleanup`: When Agent Session Manager deletes the worktrees it created, how it protects unsaved work, how it reports failure, how branches are handled, and how leftovers are found and removed.

### Modified Capabilities

None. No existing specification covers worktree cleanup.

## Impact

The implementation will affect the pane and tab close flows, the cleanup routine on the tab model, the Cleanup section of Settings, settings persistence and the saved list of repositories, the launch sequence, and agent-control pane and tab deletion. It will add unit tests that use real temporary git repositories, Dev UI flows that use the real sheets and dialogs, the worktree cleanup feature documentation and its skill, and the public cleanup documentation page. No new dependency is needed. Existing sessions and settings files stay compatible because every new setting has a default.

## Deliberately Out of Scope

- Worktrees in `/private/tmp`, `~/.codex/worktrees`, and `.claude/worktrees`, which agents and other tools create.
- Worktrees the app attached to but does not manage.
- Removing a worktree over agent control with a forced delete.
- Cleaning Xcode, SwiftPM, or other caches outside managed worktrees.
- Automatically deleting folders that git does not know as worktrees, such as the `milestone-*` folders that Xcode recreated in `routine`. The Settings list shows them and you decide.
- Changing how worktrees are created, named, or restored.

## Open Items For Review

- Reproduction in the running app. The causes above come from the app's traces, repository state, and the close paths in the source. The in-app reproduction runs during implementation validation and covers three hypotheses that the specification already accommodates: ignored build folders are removed with the worktree, a running process in the folder can make removal fail, and a detached HEAD with local-only commits is removed without a warning today.
- The launch cleanup age threshold. The specification sets it at 24 hours; this is the main number for the reviewer to confirm.
- Agents also create worktrees inside the managed folder (for example, nine `feat-openspec-final-archive-*` worktrees on 2026-09-07). The app cannot tell them from its own. Launch cleanup treats them the same way, so only the unsaved-work and age protections stand between them and removal.
- Repositories whose tabs closed before this change are not on the new list of known repositories. A one-time review of their leftovers happens with your approval, separate from the app.
