# Agent Harness Feature Matrix

This is the canonical, code-observed audit of Agent Session Manager integration points for Claude Code, Cursor, Codex, and OpenCode as of **July 27, 2026**. It describes the app implementation, not upstream CLI feasibility. The internal `.shell` pane type is excluded.

## Legend

| Status | Meaning |
|---|---|
| **Implemented** | Wired end to end in Agent Session Manager |
| **Partial** | Present, but with a known limitation or lifecycle gap |
| **Missing** | Not implemented in Agent Session Manager |
| **N/A** | Intentionally not applicable to that harness |

## Product Surface

| Surface | Claude Code | Cursor | Codex | OpenCode | Notes |
|---|---|---|---|---|---|
| Tool detection | Implemented | Implemented | Implemented | Implemented | `CLIToolDetector` probes `claude`, `agent`, `codex`, and `opencode` in the selected interactive shell. |
| Tool activation | Implemented | Implemented | Implemented | Implemented | Settings persist active harnesses; only active harnesses appear in New Pane. |
| Launch command | Implemented | Implemented | Implemented | Implemented | Launches `claude --settings ...`, `agent`, `codex`, or `opencode` in the resolved checkout. |
| Configurable CLI options | Implemented | Implemented | Implemented | Implemented | Each harness has a separate catalog. See the harness-specific CLI guides linked below. |
| Configurable environment variables | Implemented | N/A | N/A | Implemented | The user-facing environment-variable catalog is Claude-specific and OpenCode-specific. Cursor and Codex receive the internal `AGENT_SESSION_MANAGER_PANE_ID`. OpenCode app-controlled variables (`OPENCODE_CONFIG_CONTENT`, `OPENCODE_PERMISSION`, `OPENCODE_EXPERIMENTAL_EVENT_SYSTEM`, `OPENCODE_DISABLE_PRUNE`, and `OPENCODE_DISABLE_DEFAULT_PLUGINS` in Dev builds) are shown as disabled in the editor. |
| Profiles: CLI options | Implemented | Implemented | Implemented | Implemented | Profiles store a harness type and harness-specific CLI options. |
| Profiles: environment variables | Implemented | N/A | N/A | Implemented | Profile environment variables are Claude-specific and OpenCode-specific. OpenCode app-controlled variables are shown as disabled in the editor. |
| Worktree resolution | Implemented | Implemented | Implemented | Implemented | New Pane passes every harness through `Tab.resolveOrAttachWorktree`. |
| Loading overlay during worktree setup | Implemented | Implemented | Implemented | Implemented | `addPaneWithLoadingState` precedes async Git setup for every harness. |
| External worktree attachment | Implemented | Implemented | Implemented | Implemented | Existing paths from `git worktree list --porcelain` can be reused. |
| Managed worktree cleanup | Implemented | Implemented | Implemented | Implemented | Cleanup is based on pane worktree ownership, not harness type. |
| Session restore | Implemented | Implemented | Implemented | Implemented | Persisted resolved checkout directories are restored for every harness when they still exist. |
| Continue on app restart | Implemented | Implemented | N/A | Implemented | Claude and Cursor receive restore-time `--continue` unless an explicit resume option is saved; OpenCode uses `--session <id>` with `--continue` fallback. |
| Auto session names | Implemented | N/A | N/A | Implemented | Claude uses `--name '<tab>/<pane>'`; OpenCode discovers the TUI-created session and renames it via `PATCH /session/:id`. |
| Restart existing process | Implemented | Implemented | Implemented | Implemented | Controller replacement preserves the existing monitor and callback wiring. |
| Quick refresh and continue | Implemented | Implemented | Implemented | Implemented | Monitor replacement goes through `Pane.installStatusLineMonitor`, which reattaches callbacks. Cursor quick refresh preserves `AGENT_SESSION_MANAGER_PANE_ID`. |
| Refresh with new settings | Implemented | Implemented | Implemented | Implemented | Monitor/controller replacement goes through pane install methods that rewire callbacks. |
| Rich status provider | Implemented | Partial | Partial | Implemented | Claude uses `statusLine`; Cursor adds hook model data; Codex adds version-gated SQLite/rollout data for 0.136.x; OpenCode polls the per-pane HTTP API. |
| Shared baseline status | Implemented | Implemented | Implemented | Implemented | Worktree, branch, duration, lines changed, PR, and profile chips are app-owned where data is available. Cursor and Codex fetch versions; OpenCode uses `GET /global/health`. |
| Native attention integration | Implemented | Partial | Missing | Implemented | Claude uses `Notification` (broadened to `permission_prompt\|elicitation_dialog\|idle_prompt\|agent_needs_input`) plus `Stop` background-work gating (`background_tasks` and `session_crons`) to suppress false "finished" `Stop` notifications, and drop `idle_prompt` while the pane is working; Cursor uses `stop`, but setting changes do not refresh existing Cursor panes. OpenCode uses SSE `session.idle` and `permission.asked` events with a 15-second polling fallback. |
| Shared terminal attention | Implemented | Implemented | Implemented | Implemented | BEL and OSC 777 flow through `TerminalController`. |
| Notification sidebar and banners | Partial | Partial | Partial | Partial | Delivery exists, but new-pane and controller-replacement lifecycle gaps can prevent callbacks from being attached. |
| Notification persistence | Implemented | Implemented | Implemented | Implemented | Pending in-app notifications are stored in `sessions.json`. |
| GitHub PR tracking | Implemented | Implemented | Implemented | Implemented | `PRTrackingCoordinator` is harness-independent. |
| PR merged notifications | Partial | Partial | Partial | Partial | Provider delivery exists for every monitor, but notification callback rewiring has the lifecycle gaps above. |
| Observability and trace dashboard | Implemented | Implemented | Implemented | Implemented | Trace recording and dashboard grouping are app-level features. |

## Agent Control

| Surface | Claude Code | Cursor | Codex | OpenCode | Notes |
|---|---|---|---|---|---|
| Per-pane MCP injection | Implemented | Implemented | Implemented | Implemented | Claude uses `--mcp-config`; Cursor uses a private plugin through `--plugin-dir` whose bundled stdio bridge forwards to the local HTTP server; Codex uses launch-time `-c` overrides; OpenCode merges `OPENCODE_CONFIG_CONTENT`. |
| Injection policy and scope | Implemented | Implemented | Implemented | Implemented | App settings support `Always`, `Never`, and ask policies plus `Pane`, `Tab`, and `Global` scope. |
| Runtime credential isolation | Implemented | Implemented | Implemented | Implemented | Credentials are runtime-only bearer tokens, passed through an environment variable and revoked on pane teardown. Cursor's plugin stores only the bundled bridge path; the inherited endpoint and token are not written to disk. |
| Scoped MCP resources | Implemented | Implemented | Implemented | Implemented | The app-owned server exposes stable-ID workspace, pane, profile, status, notification, and diagnostic resources. |
| Scoped MCP mutations | Implemented | Implemented | Implemented | Implemented | Tab/pane, profile, harness, status-line, notification, diagnostic, and Debug Mode tools enforce scope through the shared router. |
| Terminal-pure setup | Implemented | Implemented | Implemented | Implemented | Configuration preparation occurs in Swift before launch; panes receive only the final harness invocation. |
| Diagnostic redaction and bounds | Implemented | N/A | Implemented | Implemented | Diagnostic queries are bounded and metadata-first; terminal content, harness output, secrets, and environment values are excluded. |

## Status Chips

The catalog controls whether a chip can be selected for a harness. A selectable chip can still render `—` when its provider does not populate the field.

| Chip ID | Claude Code | Cursor | Codex | OpenCode | Source or gap |
|---|---|---|---|---|---|
| `model` | Implemented | Implemented | Partial | Implemented | Claude hook JSON; Cursor `afterAgentResponse` hook; Codex SQLite/rollout metadata for supported versions; OpenCode `GET /session/:id`. |
| `worktree` | Implemented | Implemented | Implemented | Implemented | App-owned checkout directory plus Git branch. |
| `cost` | Implemented | N/A | N/A | Implemented | Claude hook JSON; OpenCode `GET /session/:id`. |
| `context` | Implemented | N/A | Partial | N/A | Claude hook JSON percentage; Codex rollout token count for supported versions; OpenCode does not expose context window size in 1.17.x. |
| `effort` | Implemented | N/A | N/A | N/A | Claude hook JSON. |
| `thinking` | Implemented | N/A | N/A | N/A | Claude hook JSON. |
| `vimMode` | Implemented | N/A | N/A | N/A | Claude hook JSON. |
| `agentName` | Implemented | N/A | N/A | N/A | Claude hook JSON. |
| `sessionName` | Implemented | N/A | N/A | Implemented | Claude hook JSON; OpenCode `PATCH /session/:id {title}`. |
| `linesAdded` | Implemented | Implemented | Implemented | Implemented | App-owned `git diff --shortstat HEAD`. |
| `linesRemoved` | Implemented | Implemented | Implemented | Implemented | App-owned `git diff --shortstat HEAD`. |
| `duration` | Implemented | Implemented | Implemented | Implemented | App-owned process duration. |
| `contextRemaining` | Implemented | N/A | Partial | N/A | Claude hook JSON percentage; Codex rollout token count for supported versions; OpenCode does not expose context window size in 1.17.x. |
| `inputTokens` | Implemented | N/A | Partial | Implemented | Claude hook JSON; Codex rollout token count for supported versions; OpenCode `GET /session/:id`. |
| `outputTokens` | Implemented | N/A | Partial | Implemented | Claude hook JSON; Codex rollout token count for supported versions; OpenCode `GET /session/:id`. |
| `rate5h` | Implemented | N/A | Partial | N/A | Claude hook JSON; Codex primary 300-minute rate window for supported versions; OpenCode does not expose rate limits. |
| `rate7d` | Implemented | N/A | Partial | N/A | Claude hook JSON; Codex secondary 10,080-minute rate window for supported versions; OpenCode does not expose rate limits. |
| `rate5hReset` | Implemented | N/A | Partial | N/A | Claude hook JSON; Codex primary 300-minute rate window for supported versions; OpenCode does not expose rate limits. |
| `rate7dReset` | Implemented | N/A | Partial | N/A | Claude hook JSON; Codex secondary 10,080-minute rate window for supported versions; OpenCode does not expose rate limits. |
| `version` | Implemented | Implemented | Implemented | Implemented | Claude hook JSON; Cursor and Codex run `<command> --version`; OpenCode uses `GET /global/health`. |
| `outputStyle` | Implemented | N/A | N/A | N/A | Claude hook JSON. |
| `exceeds200k` | Implemented | N/A | N/A | N/A | Claude hook JSON. |
| `pr` | Implemented | Implemented | Implemented | Implemented | App-level GitHub CLI polling. |
| `profileName` | Implemented | Implemented | Implemented | Implemented | App state. |

## Notifications

| Integration point | Claude Code | Cursor | Codex | OpenCode | Notes |
|---|---|---|---|---|---|
| BEL handling | Implemented | Implemented | Implemented | Implemented | Shared terminal parser path. |
| OSC 777 handling | Implemented | Implemented | Implemented | Implemented | Shared `ESC]777;notify;title;body BEL` handler. |
| Native hook attention | Implemented | Implemented | Missing | Implemented | Claude `Notification` hook and Cursor `stop` hook are refreshed for every live pane when toggled. Cursor stores hook output in private per-pane directories and reports `beforeSubmitPrompt`/`stop` lifecycle state for activity indicators. OpenCode uses SSE `session.idle` and `permission.asked` events with a 15-second polling fallback. |
| Background-work completion gating (`Stop` lists) | Implemented | N/A | N/A | N/A | Claude Code v2.1.145+ reports `background_tasks` and `session_crons` on every `Stop`; any entry (background agents, shell commands, Monitors, workflows, wakeups, recurring `/loop` schedules) keeps the pane working and suppresses the "Claude finished" notification. A `Stop` missing either list records the `claude.stop.background_state` warning and is treated as finished. |
| Sidebar and pane/tab indicators | Partial | Implemented | Partial | Partial | Cursor lifecycle and attention callbacks drive working, stopped, and waiting states. |
| macOS banners | Partial | Partial | Partial | Partial | Uses the same callback path as sidebar delivery. |
| Pending-notification persistence | Implemented | Implemented | Implemented | Implemented | In-app entries survive restart through `sessions.json`; banners are not replayed. |
| PR merged notifications | Partial | Partial | Partial | Partial | Status monitors subscribe to shared PR tracking; callback rewiring gaps also apply here. |

## Known Gaps

- Codex rollout parsing is currently supported only for Codex `0.136.x`; unknown versions degrade to baseline/state DB facts.

## Harness Guides

Individual CLI flag catalogs remain in the harness-specific guides:

- [Claude Code pane options and shared pane flow]({{ '/documentation/features/panes/' | relative_url }})
- [Cursor CLI support]({{ '/documentation/features/cursor-cli/' | relative_url }})
- [Codex CLI support]({{ '/documentation/features/codex-cli/' | relative_url }})
- [OpenCode CLI support]({{ '/documentation/features/opencode-cli/' | relative_url }})
