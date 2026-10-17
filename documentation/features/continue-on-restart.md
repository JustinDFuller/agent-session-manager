# Continue on Restart

When the app relaunches and restores a saved session, Claude and Cursor panes automatically pass `--continue` to the CLI, OpenCode uses its saved session ID when available, and Codex resumes its exact saved foreground conversation when continuation is enabled. Codex uses `resume <session-id>` after its global and user options; it does not depend on `--continue` or select a session by recent activity.

## Configuration

Open **Settings → Panes → Cleanup**:

- **Continue on Restart** — Checkbox toggle. Default: on. Persisted to `restart-settings.json` when changed.

Accessibility identifier: `settings-continue-on-restart-toggle`.

## Behavior

When enabled, `SessionPersistence.restore` adds `--continue` to Claude and Cursor pane arguments unless the saved options already contain `--continue` or an explicit `--resume`. OpenCode restores its saved session ID when available. Codex restores only its saved foreground session ID after checking that the exact session and transcript are accessible through the effective Codex home: the configured interactive shell's exported `CODEX_HOME`, then the inherited launch value, then `~/.codex`. The shell-exported value matches the environment used by the interactive Codex process. A missing session offers Retry or an explicit fresh start; older Codex panes without an identity start fresh with a notice. With the setting disabled, Codex starts fresh.

**Refresh and Continue** uses the current foreground Codex session ID after an exact availability check. **Refresh with New Settings…** starts a fresh Codex conversation. On refresh and restore, status lookup is initialized from that saved exact identity so transcript and SQLite enrichment can proceed before a new hook record arrives. This recovery path still requires a post-change Dev capture.

Codex 0.162.1 runtime observations confirm that Refresh and app relaunch can restore the exact conversation and complete a follow-up turn. In the retained 2026-10-17 Dev capture, Refresh telemetry recorded a matching continuation preflight and foreground binding, hook invocations, populated status facts, and a completion notification; after a full app relaunch, the panes restored their conversations and another turn completed. The app-owned Codex status lines nevertheless remained blank after Refresh and relaunch, and the post-relaunch collection showed no new hook invocations. That capture predates the saved-identity status seeding change described above, so status recovery remains unverified. Earlier Dev runs also showed missing hooks, status facts, and completion after Refresh, so resumed-session status and notification delivery remain under acceptance.

## Persistence

Setting stored at:

`~/Library/Application Support/agent-session-manager/restart-settings.json`

Implemented via `SettingsPersistence.saveRestartSettings` / `SettingsPersistence.restoreRestartSettings`, loaded in `ContentView` before `SessionPersistence.restore`.

## Lost Pane Fix

Panes added via the New Pane sheet are now immediately persisted to `sessions.json`. Previously, only tab additions and active-tab changes triggered a save, so a pane added right before quitting would be lost on relaunch.
