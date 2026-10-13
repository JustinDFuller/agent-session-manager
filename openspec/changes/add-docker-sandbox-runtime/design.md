## Context

A pane today launches its agent on the Mac from several near-identical places. Agent Control is a local MCP server accepting only `Host: 127.0.0.1:<port>` and a per-pane bearer token.

Docker's `sbx` tool creates a sandbox: a small virtual machine (VM) for one agent, with chosen Mac folders ("mounts") visible inside at the same path, behind a network proxy with an allowlist. The "integration folder" holds a sandbox's Claude integration files. The "pane tag" is an environment variable marking one pane's processes.

## Spike results

Run on `sbx` 0.46.0, Claude Code 2.1.280, Git 2.53.0 in the VM, Apple Git 2.50.1 on the Mac.

1. Killing the local `sbx exec` leaves the command running in the VM.
2. A bare `-e NAME` keeps the value out of Mac process arguments; `-e NAME=value` does not.
3. The proxy delivers requests to the Mac as `Host: localhost:<port>`. Removing a rule needs `--force`.
4. A custom `CLAUDE_CONFIG_DIR` drops the stock skip-permissions default. With an empty one, `claude auth status` said logged in but `claude --print` did not.
5. `sbx create` accepts files and directories as `:ro` on read-write parents, parents before children, first path read-write. File mounts cannot be added after create; a single file cannot be read-write.
6. `~/.claude` read-only with `projects` and `plans` read-write on top behaved as intended.

## Decisions

### One launch step, runtime applied last

Launch paths merge into one step first, with no behavior change. One runtime stage then runs the final invocation on the Mac or wraps it for the sandbox at process start, recording that it did, so a restart cannot wrap twice.

### Runtime choice and no fallback

The runtime is the pane's choice, else the profile's override, else the app-wide default, else Mac; a missing saved value reads as unset. Agents without a sandbox integration resolve to Mac, with the reason shown.

Before any sandbox work the launch asserts: runtime resolved to Docker Sandbox, `sbx` passing, the Mac's Git 2.41 or newer, a linked worktree, `extensions.worktreeConfig` off, shared paths existing, path options inside shared folders, Python 3 present. A violation stops the launch with a clear error; a restored pane adds Retry. A path that would fall back to Mac reports `sandbox.pane.mac_fallback`.

### Detecting `sbx`, and the Mac's Git version

Detection runs `sbx version --json`, `sbx daemon status --json` and `sbx diagnose --json` with no input and a timeout, through one injectable `SandboxCLI` type. Minimum version 0.46.0. `--attr-source=<empty tree>` needs Git 2.41, so Docker Sandbox mode requires it on the Mac; an older Git is refused, naming the found and required versions.

### One sandbox per worktree and profile

Panes with no profile use the identity `default`. The name is `<prefix>-<slug>-<hash>`: prefix `agent-session-manager` (`-dev` in Dev builds), the lowercased worktree folder name with other characters as hyphens, cut to 63 characters, plus ten hex characters of a SHA-256 of the worktree path and profile id. A registry lists the sandboxes the app created.

### Lifecycle, ending the agent, idle stop

Create or reuse from the registry and `sbx ls --json`; a sandbox missing a needed mount fails the launch and asks for Recreate. Start it with `sbx exec <name> true` before attaching, so the terminal shows only the agent.

Each launch passes `AGENT_SESSION_MANAGER_SANDBOX_PANE=<pane id>`. To end an agent, one short `sbx exec` uses the VM's Python 3 to find processes with that tag in `/proc/*/environ`, terminate, and kill survivors. It runs before launch, on close, on restart, and on quit.

After a sandbox's last agent ends, wait 30 seconds, then stop it only if unused and tagless. A relaunch cancels the stop; a stop that would hit a live process reports `sandbox.stop.live_agent` instead.

### Mounts and Git protection

The Git common directory is read-only by default, with only the paths Git must write carved out. A read-write common directory lets the agent plant a fake `commondir`, redirecting Mac-side Git to an attacker's repository, config, and hooks, and lets `git worktree prune` delete other worktrees' records.

Mounts use the identical Mac path, set at create time in this order:

- the worktree (read-write), then its `.git` pointer file (read-only);
- the Git common directory (read-only), then inside it `objects` (read-write) with `objects/info` nested back to read-only, `refs` (read-write, the whole directory, because `git stash` writes `refs/stash`), `logs` (read-write), this worktree's own record (read-write) with `commondir` and `gitdir` inside it (read-only), and `packed-refs-store` (read-write, below);
- the integration folder, `~/.claude`, the app-owned Claude config folder, and extra folders.

Only those paths are writable. `config`, `hooks`, `info`, other worktrees' records, the `packed-refs` link itself, and any new file or folder in the common directory are refused, which closes the hooks, aliases, and `core.sshCommand` routes. The nested `objects/info` mount stops `alternates` or `http-alternates` files pointing Git at an attacker's objects.

A layout change means Recreate. The launch checks the layout from `sbx ls --json` and reports `sandbox.git.not_read_only` if wrong. The main checkout is refused because its folder contains every worktree. The app does not disable hooks or override `core.sshCommand` on the Mac: that would break the app's own `post-checkout` hooks and custom SSH setups for every pane.

Two routes stay writable by design. A worktree `.gitattributes` can select a filter already in the user's config, so every read-only Git command the app runs against a worktree (`diff --shortstat HEAD`, `branch --show-current`, `remote get-url origin`, `rev-parse`, `worktree list`) goes through one launcher adding `-c core.fsmonitor=false --no-pager --attr-source=4b825dc642cb6eb9a060e54bf8d69288fbee4904` (the empty tree), plus `--no-ext-diff --no-textconv` for `diff`; `fetch`, `worktree add`, `worktree remove` are unchanged. And the record's `config.worktree` is read only when `extensions.worktreeConfig` is on, so a sandbox pane for such a repository is refused (`sandbox.git.worktree_config_enabled`).

### Making branch and tag deletion work: the `packed-refs` link

Git's files backend takes `packed-refs.lock`, next to `packed-refs`, for any ref deletion, even of a loose ref. That includes the cleanup after every commit, `stash pop`, `branch -d`, and `tag -d`. On a read-only common directory the lock cannot be created: commits land but print `Unable to create '.../packed-refs.lock': Read-only file system` each time, and deleting a branch or tag fails. Git's upstream fix is unreleased and covers neither branch or tag deletion nor stash.

Decision: before creating a sandbox for a repository, the app, in Swift on the Mac, makes `<common>/packed-refs` a symbolic link to `<common>/packed-refs-store/packed-refs`. Git follows the link and puts the lock in the store folder, which is read-write and holds only `packed-refs` and its lock. The common directory and the link stay read-only, so the sandbox cannot repoint the link. The step is idempotent: create the store folder, move a regular `packed-refs` into it (or create an empty one), and make the relative link.

Invariant, not fallback: at every sandbox launch the app checks the link is in place and points at the store file. It then acts on what it finds:

- Link in place: nothing.
- Link missing or replaced by a regular file, and no store file or an identical or empty one: repeat the step before launch and record `sandbox.git.packed_refs_relinked` (trace event and invariant report).
- Anything else (a regular file and a store file with different contents, a link pointing elsewhere, a store path that is not a plain folder): refuse the pane with `sandbox.git.packed_refs_conflict`, naming the paths. The app never merges or overwrites.

Rejected: reftable, which changes the repository format for every tool. Config timeouts such as `core.packedRefsTimeout`, which only change how long Git waits. Accepting the errors, which shows the agent a read-only error on every commit and blocks deleting branches. A writable common directory with a read-only denylist, which inverts read-only by default.

Verified in a real sandbox (VM Git 2.53, Mac Apple Git 2.50.1): commit, branch create, switch, merge, `branch -d`, and `tag -d` all work and `packed-refs` is rewritten through the link.

Still failing, because they write Git settings or protected paths: `branch -m` and `-c`; `--set-upstream-to`, `checkout -b --track`, and `push -u` recording an upstream; `remote add`, `set-url`, `remove`; `git config`; `gc` and `maintenance` tasks that need files in the common directory; adding, removing, or pruning other worktrees; installing hooks. `branch -d` may also print a warning that the settings file cannot be locked. A bare `push` or `pull` needs tracking set on the Mac, or the branch named.

### Git identity and environment

The launch forwards the identity Git resolves on the Mac as `GIT_AUTHOR_*`/`GIT_COMMITTER_*`. The Mac's `~/.gitconfig` is not shared, so signing is unavailable. A missing identity reports `sandbox.git.identity_missing` and continues.

Only the app's pane variables, profile and pane environment settings, a fixed terminal set, forwarded names, the pane tag, and the Git identity enter the VM, each as a bare `-e NAME`. Anything else reports `sandbox.env.not_allowlisted`.

### Network

The app adds per-sandbox rules only: one per extra host and one for the current Agent Control port, matched to settings on each launch, with dropped hosts and earlier ports removed (`--force`). It never changes the global policy.

### Agent Control from the sandbox

The endpoint is `http://host.docker.internal:<port>/mcp`; the server sees `Host: localhost:<port>` (spike 3). Sandbox pane credentials are marked, and the server accepts `localhost:<port>` (and the matching `Origin`) only for marked credentials, still listening only on loopback.

Marked credentials can read but not change the app. Each tool is classified read or change in one place; change and unclassified tools are refused with an error naming why. Otherwise injected instructions could make an agent open Mac panes.

### Claude integration files, configuration, login, permissions

The status payload, settings, hook script, hook log and attention log live in the integration folder (`<support folder>/sandboxes/<sandbox name>/`).

`~/.claude` is mounted read-only at its own path, with `projects` and `plans` read-write on top (spike 6). `CLAUDE_CONFIG_DIR` points at an app-owned folder (`<support folder>/sandbox-claude-config/`, read-write) linking the user's settings, `CLAUDE.md`, skills, agents, commands, hooks, plugins, output styles, projects and plans, and holding its own `.claude.json` and credentials. `--continue` should then work across Mac and sandbox (task 6.8 checks). The app writes onboarding and trust flags only when missing.

Permissions come only from the user's CLI options and Claude settings (spike 4). A path-taking CLI option must point inside a shared folder, or the launch fails naming it. Login comes through the sandbox proxy after `sbx login`; spike 4 left it unproven, so task 1.1 checks it first.

### Open Shell and telemetry

"Open Shell" on a sandbox pane starts the shell inside that sandbox with the same exec wrapping, tag and allowlist, without the Agent Control variables.

Each step gets one span with a bounded outcome and no secrets. Invariants are the `sandbox.*` names above plus `sandbox.launch.double_wrap`, `sandbox.mount.path_mismatch`, `sandbox.agent.end_failed`.

## Risks / Trade-offs

- Claude login with the app-owned folder is unproven; task 1.1 decides.
- The `packed-refs` link changes the user's real `.git`. Other tools that read `.git` directly (editors, Git GUIs, libgit2-based tools) are untested with it, and some may replace it with a regular file. The launch check handles that when the contents match the store; otherwise the pane is refused and the user resolves it.
- Git commands the user runs by hand on the Mac, and files the agent writes that Mac tools later run, are not covered.
- The empty attribute source makes line counts ignore the repository's own attributes, so counts may differ slightly where line-ending rules are used. Task 3.2 checks this.
- User hooks and plugins calling Mac-only programs fail in the sandbox, and the agent can write text into history, memory, and plans a later Mac session reads. Accepted.
- One app-owned Claude config folder is shared by every sandbox, so one agent can see another's login and trust-flag state. It never reaches the Mac's own `~/.claude.json`. Accepted.

## Migration Plan

No data migration. Anything without a runtime value reads as Mac. A repository gets the `packed-refs` link when its first sandbox is created.

## Open Questions

- Which `sbx` command reports that the global network policy is initialised? `sbx diagnose --json` has no such check; `sbx policy ls` shows a `local-policy` row once initialised. The detection task settles it.
