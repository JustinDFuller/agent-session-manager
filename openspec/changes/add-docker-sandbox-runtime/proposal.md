## Why

Every pane runs its agent directly on the Mac, with the user's full access to files, credentials, and network. Docker's `sbx` tool runs an agent in a small virtual machine (a sandbox) with only the folders and hosts it is given. This change makes that a built-in way to run a pane.

## What Changes

- Add a pane "runtime": Mac (today's behavior) or Docker Sandbox, chosen app-wide, per profile, or per pane. Saved sessions with no runtime mean Mac.
- Build a generic runtime layer, with only Claude supported now. Other agents stay on the Mac, and the sheet says why.
- Merge the pane launch paths into one, with no behavior change.
- Use one sandbox per worktree and profile, with the profile's shared folders, allowed hosts, forwarded variables, memory, and CPU.
- Manage each sandbox from Swift: create or reuse, start before the terminal attaches, stop when idle, remove with its worktree, and clean up leftovers at app start. Closing, restarting, or quitting ends the pane's agent inside the sandbox.
- Share the worktree, the repository's Git data, and extra folders at the same paths as on the Mac.
- Keep Git on the Mac safe from the sandbox. The repository's shared Git folder is read-only inside the sandbox by default; only the object store, refs, reflog, the pane's own worktree record, and a small folder holding `packed-refs` are writable. The app's own read-only Git commands on the Mac turn off file-system monitors, external diff tools, pagers, and attribute-selected filters, so a worktree file cannot make them run a program (Mac panes too). Hooks and SSH settings are left alone. Docker Sandbox mode requires Git 2.41 or newer on the Mac.
- Make `packed-refs` a symbolic link into that small folder before a repository's first sandbox, so commits, branch and tag deletion, and stash work without `packed-refs` lock errors. The app re-checks the link at every launch and refuses the pane if it cannot restore it.
- Pass only an allowlist of environment variables, by name. Forward the Mac's Git author identity.
- Let sandbox panes reach Agent Control to read, focus, and acknowledge notifications within scope, but never to create, restart, close, reorder, or reconfigure panes, tabs, profiles, or settings.
- Keep sandbox panes' Claude status line, hook, and attention files in a per-sandbox shared folder, so the Mac still sees activity and alerts.
- Share the user's `~/.claude` read-only, with only `projects` and `plans` writable, and point `CLAUDE_CONFIG_DIR` at an app-owned folder linking to the user's settings, `CLAUDE.md`, skills, agents, commands, hooks, plugins, and output styles. `--continue` works across Mac and sandbox. Permission prompts follow the user's own options and settings.
- Open Shell on a sandbox pane opens a shell inside its sandbox.
- Add a setup wizard step checking `sbx` (installed, recent, running, logged in, has a network policy) and the Mac's Git (2.41 or newer). Docker Sandbox becomes the default only if all pass.
- Add Runtime and Sandboxes sections to Settings, app-wide and per profile.
- Refuse sandbox panes on the main checkout and in repositories with `extensions.worktreeConfig`.
- Trace each sandbox step.

## Capabilities

### New Capabilities

- `docker-sandbox-panes`: Choosing a pane's runtime, never falling back to the Mac, sandbox lifecycle, what is shared and forwarded, Git protection, network access, Agent Control, status line and alerts, Claude behavior inside, the wizard step, and Settings.

### Modified Capabilities

None. No existing main spec covers pane launch, setup, or Agent Control.

## Impact

- Pane launch, restore, restart, and the app's read-only Git commands.
- New runtime, `sbx` runner, and lifecycle code.
- Persistence for panes, settings, profiles, and a registry.
- A one-time change to each sandboxed repository's `.git` folder (the `packed-refs` link).
- Agent Control: host validation and a read-only rule for sandbox credentials.
- UI: setup wizard, Settings, New Pane sheet.
- New optional dependency: `sbx`, tested with 0.46.0.

## Delivery

Three pull requests: Proposal, Implementation, and Archive.

## Deliberately Out of Scope

- Codex, Cursor, and OpenCode in a sandbox; each is a later change.
- Panes on the main checkout, repositories with `extensions.worktreeConfig`, cloud sandboxes, and custom images.
- Git commands that write settings inside the sandbox (`git config`, `remote add`, setting an upstream, renaming a branch), and `gc`.
- Forcing permission prompts off.
- Company managed settings, and rewriting the user's localhost MCP configuration.
- Sharing `~/.ssh`, `~/.aws`, or GitHub CLI credentials by default.
- Managing secrets. The app never runs `sbx login` or changes the global network policy.
- Hardening against attacks on the sandbox boundary itself.
- Files the agent writes into the worktree that Mac tools later run, and Git commands the user runs by hand on the Mac.
- User hooks and plugins that need Mac-only programs.
