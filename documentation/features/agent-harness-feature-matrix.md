# Agent Harness Feature Matrix

This is the canonical, code-observed audit of Agent Session Manager integration points for Claude Code, Cursor, Codex, and OpenCode as of **October 17, 2026**. It describes the app implementation, not upstream CLI feasibility. The internal `.shell` pane type is excluded. A fresh Codex 0.162.1 conversation has real Dev status, lifecycle, and completion-notification evidence. A retained Dev capture confirms that Refresh and app relaunch restored conversation history and completed follow-up turns; Refresh traces also recorded hooks, rich status facts, and completion delivery. The app-owned Codex status lines nevertheless remained blank, and post-relaunch hook delivery was not observed. Permission/question attention and acknowledgement remain under acceptance.

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
| Continue on app restart | Implemented | Implemented | Partial | Implemented | Claude and Cursor receive restore-time `--continue` unless an explicit resume option is saved; OpenCode uses `--session <id>` with `--continue` fallback; a retained Dev capture confirms Codex restores its saved exact foreground conversation and completes a follow-up turn after app relaunch, while resumed hook and app-owned status recovery remain unresolved. |
| Auto session names | Implemented | N/A | N/A | Implemented | Claude uses `--name '<tab>/<pane>'`; OpenCode discovers the TUI-created session and renames it via `PATCH /session/:id`. |
| Restart existing process | Implemented | Implemented | Implemented | Implemented | Controller replacement preserves the existing monitor and callback wiring. |
| Quick refresh and continue | Implemented | Implemented | Partial | Implemented | Codex checks and resumes the pane's exact foreground session ID. A separate owned Dev run reported status and completion after Refresh, but a later pane-scoped Refresh restored history without hook records, rich status, or a new completion notification; these outcomes conflict. Claude and Cursor use their supported continuation behavior. Monitor replacement goes through `Pane.installStatusLineMonitor`, which reattaches callbacks. Cursor quick refresh preserves `AGENT_SESSION_MANAGER_PANE_ID`. |
| Refresh with new settings | Implemented | Implemented | Implemented | Implemented | Codex starts a fresh conversation; monitor/controller replacement goes through pane install methods that rewire callbacks. |
| Rich status provider | Implemented | Partial | Partial | Implemented | Claude uses `statusLine`; Cursor adds hook model data; Codex selects version-gated adapters for 0.162.x and legacy 0.136.x and tracks exact foreground records. Fresh and CLI `/resume` Dev runs populated status facts. A retained Refresh trace recorded rich facts although the visible app-owned row stayed blank; a later pane-scoped Refresh and the latest app relaunch showed missing hook records and blank status rows. OpenCode polls the per-pane HTTP API. |
| Shared baseline status | Implemented | Implemented | Implemented | Implemented | Worktree, repository identity, branch, duration, line counts, and profile are app-owned. Repository identity resolves without GitHub authentication and merges with provider snapshots. PR state distinguishes loading, current, no PR, unavailable, and stale failures with Retry. Cursor and Codex fetch versions; OpenCode uses `GET /global/health`. |
| Native attention integration | Implemented | Partial | Implemented | Implemented | Claude uses `Notification` (broadened to `permission_prompt\|elicitation_dialog\|idle_prompt\|agent_needs_input`) plus `Stop` background-work gating (`background_tasks` and `session_crons`) to suppress false "finished" `Stop` notifications, and suppress `idle_prompt` only for confirmed pending work; otherwise idle recovers interrupted foreground turns. `PreToolUse` question and plan events produce attention; Cursor uses `stop`, but setting changes do not refresh existing Cursor panes. Codex uses version-selected lifecycle hooks plus fixed-copy completion, permission, and native-question attention; live attention acceptance remains open. OpenCode uses SSE `session.idle` and `permission.asked` events with a 15-second polling fallback. |
| Shared terminal attention | Implemented | Implemented | Implemented | Implemented | BEL and OSC 777 flow through `TerminalController`. |
| Notification sidebar and banners | Partial | Partial | Partial | Partial | Delivery exists, but new-pane and controller-replacement lifecycle gaps can prevent callbacks from being attached. |
| Notification persistence | Implemented | Implemented | Implemented | Implemented | Pending in-app notifications are stored in `sessions.json`. |
| GitHub PR tracking | Implemented | Implemented | Implemented | Implemented | `PRTrackingCoordinator` is harness-independent and uses the configured shell's `gh` path and exported authentication context. A successful empty response shows **No PR**; failed queries retain stale data, show the classified error and **Retry**, and cannot clear PRs or trigger resolution notifications. Retained Dev screenshots show the authentication error and a successful **No PR** result; bounded diagnostics record the corresponding `failure=authentication` and `outcome=not_found` results. |
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
| `model` | Implemented | Implemented | Partial | Implemented | Claude hook JSON; Cursor `afterAgentResponse` hook; Codex root `turn_context` metadata and exact-identity SQLite enrichment for supported versions; OpenCode `GET /session/:id`. |
| `worktree` | Implemented | Implemented | Implemented | Implemented | App-owned checkout directory plus Git branch. |
| `cost` | Implemented | N/A | N/A | Implemented | Claude hook JSON; OpenCode `GET /session/:id`. |
| `context` | Implemented | N/A | Partial | N/A | Claude hook JSON percentage; Codex cumulative token totals and normalized current occupancy from supported rollout records; OpenCode does not expose context window size in 1.17.x. |
| `effort` | Implemented | N/A | N/A | N/A | Claude hook JSON. |
| `thinking` | Implemented | N/A | N/A | N/A | Claude hook JSON. |
| `vimMode` | Implemented | N/A | N/A | N/A | Claude hook JSON. |
| `agentName` | Implemented | N/A | N/A | N/A | Claude hook JSON. |
| `sessionName` | Implemented | N/A | N/A | Implemented | Claude hook JSON; OpenCode `PATCH /session/:id {title}`. |
| `linesAdded` | Implemented | Implemented | Implemented | Implemented | App-owned `git diff --shortstat HEAD`. |
| `linesRemoved` | Implemented | Implemented | Implemented | Implemented | App-owned `git diff --shortstat HEAD`. |
| `duration` | Implemented | Implemented | Implemented | Implemented | App-owned process duration. |
| `contextRemaining` | Implemented | N/A | Partial | N/A | Claude hook JSON percentage; Codex cumulative token totals and normalized current occupancy from supported rollout records; OpenCode does not expose context window size in 1.17.x. |
| `inputTokens` | Implemented | N/A | Partial | Implemented | Claude hook JSON; Codex cumulative token totals and normalized current occupancy from supported rollout records; OpenCode `GET /session/:id`. |
| `outputTokens` | Implemented | N/A | Partial | Implemented | Claude hook JSON; Codex cumulative token totals and normalized current occupancy from supported rollout records; OpenCode `GET /session/:id`. |
| `rate5h` | Implemented | N/A | Partial | N/A | Claude hook JSON; Codex standard-bucket primary 300-minute rate window for supported versions; OpenCode does not expose rate limits. |
| `rate7d` | Implemented | N/A | Partial | N/A | Claude hook JSON; Codex standard-bucket secondary 10,080-minute rate window for supported versions; OpenCode does not expose rate limits. |
| `rate5hReset` | Implemented | N/A | Partial | N/A | Claude hook JSON; Codex standard-bucket primary 300-minute rate window for supported versions; OpenCode does not expose rate limits. |
| `rate7dReset` | Implemented | N/A | Partial | N/A | Claude hook JSON; Codex standard-bucket secondary 10,080-minute rate window for supported versions; OpenCode does not expose rate limits. |
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
| Native hook attention | Implemented | Implemented | Implemented | Implemented | Codex 0.162.x routes permission-hook and native-question events to distinct fixed-copy attention; source and unit coverage exists, while real request and acknowledgement captures remain outstanding. Claude `Notification` hook and Cursor `stop` hook are refreshed for every live pane when toggled. Cursor stores hook output in private per-pane directories and reports `beforeSubmitPrompt`/`stop` lifecycle state for activity indicators. OpenCode uses SSE `session.idle` and `permission.asked` events with a 15-second polling fallback. |
| Background-work completion gating (`Stop` lists) | Implemented | N/A | N/A | N/A | Claude Code v2.1.145 introduced `background_tasks` and `session_crons` (initial live evidence: v2.1.286); when both lists are present, any entry (background agents, shell commands, Monitors, workflows, wakeups, recurring `/loop` schedules) keeps the pane working and suppresses the "Claude finished" notification. A `Stop` missing either list records the `claude.stop.background_state` warning and finishes the active turn even if the remaining list is nonempty. Persistent background shells can suppress completion indefinitely. |
| Sidebar and pane/tab indicators | Partial | Implemented | Partial | Partial | Cursor lifecycle and attention callbacks drive working, stopped, and waiting states. Codex 0.162.x uses foreground hooks for working/stopped states and Codex 0.136.x supports working/stopped without interruption events; a fresh 0.162.x completion notification was delivered in Dev, while permission/question attention and acknowledgement captures remain outstanding. |
| macOS banners | Partial | Partial | Partial | Partial | Uses the same callback path as sidebar delivery; macOS authorization and alert settings are prerequisites, and a permitted Codex banner has not been captured. |
| Pending-notification persistence | Implemented | Implemented | Implemented | Implemented | In-app entries survive restart through `sessions.json`; banners are not replayed. |
| PR merged notifications | Partial | Partial | Partial | Partial | PR transition delivery is wired through pane monitor callbacks; retained real Dev merge/close notification and action-flow evidence remains outstanding. |

## Known Gaps

- Codex recognizes the `0.162.x` current adapter and retains the `0.136.x` legacy adapter; the legacy contract has no `Interrupt` event, and unrecognized versions receive baseline-only integration. Exhausted hook-queue write retries produce redacted diagnostics without guaranteeing event delivery. Fresh-session binding, status, activity, and completion notification work in Dev after hook review and trust. A retained Dev capture confirms conversation continuity and a follow-up turn after Refresh and app relaunch, but Refresh evidence is inconsistent, the app-owned status row stayed blank, and the latest post-relaunch trace contained no hook invocations. Permission/question request and acknowledgement acceptance remains open.

## Harness Guides

Individual CLI flag catalogs remain in the harness-specific guides:

- [Claude Code pane options and shared pane flow]({{ '/documentation/features/panes/' | relative_url }})
- [Cursor CLI support]({{ '/documentation/features/cursor-cli/' | relative_url }})
- [Codex CLI support]({{ '/documentation/features/codex-cli/' | relative_url }})
- [OpenCode CLI support]({{ '/documentation/features/opencode-cli/' | relative_url }})
