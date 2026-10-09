# Panes

A **pane** is a terminal session inside a tab. Each pane runs an AI agent CLI: Claude Code, Cursor, or Codex. All three harnesses use the shared worktree flow: the app can attach to existing git checkouts or create **managed** trees under `.agent-session-manager/worktrees/<name>` inside the tab’s repository. See [worktree-creation.md]({{ '/documentation/features/worktree-creation/' | relative_url }}).

## Creating a pane

Use **⌘P** (default; configurable under **Settings → Shortcuts → New Pane in Current Tab**) or **File → New Pane in Current Tab** to open the New Pane sheet.

### Progressive disclosure

The New Pane sheet keeps the common path visible:

1. Choose a **Profile**. Profiles preconfigure the harness and saved options.
2. Enter a session name, branch ref, or existing worktree in **Session, branch, or worktree**.
3. Select **CLI Options** when this pane needs one-off flags, MCP servers, presets, or environment values.
4. Select **More Settings** only when changing Priority Pane, Agent Control, or Scrollback History.
5. Choose **Create Pane** or press Return.

Only tools enabled in **Settings → Harnesses** appear when selecting a custom harness. Switching tools preserves the session field.

The CLI Options and More Settings sheets expose their controls as children of an accessibility container, preserving each control's identifier. Choosing **Done** returns to New Pane; choose **Cancel** there to abandon pane creation.

Pane settings presentation uses the selected pane as its data source so the first opening contains that pane's settings. Closing the sheet clears the selection; reopening it reads the current pane state.

Refreshing a pane first opens its confirmation sheet. **Refresh with New Settings…** opens the configuration sheet after that confirmation dismisses, preserving the selected pane and its current scrollback override.

### CLI options

The **CLI Options** surface shows options enabled in the selected profile or marked **Show on new pane**. When using **Custom**, it shows the active catalog. Presets, custom values, multi-select MCP options, and supported environment variables remain editable there.

Use **Show all options** or **Show all environment variables** to expose the remaining catalog for the selected harness. Long catalogs stay within bounded lists that can be scrolled independently, so the **Done** action remains available. Enabled profile options are visible immediately; disabled options stored in a profile can still be enabled from the expanded catalog.

### More settings

**Scrollback History** — Inherit the 5,000-line global default or choose a pane-specific finite or memory-capped limit. The choice is saved with the pane and is preserved by Refresh Pane.

**Agent Control** and **Priority Pane** remain available under **More Settings** without occupying the primary creation path.

## Status line

Each pane shows a configurable status bar at the bottom (model, cost, context usage, worktree name, and more). Configure items in **Settings → Status Line**.

## Focus mode

The active pane has a 3-point accent-colored border so it is easier to identify in the grid. Click a pane to make it active.

When a tab contains multiple panes, double-click a pane header or right-click and choose **Focus This Pane** to give that terminal the full tab body while keeping the tab bar visible. See [focus-pane.md]({{ '/documentation/features/focus-pane/' | relative_url }}).

## Clipboard

Right-click anywhere on a pane to open the context menu. **Copy** and **Paste** appear at the top, above a divider.

- **Copy** — copies the current selection to the clipboard and clears it as confirmation. The item is greyed out when nothing is selected.
- **Paste** — sends clipboard text through SwiftTerm's bracketed-paste path, so agent TUIs receive it as a single paste event rather than line-by-line keystrokes. ⌘C and ⌘V continue to work as before.
- **Scrollback History** — switches the pane back to the global default, applies a preset or capped unlimited mode, or opens a custom limit editor. Reducing the effective limit requires confirmation because it discards oldest lines.

## Open Shell Here

Right-click a pane header and choose **Open Shell Here** to create a plain shell pane in the same working directory. The new shell pane is named from the source pane so you can tell where it came from, for example `shell:reader`, `shell:reader-2`, and so on.

Shell panes use the same terminal notification handlers as harness panes. A real terminal bell or OSC 777 notification creates a sidebar row, and terminal input acknowledges that row.

## Session persistence

Open panes are saved to `~/Library/Application Support/agent-session-manager/sessions.json`. On relaunch, the app restores tabs and restarts the CLI in any pane whose checkout still exists on disk (see restore rules in [worktree-creation.md]({{ '/documentation/features/worktree-creation/' | relative_url }})).

## Attention notifications

When a tool sends a terminal bell (`\a`), Agent Session Manager can surface [in-app notifications and optional macOS banners]({{ '/documentation/features/notifications/' | relative_url }}) (including when that pane is focused).

## macOS Permission Prompts

When you open your first pane for a repository, macOS may show permission dialogs like:

- **"AgentSessionManager" would like to access files in your Documents folder.**
- **"AgentSessionManager" would like to access files in your Desktop folder.**
- **"AgentSessionManager" would like to access data from other apps.**

These are one-time Transparency, Consent, and Control (TCC) prompts. They occur because Claude Code scans common directories during startup (project detection, configuration discovery). Grant permission once and macOS remembers the decision — the prompts should not repeat.

### What we already mitigate

The app runs the user’s shell as `zsh -i -c '<command>'` (and omits the login `-l` flag). That avoids sourcing `/etc/zprofile` and `~/.zprofile`, which can trigger extra TCC prompts when those scripts touch protected paths. The shell is still interactive (`-i`), so `~/.zshrc` can run and tools like Homebrew or version managers can adjust `PATH`. The app does **not** use `zsh -f` (which skips init files entirely and often breaks CLI discovery).

### Environment sanitization

Before a pane process starts, the app sanitizes the environment it inherited:

- `TERM=xterm-256color` and `COLORTERM=truecolor` are added if unset (SwiftTerm's advertised terminal capabilities).
- `LANG=en_US.UTF-8` is added if unset.
- `PATH` is merged with the system default entries from `/etc/paths` and `/etc/paths.d/*` — the same files macOS uses for login shells — so tools like `go`, Homebrew, and version managers are findable even when the app was launched from Finder/DMG and inherited LaunchServices' minimal PATH.

Inherited values are always preserved. When Agent Session Manager is launched from a terminal, the parent shell usually supplies a complete `PATH` and `TERM`, so the sanitizer is a no-op. When launched from the DMG via Finder, the sanitizer restores the missing baseline.

For process launches and environment details when diagnosing issues, see [debug-logging.md]({{ '/documentation/features/debug-logging/' | relative_url }}).

### If prompts persist across sessions

macOS stores TCC decisions per app bundle. If permissions don't stick:

1. Open **System Settings → Privacy & Security**
2. Check **Files and Folders** and **Full Disk Access** for Agent Session Manager entries
3. Run `tccutil reset All com.justinfuller.agent-session-manager` to reset and re-grant

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘T (default) | New tab |
| ⌘P (default) | New pane in current tab |
| ⌘W | Close active pane |
| ⌘K | Close active tab |
| ⌘1–⌘9 | Switch to tab by index |

For fallback creation from the configured **default branch**, see [default-branch.md]({{ '/documentation/features/default-branch/' | relative_url }}).

Pane loading and setup errors reflect the real worktree operation before a terminal starts. UI regressions create panes through New Pane and use a delayed Git checkout hook and an actual conflicting non-worktree directory in disposable repositories; the app has no loading or error injection flags.
