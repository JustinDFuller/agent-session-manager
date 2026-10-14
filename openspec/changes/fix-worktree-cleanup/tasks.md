# Tasks

## 1. Shared git runner and cleanup pipeline

- [x] 1.1 Extract a directory-based git runner that marks failed commands with an error status and reason in traces, and make `Tab.runGit` and `Tab.runGitOutput` use it; verify unit tests run real git in a temporary repository and assert that a failing command records an error span.
- [x] 1.2 Add `WorktreeCleanup.assess` that reports modified files, untracked files, commits on no remote (including a detached HEAD), branch name, lock state, and whether another pane uses the checkout; verify unit tests with real temporary repositories and a local bare remote cover clean, modified, untracked, unpushed, detached with local commits, detached fully pushed, locked, ignored-only changes, and shared-pane cases.
- [x] 1.3 Add `WorktreeCleanup.remove` with optional force, prune, and branch deletion that never deletes the default branch or a branch checked out elsewhere; verify unit tests cover removal of clean and forced dirty worktrees, branch deleted, branch kept with the setting off, branch checked out elsewhere, and git refusal returning a named failure.
- [x] 1.4 Replace `Tab.cleanupWorktree` and `Tab.cleanupManagedWorktree` with the pipeline and restrict deletion to the managed folders; verify no caller of the old functions remains and unit tests show an unmanaged checkout and a `/tmp` worktree are never removed.
- [x] 1.5 Add the Delete Branch With Worktree and Clean Up Leftovers at Launch settings with persistence and defaults of on, and add their files to the Reset App State targets; verify unit tests for defaults, round trip, and invalid file isolation, and that the Makefile reset lists and Dev UI cleanup inventories name both files.

## 2. Pane close, failure reporting, and agent control

- [x] 2.1 Route the close-pane flow and both buttons of the pull request alert through the pipeline, with the unsaved-work dialog (Keep Worktree default, Delete Anyway) for Ask and Always Delete; verify real Dev UI flows show the dialog for modified files, untracked files, unpushed commits, and detached HEAD, and that Keep Worktree leaves the worktree and Delete Anyway removes it.
- [x] 2.2 Add the combined failure and kept-worktree alert naming each worktree and reason, and keep a worktree that another pane uses; verify a real Dev UI flow with a shell pane on the same checkout shows the in-use message and a forced git refusal shows the failure alert.
- [x] 2.3 Terminate the closed pane's processes and wait for exit, bounded, before removal; verify a real Dev UI flow with a process still writing in the worktree either removes it or reports the failure, and record which behavior was observed (observed: the worktree was removed after the writer process was terminated, with no failure alert).
- [x] 2.4 Apply the pipeline in agent-control `panes_delete` and `tabs_delete`, reporting keep, delete, or failure per worktree and never deleting unsaved work; verify unit tests on the mutation results and a real agent-control call against the Dev app that returns kept with a reason for a dirty worktree.

## 3. Tab close

- [x] 3.1 Add one close-tab request used by the tab close button, ⌘K, and Delete This Tab that assesses every managed worktree in the tab and shows one dialog (Delete Worktrees, Keep Worktrees, Cancel); verify real Dev UI flows for each entry point, Cancel leaving the tab unchanged, a tab without managed worktrees closing without a dialog, and Always Keep and Always Delete behavior.
- [x] 3.2 Report partial success on tab close so that the successes are removed and only the failed worktree is named; verify a real Dev UI flow with three worktrees where one has unsaved work shows the unsaved-work dialog for that worktree only.

## 4. Known repositories and launch cleanup

- [x] 4.1 Add `known-repositories.json` that records a root when a tab is created or restored, drops missing folders, and seeds from restored tabs on first launch; verify unit tests for add, restore, missing-folder removal, seeding, and corrupt-file isolation.
- [x] 4.2 Add the launch sweep with prune, the managed-folder filter, the eligibility rules (no open pane, clean, fully pushed, unlocked, unchanged for 24 hours), the branch setting, and per-removal and per-skip trace events; verify unit tests with real repositories and modified timestamps cover every eligibility rule, the 24-hour boundary, repositories with no tab, and the setting off.
- [x] 4.3 Run the sweep once after session restore in the background without dialogs; verify a real Dev app launch against seeded real repositories removes a clean old leftover, keeps a dirty one, and the traces list each decision.

## 5. Leftovers list in Settings

- [x] 5.1 Add the Leftovers list to Settings → Panes → Cleanup showing repository, name, size loaded after the row appears, and the reason kept, including unregistered folders marked as not a worktree and an empty state; verify real Dev UI flows show each case with the list scanning off the main thread.
- [x] 5.2 Add deleting selected entries through the pipeline and the unregistered-folder confirmation limited to folders directly inside a managed worktrees folder; verify real Dev UI flows delete a clean entry, require Delete Anyway for a dirty one, and remove a selected unregistered folder only after confirmation.

## 6. Reproduction and proof in the running app

- [x] 6.1 Reproduce the original problems in a running Dev app built from the base commit with a scratch repository and local remote, covering the control case, modified files, the three tab-close entry points, ignored build folders, a running process, a shell pane on the same checkout, and a detached HEAD with local commits; record `git worktree list`, `du`, branch lists, and real screenshots, and confirm or correct the hypotheses in the proposal.
- [x] 6.2 Rerun every scenario with the implementation in the Dev app and capture before and after screenshots or a recording of the unsaved-work dialog, failure alert, tab-close dialog, leftovers list, and a launch cleanup that removes a clean leftover and keeps a dirty one; verify the captures come from the running app with no injected state and can be embedded in the pull request.

## 7. Documentation and checks

- [x] 7.1 Update the worktree-cleanup feature guide and its skill to describe the pipeline, settings, tab close, unsaved-work dialog, failure alert, launch cleanup, and Leftovers list; verify the guide's paths and behavior statements match the implementation and tests.
- [x] 7.2 Update the public documentation following the Diataxis skill, with a how-to for cleaning up worktrees and reviewing leftovers and reference entries for the new settings and dialog buttons, using exact visible labels and real screenshots; verify `make docs-check` and `scripts/test-release-publishing.sh` pass.
- [x] 7.3 Run the complete applicable checks and correct any regressions; verify `swift test`, `make lint`, `make no-code-comments`, `make no-fixed-width-prose`, and the focused `make test-ui-dev` flows all pass.
