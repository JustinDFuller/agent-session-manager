# Design

## Context

See [proposal.md](proposal.md) for motivation and [the worktree-cleanup delta](specs/worktree-cleanup/spec.md) for the behavior contract.

Today cleanup lives in two places. `Tab.cleanupWorktree(for:)` and `Tab.cleanupManagedWorktree(at:)` in `Models/Tab.swift` run `git worktree remove <path>` through the private `runGit` and let the error propagate. Every UI caller discards it with `try?`: the close-pane flow and both buttons of the pull request alert in `App.swift`. Only the agent-control path in `Controllers/AgentControlMutations.swift` reports the error, and it reports it to the agent, not to the person. `AppState.closeTab` closes panes without any cleanup decision, and its three UI entry points (tab close button, ⌘K, Delete This Tab) call it directly.

A pane records whether its worktree is managed (`Pane.worktreeIsManaged`) and its checkout (`Pane.worktreeDirectory`). Both are persisted in `sessions.json`. The `Tab` already parses `git worktree list --porcelain` and knows the managed folder. Settings are persisted as one small JSON file each through `SettingsPersistence`, and the Dev app uses its own application support folder.

## Goals / Non-Goals

**Goals:** One cleanup pipeline that every caller uses, so the unsaved-work check, branch handling, in-use check, and failure reporting cannot diverge between pane close, tab close, the pull request dialog, agent control, the Settings list, and the launch sweep.

**Non-Goals:** No change to how worktrees are created or named. No deletion of anything outside a repository's managed folders. No trash or undo; deletion stays `git worktree remove`.

## Decisions

### 1. One pipeline: assess, confirm, execute, report

Introduce a `WorktreeCleanup` type that takes a repository root and a checkout and exposes three steps. `assess` returns a value that describes the checkout: modified file count, untracked file count, commits on no remote, whether the head is detached, branch name, whether the branch has commits on no remote, whether the worktree is locked, and whether another pane uses it. `remove` runs the deletion with or without force. `report` turns a result into a message and a trace event. Callers differ only in how they ask the user.

Assessment uses git, not file scanning: `git status --porcelain=v1 -z` for modified and untracked files, `git rev-list --count HEAD --not --remotes` for unpushed commits (which also covers a detached HEAD), the same with the branch name for the branch check, and `git worktree list --porcelain` for locks. Ignored files, such as build folders, are not counted as work and are deleted with the worktree; that is what frees the disk space. The git runner takes a directory instead of a `Tab`, because the launch sweep and Settings list run for repositories that have no tab. `Tab.runGit` and `Tab.runGitOutput` then call the same runner.

An alternative was to try `git worktree remove` first and treat git's refusal as the signal. It was rejected: git does not refuse for a clean worktree whose commits exist only locally, and it cannot say what the unsaved work is, which the dialog must show.

### 2. Removal never forces unless the user said so

`remove` runs `git worktree remove <path>`. Only Delete Anyway adds `--force`. After a successful removal it runs `git worktree prune` for that repository so no stale registration remains. If the Delete Branch With Worktree setting is on and the branch has no commits on any remote, it runs `git branch -D <branch>`; otherwise it uses `git branch -d`, which git refuses when the branch is not merged, and a refusal is reported as the branch being kept. Delete Anyway on a branch with unpushed commits uses `-D` because the dialog already warned about those commits. The default branch and any branch checked out in another worktree are never deleted.

### 3. Pane and tab close share one confirmation flow

Closing a pane still removes it from the window first. The cleanup then runs, and if it needs a decision (the setting is Ask, or the assessment found unsaved work), the dialog is shown before the pane is removed, so Cancel really keeps the pane. This matches the current Ask behavior and extends it to Always Delete when work is at risk.

Tab close gets the same flow in one place. The three UI entry points call a new close-tab request in the view layer. It assesses every managed worktree in the tab, shows one dialog that lists them with any unsaved work, and only then calls `AppState.closeTab` and the cleanup. `AppState.closeTab` keeps closing the tab and no longer decides about worktrees. Agent control keeps its explicit `cleanup` argument and calls the pipeline with the person-facing dialogs replaced by "keep and report", because an agent must not be able to force a deletion.

Before removal, the closed panes' terminal processes are terminated and the removal waits for them to exit, with a short bound. If the removal still fails, the failure is reported rather than retried indefinitely. Whether a running process is a real cause of failures is confirmed during validation.

### 4. Failures are shown and traced

A root-level alert reports failures and kept worktrees with the worktree name and reason. Multiple results from one action are combined into one alert. Each assessment and removal runs inside a trace span; a failure records an error status and a reason attribute. The span for `git worktree remove` already exists, but it does not mark errors today, which is why the failures are invisible in the traces. This is fixed in the shared runner so every git command gets the same treatment.

### 5. Known repositories

A new `known-repositories.json` in the application support folder stores repository roots. A root is added when a tab is created or restored. A root whose folder no longer exists is dropped at launch. The first launch after upgrade seeds the list from the restored tabs. Repositories whose tabs closed earlier are not on the list; the proposal handles those with a one-time review.

### 6. Launch sweep

After session restore, a background task runs once if Clean Up Leftovers at Launch is on. For each known repository it runs `git worktree prune`, lists worktrees, keeps those under `.agent-session-manager/worktrees/` or `.tree/`, drops the checkouts used by open panes, assesses the rest, and removes those that are eligible under the spec. The age check uses the most recent modification time of the worktree's administrative `HEAD` and `index` files in the repository's git folder, which change when the checkout moves, commits, or stages. The specification sets the threshold at 24 hours, which is long enough that a worktree an agent is still working in is not removed, and short enough that yesterday's finished panes are.

The sweep never shows a dialog. It writes a trace event for each removal and each skip with its reason. Anything it skips stays in the Settings list.

### 7. Settings list

The Cleanup section of Settings → Panes gets a Leftovers list. It scans known repositories when the section appears, off the main thread. Size is computed per row after the row appears so a large `.build` folder does not block the list. Entries are registered worktrees under the managed folders that no pane uses, plus folders that git does not register, marked as not a worktree. Deleting a registered entry goes through the pipeline. Deleting an unregistered folder removes only that folder after a confirmation, and only if it is directly inside a managed worktrees folder.

### 8. Settings

Two new settings, `deleteBranchWithWorktree` and `cleanUpLeftoversAtLaunch`, default to on and persist like the existing Worktree Cleanup setting in their own JSON files. The Reset App State targets list both files for the production and Dev folders.

## Risks / Trade-offs

- [Launch cleanup deletes a worktree an agent created inside the managed folder and is not using] → Only clean, fully pushed, unlocked worktrees older than 24 hours with no open pane are eligible, and every removal is traced. The setting can be turned off.
- [Ignored files hold something the user cares about, such as a local `.env`] → They are not counted as unsaved work and are deleted with the worktree, as `git worktree remove` already does. Mentioned in the dialog text only if reviewers want it; flagged here for review.
- [A remote ref is stale, so a commit that looks pushed is not, or the reverse] → Assessment uses remote-tracking refs without fetching. A stale ref can only make the check conservative or miss a very recent push. Fetching on every close was rejected because it needs the network and credentials.
- [`git worktree remove` is slow for a huge folder] → It runs after the pane leaves the window, and the result alert appears when it ends.
- [Seeded list misses old repositories] → Covered by the one-time review in the proposal.

## Migration Plan

New settings and the new repositories file have defaults, so existing installs need no migration. Old `sessions.json` and settings files are unchanged. To roll back, remove the change; the extra JSON files are ignored by older builds.

## Open Questions

- The exact wording of the dialogs and alerts. The specification fixes the button names and the information shown, not the sentences.
