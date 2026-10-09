# Agent Control

Agent Control lets an injected agent inspect and operate Agent Session Manager through an app-owned local Model Context Protocol (MCP) server. The app remains the authority for tabs, panes, profiles, worktrees, settings, status lines, and notifications.

The control server starts before session restoration and also starts when a UI-test launch skips restoration. Skipping saved sessions does not disable the real control service or harness injection.

## Configuration

Open **Settings** and choose:

- **Injection policy**: `Always`, `Never`, `Ask (on by default)`, or `Ask (off by default)`.
- **Scope**: `Pane`, `Tab`, or `Global`.

For an ask policy, the New Pane sheet shows the resolved Agent Session Manager control toggle. The decision is persisted with the pane. Policy changes apply to future launches, restores, and restarts; an already-running harness must be restarted to receive a changed environment. Restarts replace injected control configuration rather than accumulating arguments or credentials. Converting a pane to a shell removes the control credential before the shell starts.

`Global` scope is the default for new settings and legacy settings without an explicit scope. `Pane` scope permits access only to the source pane, and `Tab` scope includes the source tab and its panes. Explicitly persisted `Pane` or `Tab` settings remain unchanged. `Global` scope is required for global configuration changes and `debug.set_mode`. Scope is enforced by every request, not only by the tool descriptions.

## Available MCP surface

Read-only resources provide scoped snapshots for:

- workspace, tabs, panes, profiles, harness catalogs, status-line configuration, notifications, and pane status data;
- diagnostic summary, current per-pane traces, invariant occurrences, and app-owned unified logs.

Profile resources contain only profiles referenced by panes visible to the caller. Harness catalogs and global status-line configuration require Global scope; pane- and tab-scoped status-line responses include only visible pane data and profile overrides. Pane command arguments are field-redacted before they leave the app.

Mutation tools provide narrowly scoped operations for:

- tab and pane creation, deletion, focus, restart, and reordering;
- profile lifecycle and ordering;
- harness enablement and CLI option configuration;
- global or profile-specific status-line configuration;
- notification acknowledgement and navigation;
- bounded diagnostic queries and Global-only Debug Mode changes.

Resources use stable IDs. Names are display values and are not addresses. Stale IDs and out-of-scope IDs return structured errors.

## Harness support

Claude Code, Cursor, OpenCode, and Codex receive app-owned, per-pane MCP configuration before the final harness command starts. Cursor receives a private plugin directory through `--plugin-dir`; its plugin-root `mcp.json` starts the app-bundled `AgentSessionManagerMCPBridge` over stdio without modifying project or user configuration. The bridge inherits the loopback endpoint and credential from the Cursor process environment, then forwards MCP messages to the app-owned HTTP server. Claude receives an inline `--mcp-config` document whose top-level `mcpServers` record contains the app-owned HTTP server. Credentials are high-entropy bearer tokens held only in memory and passed through a runtime environment variable. If control registration, bridge lookup, or Cursor plugin preparation is temporarily unavailable, the app opens a normal Cursor pane without injection instead of blocking pane creation. Credentials are revoked when a pane or tab is torn down and are never persisted, logged, or printed in the terminal. A missing or non-executable bundled bridge reports the `cursor.agent_control.bridge_available` invariant, visible in the Invariant Dashboard and unified logs, rather than failing silently.

Cursor prompts to approve the injected MCP server unless the pane's `--approve-mcps` option is enabled, which auto-approves every MCP server the pane sees. The `agent_control.harness.prepare` trace event carries an `approve_mcps` attribute for Cursor panes so a pane that never connects can be diagnosed from one trace lookup.

Cursor uses the CLI's local plugin mechanism rather than `.cursor/mcp.json` or `~/.cursor/mcp.json`. The generated MCP configuration contains only the absolute path to the bundled stdio bridge. The endpoint and `AGENT_SESSION_MANAGER_MCP_TOKEN` remain in the inherited runtime environment and are never written to the plugin directory.

OpenCode configuration is merged into the app-owned inline configuration; existing user MCP entries and unrelated settings are preserved. Disabled or declined injection leaves the normal pane launch path unchanged.

## Security and diagnostics

The server binds only to `127.0.0.1` on an ephemeral port. Requests require the exact loopback host, an optional origin must match the loopback origin, and a valid bearer token bound to an MCP session. Request bodies, responses, concurrency, execution time, and sessions per credential are bounded. Session replacement, deletion, pane teardown, and token revocation release both transport and authorization state. Replacing a pane credential disconnects only sessions bound to the replaced credential, so a cleanup task cannot close a newly registered session. Requests return at the configured deadline; cancelled Git operations terminate their subprocesses where possible.

Diagnostic responses are metadata-first, incrementally bounded, and redacted. Diagnostic resource reads accept `limit`, `sinceEpochMs`, and `untilEpochMs` query parameters. Resource reads default to 20 records and cap requests at 50; diagnostic query tools retain their separate bounded limits. Use time windows to page through older records. A readable resource may return an empty result when no durable file exists; `tracesCapturing` and `invariantsCapturing` report whether new durable capture is enabled.

They do not expose terminal content, harness output, secrets, environment values, or arbitrary system logs. Trace and invariant files remain readable when Debug Mode is disabled, but new durable capture is disabled; unified logs remain available. Legacy top-level diagnostic files are reported separately from current metadata-aware per-pane records.

## Development and troubleshooting

Use the Dev build for MCP protocol and UI validation:

```bash
make test-ui-dev
swift test --filter AgentControl
```

Dev state is isolated under `~/Library/Application Support/agent-session-manager.dev/`. The final terminal invocation contains only the selected harness command; setup, configuration, and error reporting stay in the app layer.

The real Cursor MCP UI test requires `agent status` to validate a live account. Stored credentials that cannot fetch account details do not satisfy this prerequisite; the test reports an explicit skip instead of treating the login screen as an MCP regression. Once authenticated, the test enables the real `--approve-mcps` and `--trust` options for its temporary Git workspace and verifies the session binding and credential revocation traces.
