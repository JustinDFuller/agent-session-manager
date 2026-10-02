# Invariants

Agent Session Manager records contract violations separately from traces so repeated mismatches remain visible during dogfooding.

Production writes under `~/Library/Application Support/agent-session-manager/`. Development builds use the isolated `~/Library/Application Support/agent-session-manager.dev/` directory.

## Enabling

Open **Settings → Debug** and enable **Enable Debug Mode**. Violations are always routed through tracing, but durable invariant JSONL output is written only while Debug mode is enabled.

## Catalog

| ID | Integration | Severity | Legacy trace event |
|---|---|---|---|
| `statusline.worktree.name` | Status Line | warning | `statusline.worktree.name_mismatch` |
| `statusline.lines.source` | Status Line | warning | `statusline.lines.source_mismatch` |
| `claude.stop.background_state` | Claude | warning | `statusline.claude.stop_background_state_missing` |
| `app.bundle_identity.preferred_url` | App Bundle | warning | `app.bundle_identity.preferred_url_mismatch` |
| `github.cli.available` | GitHub CLI | warning | `github.cli.missing_executable` |
| `opencode.config_content.app_controlled` | OpenCode | warning | `opencode.config_content.user_override_silenced` |
| `opencode.port_missing` | OpenCode | error | `statusline.opencode.port_missing` |
| `opencode.port.policy` | OpenCode | error | `opencode.port.policy_violated` |
| `opencode.session.rebindable` | OpenCode | warning | `opencode.session.rebindable_violated` |
| `opencode.tui.endpoints_unused` | OpenCode | error | `opencode.tui.endpoint_forbidden` |
| `cursor.agent_control.bridge_available` | Cursor | error | `cursor.agent_control.bridge_missing` |
| `app.launch.auxiliary_windows_closed` | App Launch | error | `app.launch.auxiliary_window_opened` |
| `terminal.clipboard.copy_requires_selection` | Terminal | warning | `terminal.clipboard.copy_without_selection` |

Each occurrence has its own UUID. Repeated violations of the same invariant remain separate dashboard rows.

`AuxiliaryWindowRegistry.checkOpenWindows()` records `app.launch.auxiliary_windows_checked` (observed window titles and requested ids) every time it runs, regardless of outcome, so a quiet launch is distinguishable from a check that never executed.

## File

Violations are appended synchronously to:

```text
~/Library/Application Support/agent-session-manager/invariants/invariants.jsonl
```

The file starts with versioned metadata and is trimmed to 10 MB with an invariant-specific marker. It is size-bounded only; the trace retention cleanup does not delete it.

## Dashboard

Open **Invariant Dashboard** from **Settings → Debug**, the Window menu, or `⌘⇧I`. The dashboard uses a custom header plus scrollable rows instead of SwiftUI `Table`, pins the macOS 26 dark row colors used by the screenshot baseline, shows newest violations first, supports filtering, and displays the selected occurrence context.

The dashboard appears in its own auxiliary macOS window with the standard traffic-light controls. Close it with the window close button or `⌘W`; that command closes only the dashboard window and leaves the main pane selection unchanged.

For read-only incident diagnosis, use `agent-data-access`; its collector filters invariant occurrences by candidate `context["pane.id"]`.
