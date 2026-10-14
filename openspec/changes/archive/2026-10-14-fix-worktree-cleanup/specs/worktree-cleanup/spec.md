# Spec Delta

## Purpose

Remove the worktrees that Agent Session Manager creates when their panes or tabs are closed and when they are left behind, without losing unsaved work and without failing silently.

## ADDED Requirements

### Requirement: Only managed worktrees are cleaned up

The app SHALL delete only worktrees it created under a repository's `.agent-session-manager/worktrees/` folder or its older `.tree/` folder, and existing checkouts it was told to manage. It SHALL NOT delete any other worktree, including the main checkout and worktrees in `/tmp`, `~/.codex/worktrees`, and `.claude/worktrees`.

#### Scenario: Close a pane on an unmanaged checkout

- **WHEN** a user closes a pane whose checkout was not created or adopted by the app
- **THEN** the pane closes and the checkout, its git registration, and its branch remain

#### Scenario: Agent scratch worktree elsewhere

- **WHEN** a repository has a worktree under `/private/tmp`
- **THEN** no cleanup action in this capability deletes it

### Requirement: Closing a pane follows the cleanup setting

When a user closes a pane with a managed worktree, the app SHALL follow the Worktree Cleanup setting. With Ask it SHALL offer Delete Worktree, Keep Worktree, and Cancel. With Always Keep it SHALL close the pane and keep the worktree. With Always Delete it SHALL close the pane and delete the worktree. The pane SHALL leave the window immediately in every case.

#### Scenario: Ask and delete a clean worktree

- **WHEN** the setting is Ask, a user closes a pane whose worktree has no unsaved work, and chooses Delete Worktree
- **THEN** the pane closes, the worktree folder is removed, and the repository no longer lists the worktree

#### Scenario: Always Keep

- **WHEN** the setting is Always Keep and a user closes a pane with a managed worktree
- **THEN** the pane closes without a dialog and the worktree remains

### Requirement: Closing a tab follows the cleanup setting

When a user closes a tab by its close button, ⌘K, or Delete This Tab, the app SHALL apply the Worktree Cleanup setting to every managed worktree used by that tab's panes. With Ask it SHALL show one dialog for the whole tab that names the worktrees and offers Delete Worktrees, Keep Worktrees, and Cancel. Cancel SHALL leave the tab open.

#### Scenario: Close a tab with three managed worktrees

- **WHEN** the setting is Ask, a tab has three panes with managed worktrees, and a user closes the tab and chooses Delete Worktrees
- **THEN** one dialog names all three worktrees, the tab closes, and the three clean worktrees are removed

#### Scenario: Cancel closing a tab

- **WHEN** a user closes a tab with managed worktrees and chooses Cancel
- **THEN** the tab, its panes, and its worktrees are unchanged

#### Scenario: Tab without managed worktrees

- **WHEN** a user closes a tab whose panes use no managed worktree
- **THEN** the tab closes without a cleanup dialog

### Requirement: Unsaved work is never deleted without confirmation

Before deleting a managed worktree, the app SHALL check for modified files, untracked files, and commits that are on no remote, including commits on a detached HEAD. When it finds any, it SHALL show a dialog that lists them, with Keep Worktree as the default and Delete Anyway as the alternative. This SHALL apply to Ask, Always Delete, the pull request merged or closed dialog, and tab close.

#### Scenario: Modified files

- **WHEN** a user deletes a worktree that has 25 modified files and 3 untracked files
- **THEN** the dialog says so, and the worktree stays unless the user chooses Delete Anyway

#### Scenario: Always Delete with unpushed commits

- **WHEN** the setting is Always Delete and a worktree has 3 commits that are on no remote
- **THEN** the app shows the dialog listing 3 unpushed commits instead of deleting immediately

#### Scenario: Detached HEAD with local commits

- **WHEN** a worktree is on a detached HEAD at a commit that is on no remote
- **THEN** the dialog lists that commit as unpushed

#### Scenario: Confirm deleting unsaved work

- **WHEN** a user chooses Delete Anyway
- **THEN** the worktree is removed even though it had unsaved work

### Requirement: Failure is reported

If the app cannot delete a worktree, it SHALL tell the user. The message SHALL name the worktree and give the reason. The app SHALL record the failure in its traces with an error status. The worktree SHALL stay registered and on disk unless it was removed.

#### Scenario: Git refuses the removal

- **WHEN** git refuses to remove a worktree after the pane has closed
- **THEN** the app shows a message with the worktree name and git's reason, and the worktree remains

#### Scenario: Several worktrees, one failure

- **WHEN** a tab close deletes three worktrees and one fails
- **THEN** the two successes are removed and the message names only the failed one

### Requirement: A worktree used by another pane is kept

If another open pane, such as a shell pane, still uses the same checkout, the app SHALL keep the worktree when one pane is closed and SHALL tell the user why.

#### Scenario: Close the agent pane but not its shell pane

- **WHEN** a user deletes a pane's worktree while a shell pane is open on the same checkout
- **THEN** the worktree remains and the message says another pane is using it

### Requirement: Branch deletion is a setting

The app SHALL provide a setting, Delete Branch With Worktree, that is on by default. When it is on, a successful worktree deletion SHALL also delete the worktree's local branch. The app SHALL NOT delete a branch that is checked out in another worktree or that is the repository's default branch. If the branch has commits that are on no remote, the dialog SHALL say so before the user confirms.

#### Scenario: Branch removed with its worktree

- **WHEN** the setting is on and a user deletes a clean worktree whose branch is fully pushed
- **THEN** the worktree and its local branch are both gone

#### Scenario: Setting off

- **WHEN** the setting is off and a user deletes a worktree
- **THEN** the worktree is removed and its local branch remains

#### Scenario: Branch checked out elsewhere

- **WHEN** the setting is on and the worktree's branch is also checked out in another worktree
- **THEN** the worktree is deleted and the branch remains

### Requirement: Agent control uses the same cleanup

Agent-control pane and tab deletion SHALL apply the same unsaved-work check, branch setting, and in-use check. It SHALL report keep, delete, or failure for each worktree, with the reason. It SHALL NOT delete a worktree that has unsaved work.

#### Scenario: Agent deletes a pane with unsaved work

- **WHEN** an agent deletes a pane through agent control and its worktree has modified files
- **THEN** the pane closes, the worktree remains, and the result reports it as kept with the reason

### Requirement: Launch cleanup removes safe leftovers

The app SHALL provide a setting, Clean Up Leftovers at Launch, that is on by default. When it is on, the app SHALL at launch delete eligible leftover managed worktrees in every repository where it has had a tab, and SHALL apply the branch setting. When it is off, the app SHALL delete no leftovers at launch.

#### Scenario: Clean and pushed leftover

- **WHEN** the app launches with the setting on and a repository has an old, clean, fully pushed worktree that no pane uses
- **THEN** the worktree is removed

#### Scenario: Repository whose tab was closed

- **WHEN** the app launches and a repository has no open tab but has had one before
- **THEN** its eligible leftovers are deleted

#### Scenario: Setting off

- **WHEN** the setting is off
- **THEN** the app deletes no leftovers at launch

### Requirement: Only provably safe leftovers are deleted at launch

A leftover SHALL be eligible for launch cleanup only if no open pane uses it, it has no modified or untracked files, all its commits are on a remote, it is not locked, and its checkout has not changed in 24 hours. The app SHALL also remove git registrations for worktrees whose folders no longer exist. A leftover that is not eligible SHALL stay and appear in the Settings leftover list with the reason.

#### Scenario: Leftover with unsaved work

- **WHEN** the app launches and a leftover has modified files or unpushed commits
- **THEN** it is not deleted and appears in the Settings leftover list with the reason

#### Scenario: Recently changed leftover

- **WHEN** a leftover that is otherwise eligible changed within the last 24 hours
- **THEN** it is not deleted at launch

#### Scenario: Locked leftover

- **WHEN** a leftover is locked in git
- **THEN** it is not deleted at launch

#### Scenario: Registration without a folder

- **WHEN** git lists a worktree whose folder no longer exists
- **THEN** the stale registration is removed

### Requirement: Leftovers can be reviewed in Settings

Settings → Panes → Cleanup SHALL list managed worktrees that no open pane uses and that the launch cleanup did not delete, or all of them when the launch setting is off. Each entry SHALL show its repository, name, size, and the reason it was kept. The list SHALL also show folders under the managed worktrees folder that git does not register as worktrees. The user SHALL be able to delete selected entries, under the same warnings.

#### Scenario: Review and delete a leftover

- **WHEN** a user selects a leftover with unsaved work in the list and chooses Delete
- **THEN** the unsaved-work dialog appears, and the worktree is removed only after Delete Anyway

#### Scenario: Unregistered folder

- **WHEN** a managed worktrees folder contains a folder that git does not register
- **THEN** the list shows it, marked as not a worktree, and the app does not delete it unless the user selects it

#### Scenario: Nothing left over

- **WHEN** there are no leftovers
- **THEN** the list says so
