## Purpose

A pane can run its agent inside a Docker Sandbox (a small virtual machine managed by Docker's `sbx` tool) instead of on the Mac. This capability defines how the runtime is chosen, what the sandbox can see and change, and what keeps working inside.

## ADDED Requirements

### Requirement: A pane runs on the Mac or in a Docker Sandbox

Every pane SHALL run on exactly one runtime: Mac or Docker Sandbox. A new pane's runtime SHALL be the pane's own choice, else its profile's override, else the app-wide default, else Mac. The New Pane sheet SHALL show the resolved runtime and let the user change it. The runtime SHALL be saved with the pane, a missing saved value SHALL read as Mac (unset for settings and profiles), and later settings changes SHALL NOT change an existing pane. Only Claude panes SHALL be able to use Docker Sandbox. Other agents SHALL run on the Mac, and the sheet SHALL say they are not yet supported in a sandbox.

#### Scenario: Defaults

- **WHEN** a new Claude pane is created with no runtime set at any level, or with the default Docker Sandbox and a profile with no override
- **THEN** it runs on the Mac, or in a Docker Sandbox, respectively

#### Scenario: Override order

- **WHEN** the default is Docker Sandbox, a profile overrides it to Mac, and the user then picks Docker Sandbox for one pane in the sheet
- **THEN** other panes of that profile run on the Mac and the chosen pane runs in a Docker Sandbox

#### Scenario: Settings change later

- **WHEN** a pane runs on the Mac and the user sets the default to Docker Sandbox
- **THEN** that pane stays on the Mac, including after a restart or relaunch

#### Scenario: Relaunch

- **WHEN** the app is relaunched with a saved Docker Sandbox pane and panes from a session saved before runtimes existed
- **THEN** the sandbox pane is restored in a Docker Sandbox and the older panes on the Mac

#### Scenario: Unsupported agent

- **WHEN** the default is Docker Sandbox and the user creates a Codex pane, then a Claude pane
- **THEN** the Codex pane runs on the Mac with the reason shown, and the Claude pane runs in a Docker Sandbox

### Requirement: A sandbox pane that cannot start shows an error and never runs on the Mac

If a Docker Sandbox pane cannot be prepared or started (new, restored, restarted, or refreshed), the app SHALL NOT start the agent on the Mac. It SHALL show an error in the app, not the terminal, naming what failed and the fixing command when there is one. Without creating a sandbox, it SHALL also refuse the main checkout, repositories with `extensions.worktreeConfig` enabled, a missing shared folder, and Mac Git older than 2.41.

#### Scenario: sbx unavailable

- **WHEN** the user creates a Docker Sandbox pane and `sbx` is not installed, not logged in, or its service is not running
- **THEN** no agent starts and the error names the problem, with the login command when login is needed

#### Scenario: Restored pane cannot start

- **WHEN** the app is relaunched with a sandbox pane and `sbx` is broken
- **THEN** the pane shows an error with a Retry button and no agent runs on the Mac

#### Scenario: Main checkout or per-worktree Git settings

- **WHEN** the user creates a Docker Sandbox pane on the main checkout, or in a repository with `extensions.worktreeConfig` enabled
- **THEN** no sandbox is created and the error explains why, naming the setting if that is the cause

#### Scenario: Missing shared folder

- **WHEN** a shared folder from Settings does not exist and the user creates a Docker Sandbox pane
- **THEN** no sandbox is created and the error names the folder

#### Scenario: Git too old on the Mac

- **WHEN** the user creates a Docker Sandbox pane and the Mac's Git is older than 2.41
- **THEN** no sandbox is created and the error names the found and required Git versions

### Requirement: The setup wizard checks Docker Sandbox

The setup wizard SHALL have a Runtime step that checks that `sbx` is installed, a supported version, running, logged in, has a network policy, and that the Mac's Git is 2.41 or newer. Each check SHALL show as passed or failed with its fixing command, and the step SHALL offer Recheck. The app SHALL NOT log in or change the network policy itself. Only if every check passes SHALL the step make Docker Sandbox the app-wide default; otherwise, or if skipped, the default SHALL stay Mac.

#### Scenario: All checks pass

- **WHEN** the user reaches the Runtime step and every check passes
- **THEN** the step shows six passed checks and the default becomes Docker Sandbox

#### Scenario: One check fails

- **WHEN** `sbx` is installed but not logged in
- **THEN** the step shows that check failed with its command, and the default stays Mac until the user logs in and presses Recheck

#### Scenario: Git too old in the wizard

- **WHEN** every `sbx` check passes but the Mac's Git is older than 2.41
- **THEN** the Git check shows as failed with the found and required versions, and the default stays Mac

#### Scenario: Wizard skipped or existing user

- **WHEN** the user skips the wizard, or a user who completed setup earlier updates the app
- **THEN** the default is Mac

### Requirement: Settings control Docker Sandbox

Settings SHALL have a Runtime section for the app-wide default runtime, extra shared folders (read-only or read-write), environment variable names to forward, extra network hosts, and memory and CPU limits. Docker Sandbox SHALL be selectable as the default only while the checks pass, and Settings SHALL show the failed check and a Recheck button. Each profile SHALL be able to override each setting, applying to its own sandboxes only. Settings SHALL list each sandbox the app created with its worktree, profile, and state, with Remove and Recreate buttons, unavailable while a pane uses it. Hosts and forwarded names SHALL apply at the next launch, and folders and limits when a sandbox is next created or recreated.

#### Scenario: Default unavailable

- **WHEN** a check fails
- **THEN** Docker Sandbox cannot be chosen as the default and Settings shows which check failed

#### Scenario: Remove and Recreate

- **WHEN** the user presses Remove on an unused sandbox, or adds a folder and presses Recreate on one
- **THEN** the sandbox leaves the list, or the next pane launched there sees the folder; while a pane uses a sandbox both buttons are unavailable

#### Scenario: Profile override

- **WHEN** one profile lists an extra network host, and a pane of that profile and a pane of another profile run on the same worktree
- **THEN** the first pane can reach the host and the second cannot

### Requirement: Each worktree and profile gets one sandbox, sharing folders at identical paths

A Docker Sandbox pane SHALL use one sandbox per worktree and profile (panes with no profile share a "default" identity), reused if it exists, else created. The name SHALL be valid for `sbx` (at most 63 characters, lowercase letters, digits, and hyphens), unique to the worktree and profile, and different in Dev and release builds. A stopped sandbox SHALL be started before the terminal attaches, and the terminal SHALL show only the agent's output. Refreshing a pane to another profile SHALL end its agent in the old sandbox and start it in the new one. The sandbox SHALL see the worktree, the repository's Git data, the Claude integration files, the user's Claude folder, and each extra shared folder at the same path as on the Mac, and files written there SHALL appear on the Mac.

#### Scenario: First pane on a worktree

- **WHEN** a Docker Sandbox pane is created on a worktree whose sandbox is missing or stopped
- **THEN** the sandbox is created or started and the terminal shows only Claude, with no "started successfully" line

#### Scenario: Sharing

- **WHEN** two panes with the same profile run on one worktree, and a third has a different profile
- **THEN** the first two share one sandbox and the third runs in another

#### Scenario: Names

- **WHEN** a worktree name is long or has capitals, periods, or underscores, or Dev and release builds both have a pane on one worktree
- **THEN** each sandbox name is valid and unique, and neither build touches the other's sandbox

#### Scenario: Same paths

- **WHEN** a sandbox pane runs on a worktree
- **THEN** its working directory in the sandbox is the worktree's Mac path, and files written there appear on the Mac

#### Scenario: Refresh to another profile

- **WHEN** the user refreshes a sandbox pane to a different profile
- **THEN** its agent is gone from the old sandbox and runs in the new profile's sandbox

### Requirement: Git inside the sandbox cannot damage other worktrees or change what Git runs

The repository's shared Git folder SHALL be read-only inside the sandbox by default. Only the parts Git needs to save work SHALL be writable: the object store (except `objects/info`), the refs, the reflog, the pane's own worktree record (except its `commondir` and `gitdir` files), and a small folder holding the packed refs file. Creating or changing any other file there SHALL fail. Commands on the pane's own worktree (commit, branch create and delete, tag create and delete, checkout, switch, stash, merge, rebase, log, fetch) SHALL succeed without `packed-refs` lock errors, with commits visible on the Mac; deleting a branch may warn that the Git settings file cannot be updated. These documented limits SHALL report an error and leave the Mac's Git settings, remotes, and worktrees unchanged, because they write Git settings or protected paths: renaming or copying a branch, setting an upstream (including `push -u`), adding, changing, or removing a remote, `git config`, `gc` and maintenance tasks that write protected paths, adding, removing, or pruning other worktrees, and installing hooks. Git SHALL use the Mac's author identity, and the Mac's global Git config SHALL NOT be shared. If an existing sandbox lacks the read-only layout, no agent SHALL start.

#### Scenario: Normal Git work

- **WHEN** the agent creates a branch, commits, switches branches, stashes and pops, merges, rebases onto a local branch, and fetches
- **THEN** each succeeds without read-only errors and the commit appears in the Mac's log with the Mac's author name and email

#### Scenario: Prune in the sandbox

- **WHEN** `git worktree prune` runs in the sandbox while another worktree exists
- **THEN** the other worktree is still listed on the Mac

#### Scenario: Protected Git files

- **WHEN** the agent tries to set `core.fsmonitor`, `core.hooksPath`, or an alias, run `git branch --set-upstream-to`, add or change a hook, or change the `.git` file or the record's `commondir` or `gitdir`
- **THEN** each fails and the files on the Mac are unchanged

#### Scenario: Commondir redirect

- **WHEN** the agent tries to create a `commondir` file, or any other new file or folder, directly in the shared Git folder
- **THEN** the creation fails and nothing on the Mac changes

#### Scenario: Alternates redirect

- **WHEN** the agent tries to write an `objects/info/alternates` or `objects/info/http-alternates` file naming another repository's objects
- **THEN** the write fails and Git continues to read only this repository's own objects

#### Scenario: Deleting a branch or tag

- **WHEN** the agent deletes a branch and a tag, whether their refs are loose or already packed
- **THEN** both deletions succeed with no `packed-refs` error and the Mac no longer lists them

#### Scenario: Documented limits

- **WHEN** the agent renames or copies a branch, runs `git config`, `git remote add`, or `git push -u`, runs `git gc`, adds another worktree, or installs a hook
- **THEN** each reports an error, `push -u` records no upstream, and the Mac's Git settings, remotes, worktrees, and hooks are unchanged

#### Scenario: Packed refs arrangement before the first sandbox

- **WHEN** a Docker Sandbox pane is created for a repository, with or without a packed refs file, for the first time
- **THEN** before the agent starts, the repository's packed refs file lives in the writable folder and is reached through a link, with the same refs listed on the Mac, and the shared Git folder is otherwise unchanged

#### Scenario: Packed refs link replaced by another tool

- **WHEN** a repository's packed refs link is missing or has been replaced by a regular file since the last sandbox launch, and the stored file is empty, missing, or identical
- **THEN** the next sandbox launch restores the arrangement before the agent starts and records that it did

#### Scenario: Packed refs conflict

- **WHEN** a regular packed refs file exists next to a stored one with different contents, the link points elsewhere, or the store is not a plain folder
- **THEN** no sandbox is started, nothing is overwritten, and the error names the paths

#### Scenario: Layout not read-only

- **WHEN** an existing sandbox does not have these files read-only
- **THEN** no agent starts and the error says to recreate it

#### Scenario: Settings changed on the Mac

- **WHEN** the user changes a Git setting on the Mac while the sandbox runs
- **THEN** Git in the sandbox sees the new value and the settings file stays read-only there

#### Scenario: No identity on the Mac

- **WHEN** Git resolves no author name or email for the worktree
- **THEN** the pane launches with a warning

### Requirement: The app's read-only Git commands do not run programs chosen by the repository or worktree

For every pane, whatever its runtime, the read-only Git commands the app runs on the Mac against a worktree (line counts, branch name, remote URL, worktree listing) SHALL NOT run a file-system monitor, external diff tool, text conversion tool, pager, or a filter or diff driver selected by an attributes file. The app SHALL NOT disable hooks or override SSH settings, so a user's `post-checkout` hook SHALL still run when the app creates a worktree.

#### Scenario: Programs named in settings

- **WHEN** the settings name a program as `core.fsmonitor`, an external diff tool, or a text conversion, and the status line refreshes
- **THEN** the program is not run and the line counts still show

#### Scenario: Attributes file selects a filter

- **WHEN** a `.gitattributes` file in the worktree selects a filter already defined in the user's Git config and the app refreshes line counts
- **THEN** the filter is not run

#### Scenario: User hooks still run

- **WHEN** the user has a `post-checkout` hook and the app creates a worktree
- **THEN** the hook runs and the worktree is created

### Requirement: Environment variables and network access are limited

Only these Mac variables SHALL enter the sandbox: the app's own pane variables, those enabled in the pane's profile and options, a small fixed set of terminal variables, the names listed in Settings, and the Git identity. Values SHALL NOT appear in any Mac process's arguments. Network access SHALL be the user's Docker Sandbox policy plus, for that sandbox only, the extra hosts that apply to the pane's profile and the port Agent Control uses now. The next launch SHALL remove access to a port from an earlier run. The app SHALL NOT change the global policy.

#### Scenario: Variables

- **WHEN** one variable is not allowed and another is listed in Settings, both set in the app's environment, and the pane starts
- **THEN** the agent sees only the listed one, and no Mac process has its value in its arguments

#### Scenario: Agent Control port changes

- **WHEN** the app is relaunched with a new Agent Control port and a sandbox pane launches
- **THEN** the sandbox can reach the new port and not the old one

#### Scenario: Global policy untouched

- **WHEN** a sandbox pane with an extra host is launched and its sandbox removed
- **THEN** the global policy listing is unchanged

### Requirement: Agent Control works from a sandbox pane for reading only

A Claude pane in a sandbox SHALL be able to read through Agent Control, focus panes and tabs, and acknowledge notifications within its scope, as a Mac pane can. The server SHALL accept requests addressed to `localhost` only with a sandbox pane's token, SHALL accept only `127.0.0.1` for Mac panes' tokens, and SHALL listen only on the Mac. A sandbox pane's token, whatever its scope, SHALL NOT change the app: it SHALL NOT create, restart, close, or reorder panes or tabs, or change profiles, CLI option defaults, status-line configuration, harness settings, or debug mode. Tools not classified as allowed SHALL be refused, with an error naming the reason.

#### Scenario: Sandbox pane reads

- **WHEN** Claude in a sandbox pane reads a resource, queries diagnostics, focuses a pane, or acknowledges a notification within its scope
- **THEN** the call succeeds as it would for a Mac pane

#### Scenario: Mac pane unchanged

- **WHEN** Claude in a Mac pane with global scope creates a pane
- **THEN** the pane is created as before

#### Scenario: Wrong credentials

- **WHEN** a Mac pane's token arrives addressed to `localhost`, or a sandbox request has no valid token
- **THEN** the server rejects it

#### Scenario: Changes refused

- **WHEN** Claude in a sandbox pane with global scope calls a tool that creates, restarts, closes, or reorders a pane or tab, edits a profile, CLI option default, status-line configuration, harness settings, or debug mode, or is not classified as allowed
- **THEN** nothing changes and the error names the reason

### Requirement: Status line, activity, and alerts keep working

For a Claude pane in a sandbox, the status line, the working and stopped indicator, and alerts SHALL behave as they do for a Mac pane.

#### Scenario: Status, activity, alerts

- **WHEN** Claude in a sandbox pane reports model and cost, finishes a turn, and later asks a question
- **THEN** the status line shows model and cost, the pane shows working then stopped, one finished alert is sent, and the question alert fires

### Requirement: Claude in a sandbox uses the user's setup, permission options, and conversations

A Claude pane in a sandbox SHALL see the user's Claude settings, `CLAUDE.md`, skills, agents, commands, hooks, plugins, and output styles, read-only. Only conversation history, memory, and plans SHALL be writable, and they SHALL be the ones Mac sessions use. Login and first-run state SHALL live in an app-owned folder, with first-run and trust flags set only when missing. Permission prompts SHALL follow the pane's CLI options and the user's own Claude settings, and the sandbox SHALL NOT turn them off by itself. A Claude option that takes a path SHALL point inside a shared folder, or the launch SHALL fail naming the option. With Continue on Restart on, conversations SHALL continue across Mac and sandbox panes on the same worktree, in both directions.

#### Scenario: Prompts follow the option

- **WHEN** the pane's options do or do not skip permission prompts
- **THEN** Claude in the sandbox skips or asks as it would on the Mac with the same options and settings

#### Scenario: User's setup available

- **WHEN** the user has a `CLAUDE.md` and a skill in their Claude folder and starts a sandbox pane
- **THEN** Claude loads that `CLAUDE.md` and lists that skill

#### Scenario: Settings stay read-only

- **WHEN** Claude in a sandbox pane tries to change the user's settings, `CLAUDE.md`, skill, hook, or plugin
- **THEN** the change fails and the Mac files are unchanged

#### Scenario: Existing first-run state kept

- **WHEN** the app-owned Claude folder already has first-run and trust flags
- **THEN** the app does not change them

#### Scenario: Hook that needs a Mac-only program

- **WHEN** a user hook calls a program that exists only on the Mac
- **THEN** the hook fails inside the sandbox and the pane keeps running

#### Scenario: Path option outside shared folders

- **WHEN** an enabled option points to a file outside every shared folder
- **THEN** the launch fails with an error naming that option

#### Scenario: Continue on Restart

- **WHEN** Continue on Restart is on and a sandbox pane is relaunched, or a conversation started in a Mac (or sandbox) pane is continued in a sandbox (or Mac) pane on that worktree
- **THEN** Claude resumes that conversation, and with Continue on Restart off it starts a new one

### Requirement: Closing, restarting, or quitting ends the agent in the sandbox

When a sandbox pane is closed or restarted, or the app quits, the agent and everything it started in the sandbox for that pane SHALL be ended, without ending another pane's agent in the same sandbox. The terminal SHALL show nothing from this step.

#### Scenario: Close a pane

- **WHEN** two panes share a sandbox and the user closes one
- **THEN** nothing of the closed pane keeps running, and the other pane's agent does

#### Scenario: Restart

- **WHEN** the user restarts a sandbox pane
- **THEN** the old agent is gone before the new one starts, and one agent runs for the pane

#### Scenario: Quit the app

- **WHEN** the user quits with sandbox panes open
- **THEN** none of their agents remain running

### Requirement: Open Shell on a sandbox pane opens a shell in the sandbox

Open Shell on a sandbox pane SHALL open a shell inside that pane's sandbox, with the agent's limits, never on the Mac.

#### Scenario: Open Shell

- **WHEN** the user chooses Open Shell on a sandbox pane
- **THEN** the shell runs in the sandbox at the pane's working directory, a file it writes appears on the Mac, and it cannot change Git settings

### Requirement: Idle sandboxes are stopped and removed ones are cleaned up

After a sandbox's last agent ends, the app SHALL stop it after a short grace period unless a pane starts using it, and SHALL NOT stop one with a running agent. Deleting a managed worktree SHALL first remove all of its sandboxes. At app start, the app SHALL remove sandboxes it created whose worktree is gone and end agents left by an earlier run. The app SHALL NOT stop or remove sandboxes it did not create.

#### Scenario: Stopping

- **WHEN** the last pane using a sandbox closes and the grace period passes
- **THEN** the sandbox is stopped but still exists, unless a pane restarted in time or another pane still uses it

#### Scenario: Worktree deleted or orphaned

- **WHEN** the user deletes a managed worktree with sandboxes for two profiles, or the app starts and finds a sandbox it created whose worktree is gone
- **THEN** those sandboxes are removed

#### Scenario: Other sandboxes untouched

- **WHEN** the user has sandboxes the app did not create
- **THEN** the app never stops or removes them

### Requirement: Sandbox activity is traced without secrets

Each sandbox step (detection, runtime choice, create or reuse, mounts, network rules, start, ending agents, stop, remove, startup scan) SHALL leave a trace record with an outcome from a fixed list and the pane and tab identity where a pane exists. Records and logs SHALL NOT contain environment values, tokens, or terminal content. These SHALL be reported as invariant violations: a sandbox pane starting on the Mac, a launch wrapped twice, a shared path that differs between Mac and sandbox, Git files that should be read-only being writable, stopping a sandbox with a running agent, and a packed refs link restored or in conflict.

#### Scenario: Launch traced

- **WHEN** a sandbox pane starts, or its launch fails, with a secret variable forwarded
- **THEN** the trace shows the steps and outcomes, or the failing step and reason, and no trace record or log contains the secret
