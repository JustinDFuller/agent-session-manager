# Agentic Control

## Vision

Agent Session Manager should be bidirectional: it drives agent harnesses, and agents can inspect and drive Agent Session Manager. An agent running in a pane should be able to understand the current workspace and perform the same meaningful session-management operations available to a user, while preserving the app's existing lifecycle, persistence, worktree, focus, notification, and terminal-purity behavior.

The control surface should be an app capability, not a collection of harness-specific shell commands. The app remains the authority over tabs, panes, profiles, worktrees, settings, status lines, and notifications.

## Research conclusion

MCP is the preferred agent-facing protocol. Claude Code, Cursor, Codex, and OpenCode all support HTTP-based MCP integrations, and MCP standardizes server discovery, resources, tools, structured results, and errors.

- [MCP transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
- [MCP tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)
- [Claude Code MCP](https://code.claude.com/docs/en/mcp)
- [Cursor MCP](https://docs.cursor.com/context/model-context-protocol)
- [Codex MCP](https://learn.chatgpt.com/docs/extend/mcp)
- [OpenCode MCP](https://dev.opencode.ai/docs/mcp-servers/)

Use one app-owned Streamable HTTP MCP server bound to `127.0.0.1`, rather than one stdio server per pane. The app can then remain the single authority over live `@MainActor` state and can issue per-pane credentials. Native XPC is a possible future integration for other local clients, but the harnesses do not speak XPC and would still require custom adapters.

The official [Swift MCP SDK](https://github.com/modelcontextprotocol/swift-sdk) is the first implementation candidate. The repository uses Swift tools 6.1, matching the SDK's current manifest requirement. The app source remains in its existing Swift 5 language mode until its separate concurrency migration is complete; it is still compiled by the installed Swift 6 toolchain. The control domain must remain independent of that transport decision.

## Configuration

Agent control is configured like other user-facing behavior.

### Injection policy

Persist an `AgentControlInjectionPolicy` in a new app-settings file with these user-facing choices:

- `Always`
- `Never`
- `Ask (on by default)`
- `Ask (off by default)`

The default is `Ask (on by default)`. When an ask policy is selected, `NewPaneSheet` displays an Agent Session Manager control toggle using the corresponding default. The final terminal command remains only the selected harness command; Swift prepares any MCP configuration and environment before the process starts.

Persist the resolved per-pane injection decision with session state. Changing the global policy affects new, restored, and restarted pane launches. Already-running harness processes require a restart before their environment can change.

### Scope policy

Persist an `AgentControlScope` with these choices:

- `Pane` — the injected agent can access only its own pane.
- `Tab` — the injected agent can access all panes in its tab.
- `Global` — the injected agent can access the entire app.

The default is `Global`. Scope is enforced for every read and write request, not just communicated through tool descriptions. Explicitly persisted `Pane` and `Tab` scopes remain unchanged; legacy settings without a stored scope resolve to `Global`.

There is no additional Agent Session Manager confirmation dialog for an authorized MCP mutation. The injection policy controls whether the server is available; it is not a per-tool approval mechanism. Harness-native MCP approval behavior remains independent.

## Expected control surface

Expose reads primarily as MCP resources and changes as narrowly scoped tools. Use stable IDs for addressing; names are display values only.

### Tabs and panes

- Create, inspect, focus, delete, and reorder tabs.
- Create panes with harness, profile, CLI options, environment values, worktree reference, base reference, priority, and control-injection choices.
- Inspect, focus, restart, delete, and reorder panes.
- Require explicit worktree-management and cleanup choices when an existing app policy would otherwise display an `ask` dialog.
- Preserve existing setup states, worktree ownership, cleanup behavior, notification cleanup, active IDs, and session persistence.

### Profiles and harness settings

- Create, inspect, edit, delete, and reorder profiles.
- Enable or disable harnesses for future pane creation.
- Enable harness options and update their default values.
- Update preset choices and multi-value option choices.
- Validate options against the selected harness catalog.
- Redact profile environment-variable values in read resources.

### Status lines and notifications

- Read status-line configuration and current structured status data for panes.
- Update global and profile-specific status-line configuration.
- List notifications with their tab and pane targets.
- Acknowledge a notification atomically by navigating to its pane and removing the notification through the same app path used by the UI.

### Diagnostics and observability

Agents should be able to diagnose the pane or workspace they are operating in without shelling out to inspect app-support files or asking a human to open a dashboard. Expose diagnostics as scoped MCP resources and bounded query tools:

- Provide a diagnostic summary with app mode, build identity, Debug Mode state, active tab and pane IDs, and the scoped session metadata.
- Provide metadata-aware trace queries over current per-pane JSONL files, with pane or tab IDs, time windows, event-name filters, result limits, truncation, malformed-record, and legacy-file metadata. Read trace metadata rather than deriving identity from sanitized filenames.
- Provide invariant queries with occurrence IDs, invariant IDs, integrations, severity, timestamps, and bounded context. Preserve repeated occurrences as separate records.
- Provide unified-log queries over the Agent Session Manager process and subsystem, filtered by time, category, level, and event name. Normalize logs into a bounded, redacted result; never expose terminal content, harness output, secrets, environment values, or arbitrary system logs. The app may use `OSLogStore` for this read path, with date positions and matching predicates as the query primitives.
- Return availability and capture-state metadata when Debug Mode is disabled. Unified logs remain available because they are always on; existing trace and invariant files remain readable, but no new durable records are captured.
- Diagnostic resource reads accept `limit`, `sinceEpochMs`, and `untilEpochMs`. They default to 20 records and cap requests at 50; diagnostic query tools retain their separate bounds. Readability describes the valid resource response, while `tracesCapturing` and `invariantsCapturing` describe durable capture state.

Pane scope may read only records attributable to its source pane. Tab scope may read records attributable to panes in that tab. Unscoped global records and cross-pane correlation are Global-scope data; they must not be returned to a pane- or tab-scoped caller merely because they share a time window. Log correlation must use safe structured IDs or an app-owned projection, never parsing private message text.

Expose one narrowly scoped `debug_set_mode` tool for enabling or disabling Debug Mode. It must persist through the existing debug settings path and reuse the existing tracing and invariant reconfiguration behavior. Only a Global-scope token may call it. File deletion, retention changes, path changes, and diagnostic export are outside this first use-case.

The roadmap should maintain a feature-parity matrix for later capabilities, including continue-on-restart, focus mode, activity state, PR tracking, worktree policies, diagnostics, and observability.

## Proposed architecture

### Control service

Add an app-owned control service responsible for:

- Starting the localhost listener before any injected pane can launch.
- MCP initialization, resource discovery, tool discovery, and tool calls.
- One high-entropy bearer token per injected pane.
- Mapping tokens to source pane and configured scope.
- Origin validation, request limits, timeouts, cancellation, and token revocation.
- Structured audit events with secrets and bearer tokens redacted.

Network handlers should validate and decode requests, then dispatch to a main-actor command router. The router should operate on existing `AppState`/`AppSettings`/`Tab`/`Pane`/`Profile` behavior rather than duplicating UI mutations or bypassing existing side effects.

Expose Codable snapshots and operation results instead of observable model objects. A snapshot should include current IDs, names, harnesses, worktree metadata, setup/activity state, profiles, option catalogs, status data, and notifications, subject to the caller's scope.

### Harness adapters

Each adapter must generate app-owned configuration without overwriting user or repository configuration:

- Claude Code: use its supported MCP configuration mechanism.
- OpenCode: merge an app-owned remote MCP configuration with existing config.
- Codex: use its supported HTTP MCP configuration and bearer-token settings.
- Cursor: pass a private plugin through `--plugin-dir`; its bundled stdio bridge inherits runtime connection details and never overwrites tracked or user-owned `.cursor/mcp.json`.

If injection is requested and an adapter cannot prepare valid configuration, the pane setup must report an actionable error instead of silently claiming that agent control is active. `Never` or a declined ask choice must leave the normal pane launch path unaffected.

## Prerequisite: Swift 6 language-mode migration

The Agentic Control implementation is gated on moving the repository to the latest Swift language mode supported by the active Xcode toolchain. This is a separate workstream from MCP and must land first so the control surface is not built on a compatibility mode that we intend to remove.

Plan the migration as its own implementation session:

1. Change the SwiftPM package and generated Xcode targets to Swift 6 language mode while retaining the macOS 14 deployment target.
2. Build with the active release Xcode toolchain and inventory all new concurrency, isolation, Sendable, and framework-import diagnostics.
3. Migrate production code and tests in focused groups, preserving existing actor boundaries and adding explicit isolation or Sendable conformances only where they describe the real ownership model.
4. Run the complete unit, format, SwiftLint, Dev UI, and screenshot validation suite; separate pre-existing test failures from migration regressions.
5. Record the supported Xcode and Swift versions in the build documentation and CI so future toolchain updates remain intentional.

The prerequisite is complete when the package declares Swift 6 language mode, the app and UI-test targets compile in that mode, all required validation is green, and no compatibility-only compiler settings remain. Only then should the MCP implementation roadmap continue with domain configuration and persistence.

### Ongoing version maintenance

Version updates are automated, but compatibility remains a required gate:

- `Package.swift` owns direct package lower bounds and the Swift tools/language mode declaration; `Package.resolved` records the exact dependency graph.
- Dependabot checks Swift packages and GitHub Actions daily, groups compatible updates, and may auto-merge only patch and minor dependency updates after required CI checks. Major updates remain review-required.
- `dependency-toolchain-compatibility.yml` runs on dependency and toolchain changes and weekly. It checks the supported toolchain floor, resolves the locked graph, and builds the release package before an update can be accepted. Unit tests remain covered by the existing test workflows when enabled; the floor build intentionally avoids conflating XCTest SDK isolation differences with package compatibility.
- `scripts/check-toolchain.sh` requires Swift 6.2 or newer and Xcode 26 or newer, while the current validated local toolchain is recorded as Swift 6.4 with Xcode 27.0. A toolchain upgrade must update this documentation and retain the full compatibility checks.
- Distributed app versions remain derived from release tags and commit count by `scripts/dist.sh`; dependency or toolchain updates do not silently change the product version.

The maintenance workflow is: accept or review the Dependabot update, inspect the resolved graph and release notes, run the compatibility workflow, then update the Swift/Xcode baseline only when the supported toolchain policy changes. Do not bypass a failed compatibility build with weaker concurrency checking or an unreviewed dependency pin.

## Implementation roadmap

Each item is intended to be a separate implementation session.

1. **Document and feasibility spike**
   - Keep this roadmap current.
   - Test the Swift MCP SDK against the repository toolchain.
   - Validate Streamable HTTP with a local MCP client.
   - Prototype configuration injection for every harness without repository or global-user configuration writes.

2. **Domain configuration and persistence**
   - Add injection-policy and scope types.
   - Add `AppSettings` and `SettingsPersistence` support.
   - Persist pane-level injection decisions in session state.
   - Add Settings and New Pane controls, accessibility identifiers, migration, and isolated Dev reset coverage.

3. **MCP lifecycle and security**
   - Implement the app-owned listener and service lifecycle. [implemented]
   - Implement token registration, scope authorization, request validation, bounded output, cancellation, and revocation. [implemented]
   - Add MCP protocol tests and runtime telemetry. [implemented]

4. **Read-only resources**
   - Add scoped snapshots for tabs, panes, profiles, harness settings, status lines, and notifications.
   - Verify structured output, redaction, stale IDs, and scope boundaries. [implemented]

5. **Diagnostics and observability**
   - Add scoped diagnostic DTOs and resources for summaries, traces, invariants, and unified logs. [implemented]
   - Reuse metadata-aware trace and invariant readers; keep legacy files separate and preserve truncation and malformed-record metadata. [implemented]
   - Query only the Agent Session Manager process/subsystem through a bounded, redacted `OSLogStore` adapter; never expose terminal or harness output. [implemented]
   - Add the Global-scope-only Debug Mode tool and reuse existing persistence and reconfiguration paths. [implemented]
   - Protocol-test time windows, filtering, scope boundaries, redaction, disabled capture, cancellation, and output limits. [implemented]

6. **Harness injection**
   - Implement and test adapters one at a time, starting with Claude Code and OpenCode, followed by Codex and Cursor.
   - Verify that disabled or declined injection produces no MCP configuration.
   - Verify that enabled injection is prepared before process launch and does not print app plumbing in the terminal. [implemented for all four harnesses]

7. **Tab and pane mutations**
   - Add creation, deletion, focus, restart, and reordering tools.
   - Route worktree resolution and cleanup through existing app services.
   - Return explicit partial-failure results for multi-pane cleanup. [implemented]

8. **Profiles and harness configuration**
   - Add profile CRUD and ordering tools.
   - Add harness enablement, option activation, defaults, preset choices, and multi-value choice tools. [implemented]
   - Preserve custom options and redact sensitive values.

9. **Status lines and notifications**
   - Add status-line reads and updates for global and profile configuration.
   - Add notification listing and atomic acknowledge/navigation behavior. [implemented]

10. **Parity, documentation, and hardening**
   - Audit every feature against the parity matrix.
   - Add the user-facing feature guide and feature skill.
   - Complete telemetry, failure handling, migration, security, and rollout documentation.

### Domain configuration and persistence record

Roadmap item 2 is implemented as a transport-independent foundation:

- `AgentControlInjectionPolicy` and `AgentControlScope` use stable Codable raw values and default to `Ask (on by default)` and `Global`.
- `agent-control-settings.json` stores the app-level policy and scope through the existing settings persistence path.
- Pane decisions are persisted in `sessions.json`; legacy panes without the field resolve through the current policy and are migrated on the next save.
- Settings and New Pane expose the policy, scope, and per-pane ask decision; forced policies expose a read-only state instead of a toggle.
- Dev reset paths clear the new settings file, and UI coverage uses the real Settings and New Pane flows.
- Pane-scoped decision telemetry records bounded IDs, policy, scope, source, and the resolved enabled value. No listener, token, MCP dependency, or harness configuration adapter is introduced in this phase.

### Tab and pane mutations record

Roadmap item 7 is implemented through the app-owned MCP router:

- `tabs_create`, `tabs_delete`, `tabs_focus`, and `tabs_reorder` expose global tab lifecycle operations with stable IDs, active-state results, and ordered tab IDs.
- `panes_create`, `panes_delete`, `panes_focus`, `panes_restart`, and `panes_reorder` use hierarchical pane and tab scope authorization. Pane creation awaits existing worktree resolution, duplicate detection, profile and option validation, external-worktree management, and launch preparation.
- Profile options and environment values seed pane creation, while explicit values override profile values. App-controlled environment variables are rejected and runtime environment values are not persisted.
- Worktree cleanup honors the persisted Keep, Delete, or Ask policy. Ask requires an explicit keep/delete input, and destructive cleanup reports one result per pane with `partial_failure` when removal completes but cleanup fails.
- Every mutation is recorded in `agent_control.mutation` with bounded source, target, scope, and result metadata; values, environment contents, tokens, and terminal output are excluded.
- Unit and protocol coverage verifies scope boundaries, stateful focus and ordering, tab creation, cleanup policy enforcement, and partial-failure reporting. Cross-tab pane moves and shell panes remain outside this item.

### Profiles and harness configuration record

Roadmap item 8 is implemented through the app-owned MCP mutation router:

- Global-scope `profiles_create`, `profiles_update`, `profiles_delete`, and `profiles_reorder` tools manage the existing ordered profile store using stable profile IDs.
- Profile creation seeds the selected harness defaults. Updates use keyed patches for CLI options and environment variables, so redacted environment values never need to be read back. Harness changes reset configuration to the new harness defaults before applying supplied patches.
- Profile option inputs are validated against the selected harness catalog, including boolean, single-value, and multi-value rules. App-controlled environment variables cannot be changed, and profile mutation results expose only redacted environment metadata.
- Global-scope `harnesses_set_enabled` and `harnesses_configure_cli_option` tools update the existing harness and CLI option settings. Preset values are normalized, and user-added catalog entries remain intact.
- Mutations persist through the existing settings files, roll back in-memory state when persistence fails, emit bounded `agent_control.mutation` records, and do not restart or alter already-running panes.
- `AgentControlMutationTests` covers lifecycle, ordering, scope rejection, validation, redaction, persistence-backed configuration, telemetry, preset normalization, and custom-option preservation.

### Status lines and notifications record

Roadmap item 9 is implemented through the existing resources and app-owned mutation router:

- Global-scope `status_lines_update_global` replaces and persists the global `StatusLineConfig`. Global-scope `status_lines_update_profile` replaces a profile override, while `status_lines_clear_profile_override` removes only that override. Configurations are semantically validated before mutation, including built-in and custom item IDs, custom-field identity, required labels and commands, duplicate items, and duplicate custom fields.
- Global status-line persistence uses an atomic write and profile mutations roll back in-memory state when persistence fails. Mutation results return the applied global configuration or updated profile snapshot without exposing unrelated settings.
- The existing `agent-session-manager://notifications` resource remains the notification listing surface. Global, tab, and pane callers can use `notifications_acknowledge` only for visible notifications within their scope. Acknowledgement resolves the stable notification ID, navigates using the shared `AppState` path, removes the notification and delivered macOS notification, and preserves PR-resolution actions.
- Status-line updates and notification acknowledgement emit bounded `agent_control.mutation` telemetry with operation, scope, target IDs, and outcome metadata. Notification text, configuration payloads, secrets, and terminal output are excluded.
- Unit, resource, telemetry, and real-flow UI coverage verifies validation, persistence, profile override clearing, scope enforcement, stale targets, shared notification acknowledgement behavior, tool discovery, and sidebar acknowledgement.

### Parity, documentation, and hardening record

Roadmap item 10 is implemented as the parity and hardening closeout:

- `documentation/features/agentic-control.md` documents the app-owned MCP surface, policy and scope behavior, supported harness adapters, security guarantees, diagnostics, and Dev troubleshooting.
- `.agents/skills/feature-agentic-control/SKILL.md` and the `AGENTS.md` feature entry make the guide discoverable for future Agent Session Manager work.
- `agent-harness-feature-matrix.md` now audits Agent Control across harnesses, including Cursor's private-plugin and bundled-bridge injection path.
- The tracing span catalog includes resource reads, mutations, and harness preparation alongside the existing lifecycle, authorization, and diagnostic events.
- OpenCode injection merges the app-owned MCP server into the existing inline MCP map without removing user-configured servers. A malformed existing MCP value remains an actionable configuration error.
- Streaming responses that exceed the configured limit close without emitting a successful HTTP end marker, so clients observe a transport failure instead of accepting an incomplete response as successful.

Cursor injection uses the documented local plugin surface for per-pane isolation. Its plugin starts an app-bundled stdio bridge so connection details stay in the inherited runtime environment rather than plugin configuration. Existing local XCTest execution may remain unavailable on hosts where the test runner architecture does not match the generated arm64 bundle; compatible CI or direct native XCTest validation is required in that environment.

Validation for this closeout:

- `swift build` passed with the Agent Control changes.
- `swift test --filter AgentControlHarnessInjectionTests` compiled the test bundle but could not execute it because the host requested x86_64 while the generated bundle was arm64.
- `git diff --check` passed. Local `make lint` and SwiftLint execution were unavailable because `swift-format` is not installed and SwiftLint could not load `sourcekitdInProc.framework`; run both checks in the supported CI/Xcode environment.

### Feasibility spike record

The feasibility spike was research-only. Its protocol and toolchain evidence is retained below; the implementation that follows is the separate lifecycle phase. Temporary probes belong under an ignored temporary directory and must remove their files, processes, and tokens before they finish.

#### Baseline captured on 2026-07-22

| Item | Observed value |
|---|---|
| Repository manifest | Swift tools 6.2, Swift 6 language mode, macOS 26 minimum |
| Host toolchain | Swift 6.4, Xcode 27.0 |
| Swift MCP SDK candidate | 0.12.1; its manifest declares Swift tools 6.1 |
| Claude Code | 2.1.216 |
| Codex | 0.144.6 |
| Cursor Agent | 2026.05.15-3f71873 |
| OpenCode | 1.18.4 |

The SDK candidate resolved and imported successfully in an isolated macOS 14 package using Swift tools 6.1 when compiled by the installed Swift 6.4 compiler. SwiftPM's tools version is a manifest compatibility floor; the host's installed Swift 6.4 compiler remains the version used to build the project. The app and UI-test targets now use Swift 6 language mode. Third-party packages continue to compile in their own declared language modes, so package updates are validated independently from the app's concurrency migration.

### MCP lifecycle and security implementation record

The lifecycle phase now has an app-owned baseline implementation:

- Swift MCP 0.12.1 and SwiftNIO are pinned in the package and Xcode project; the listener binds only to an ephemeral port on `127.0.0.1` at `/mcp`.
- `AgentControlService` owns start, stop, runtime-only credential registration, and shutdown cleanup. The app starts it before session restoration and stops it during application termination.
- Credentials are 256-bit random bearer tokens. Only SHA-256 hashes are kept in memory, credentials are never persisted, and pane or tab teardown revokes the associated token and MCP sessions.
- Requests require the exact loopback Host, an exact loopback Origin when an Origin header is supplied, a bearer token, a bounded body, an MCP session binding, and a per-credential concurrency limit. Responses are bounded and requests have a cancellation-aware timeout.
- Runtime spans cover listener start and stop, credential registration and revocation, timeout, stream failure, and response-limit failures. Tokens, request bodies, and terminal content are excluded from telemetry.
- Unit and protocol-boundary tests cover concurrency, revocation, host and Origin rejection, loopback binding, and unauthorized initialization.

The service now carries the configured scope with each credential and routes authenticated resource reads through the app-owned snapshot router. Mutation endpoints, diagnostics, subscriptions, and harness injection remain outside this phase.

Lifecycle cleanup and security hardening now complete the phase:

- Each live MCP session retains its source pane identity, allowing pane credential revocation to disconnect the associated server and transport instead of only removing token-store mappings.
- Server shutdown disconnects every live session before closing the listener, while pane revocation invalidates the credential immediately and performs idempotent session cleanup asynchronously.
- Authorization failures, session binding and closure, stream cancellation, timeout, stream failure, and response-limit outcomes emit bounded telemetry. Authentication material, request bodies, and terminal content remain excluded.
- Lifecycle tests cover authenticated MCP sessions, revocation cleanup, authorization telemetry redaction, loopback and origin validation, request limits, concurrency, and unauthorized initialization.
- Request timeout task groups cancel the in-flight MCP operation, and cancellation is distinguished from stream failure in telemetry. The transport remains local-only, bearer credentials remain runtime-only, and all output limits remain enforced.

### Read-only resources implementation record

The read-only resource phase now exposes stable, JSON-encoded snapshots through the app-owned MCP listener:

- Collection resources cover the workspace, profiles, harness catalogs, status-line configuration, and notifications.
- ID-based templates cover individual tabs, panes, profiles, and pane status data. Names remain display values and are never used as resource addresses.
- Pane scope sees its own pane, its parent tab, and global catalogs. Tab scope sees every pane in its tab and the same catalogs. Global scope sees all tabs, panes, profiles, harnesses, status lines, and notifications.
- Reads are resolved from live `@MainActor` `AppState` and `AppSettings` state; no parallel control-specific model or persistence path is introduced.
- Profile and pane environment values, bearer tokens, terminal contents, harness output, and other secret material are omitted or represented only by non-sensitive metadata.
- Resource subscriptions, writes, and harness configuration are intentionally not exposed yet.

Resource discovery, URI parsing, scope filtering, redaction, and an end-to-end MCP client read are covered by `AgentControlResourceTests`. Resource reads emit bounded `agent_control.resource.read` telemetry with source context and result metadata, without request payloads or credentials.

The read-only resource phase is complete:

- Collection resources and stable-ID templates are covered across pane, tab, and global callers, including workspace, profiles, harness catalogs, status lines, notifications, tabs, panes, profiles, and pane status data.
- Scope enforcement remains in the resource router. Pane callers see only their own pane, tab callers see every pane in their tab, and global callers see the full workspace. Stale and cross-scope IDs return structured MCP errors.
- Profile and runtime environment values, tokens, terminal content, and harness output are excluded from snapshots and resource-read telemetry.
- Resource tests cover discovery, MCP-client reads, scope boundaries, redaction, stale IDs, notification visibility, status visibility, and bounded resource-read telemetry. The test bundle compiles successfully with the repository's Swift 6 toolchain; local XCTest execution is currently blocked by the host test runner loading the arm64 bundle as x86_64.

### Harness injection implementation record

Harness preparation now runs in the app-owned launch path for pane creation, restore, restart, refresh, and continue flows. When injection is enabled, the app registers a fresh runtime-only credential, passes the bearer through `AGENT_SESSION_MANAGER_MCP_TOKEN`, and revokes the credential if adapter preparation fails. The token is never placed in command arguments, persisted session state, terminal output, or telemetry.

Claude Code receives an inline HTTP MCP configuration through `--mcp-config`, with the bearer header referring to the runtime environment variable. OpenCode extends its existing `OPENCODE_CONFIG_CONTENT` JSON with a remote MCP server, `oauth: false`, and the same environment reference. Codex receives ephemeral `-c` overrides for the URL, enabled state, and bearer environment variable; no Codex configuration file is written. Existing OpenCode safety settings and user-provided environment values remain in the launch environment.

Cursor receives a private plugin directory through `--plugin-dir`. The plugin's stdio MCP entry starts the bundled `AgentSessionManagerMCPBridge`, which reads the loopback endpoint and bearer token from its inherited environment and forwards raw MCP messages to the existing HTTP server. The plugin contains no credential or endpoint. Missing bridge or plugin preparation falls back to a normal Cursor launch after revoking the credential. Disabled injection revokes any prior credential and leaves the harness command and environment unchanged.

The shared preparation path emits bounded, pane-scoped `agent_control.harness.prepare` telemetry with harness, result, identity, and the bounded Cursor transport kind. Adapter serialization, bridge validation, and Cursor fallback are covered by `AgentControlHarnessInjectionTests`.

### Diagnostics and observability implementation record

The first diagnostics slice now exposes the four planned diagnostic resources:

- `agent-session-manager://diagnostics/summary`
- `agent-session-manager://diagnostics/traces`
- `agent-session-manager://diagnostics/invariants`
- `agent-session-manager://diagnostics/logs`

The corresponding bounded tools are `diagnostics_query_traces`, `diagnostics_query_invariants`, `diagnostics_query_logs`, and the Global-scope-only `debug_set_mode`. Trace and invariant readers use JSONL metadata for identity, preserve malformed-line and source-truncation metadata, keep legacy files separate, and apply the same pane/tab/global scope model as other resources. Diagnostic attributes and contexts are projected through a deny-by-default sensitive-field redactor; unified-log reads are restricted to the app's own process and subsystem and return structured fields only.

`debug_set_mode` persists through `SettingsPersistence` and reuses the existing `TracingService` and `InvariantReporter` configuration path. URI parsing, metadata identity, scope filtering, repeated invariant occurrences, redaction, and Global-only mutation behavior are covered by `AgentControlDiagnosticsTests`; MCP resource discovery now includes the diagnostic resources and tools.

Diagnostic reads are cooperative async operations. Trace and invariant scans validate UUID selectors; all diagnostic scans yield while scanning, observe task cancellation, and never return a partial result after cancellation. Query limits remain bounded to 200 records, HTTP request-body limits use the active server configuration, and query telemetry records source scope, result counts, truncation, cancellation, and persistence failures without credentials or diagnostic payloads. Existing durable files remain readable while Debug Mode is disabled, and the unified-log path remains restricted to this process and its subsystem.

#### Streamable HTTP result

The SDK's conformance server was started on `127.0.0.1:3001` at `/mcp`. The [official MCP Inspector](https://github.com/modelcontextprotocol/inspector) connected over Streamable HTTP and successfully completed:

- `initialize` and the initialized notification;
- `tools/list`;
- `resources/list`;
- `tools/call` for the harmless `add_numbers` fixture, returning `5`.

This validates the candidate transport and client path, including stateful session creation, resource discovery, tool discovery, and a tool result. The conformance fixture does not enforce the app's future per-pane bearer-token policy, so authentication, token revocation, scope authorization, bounded output, cancellation, and audit redaction remain gates for the lifecycle and security phase. The MCP transport still requires loopback binding, Origin validation, and authentication when used by the app; see the linked transport specification above.

#### Harness injection findings

The supported configuration surfaces were confirmed from the installed CLI help and official documentation without invoking commands that write user or repository configuration:

| Harness | Candidate app-owned injection | Feasibility status |
|---|---|---|
| Claude Code | Pass a temporary JSON configuration through `--mcp-config`; compare normal loading with `--strict-mcp-config`. | Supported surface confirmed; isolated end-to-end loading remains part of adapter implementation. |
| OpenCode | Add a remote MCP entry through app-owned configuration content with a URL and HTTP header. | Supported remote-server shape confirmed; merge and precedence behavior must be tested before implementation. |
| Codex | Use Streamable HTTP `url` plus `bearer_token_env_var`, supplied through documented config or launch-time overrides. | Supported surface confirmed; exact per-pane preparation must avoid `~/.codex/config.toml` and project config writes. |
| Cursor | Pass a private plugin through `--plugin-dir`; its stdio MCP entry launches the bundled bridge with inherited runtime connection details. | Supported and isolated without writing project or global MCP configuration. |

The adapter boundary is implemented: configuration preparation receives the pane identity, endpoint, runtime token, working directory, and existing configuration context, then returns launch arguments, environment additions, app-owned artifacts, cleanup ownership, or an actionable unsupported-configuration error. Tokens remain runtime-only.

#### Exit criteria for this phase

This phase is complete when the SDK and local protocol evidence above is kept in this roadmap, each harness has a recorded supported or blocked injection path, and no probe has modified the repository or global-user configuration. Phase 2 may proceed with transport-agnostic policy and persistence types. Phase 3 must not start the listener until the authentication, authorization, limits, cancellation, revocation, and telemetry gates are implemented. Harness adapter work remains ordered Claude Code, OpenCode, Codex, then Cursor.

## Testing and acceptance

- Unit-test policy resolution, ask defaults, persisted state, scope checks, token mapping, DTOs, ordering, option validation, cleanup choices, and redaction.
- Protocol-test initialize, resource/tool discovery, successful calls, invalid IDs, unauthorized scope, expired tokens, malformed requests, cancellation, and output limits.
- Protocol-test diagnostic summary, trace, invariant, and unified-log queries with pane/tab/global scope boundaries, time and event filters, redaction, truncation metadata, and Debug Mode disabled.
- Verify that only Global scope can enable or disable Debug Mode and that the operation persists and reconfigures existing diagnostic writers.
- Adapter-test all generated harness configuration while preserving existing configuration and avoiding repository pollution.
- Use a real MCP client against the isolated Dev app to create and mutate real tabs, panes, profiles, status-line settings, and notifications.
- Exercise the real New Pane flow for all four injection policies and verify the ask toggle defaults and overrides.
- Do not add fabricated state, test-only production branches, or fake screenshots. Run UI tests only with the approved Dev configuration.
- Add screenshot coverage for Settings and New Pane controls and inspect the generated artifacts before reporting visual verification.
- Load `instrument-runtime-telemetry` before implementing runtime behavior. Instrument server lifecycle, injection decisions, authentication, authorization, tool execution, failures, cancellation, and cleanup.

## Defaults and constraints

- Injection policy: `Ask (on by default)`.
- Scope: `Global`.
- Debugging reads are available at the caller's configured scope; unscoped global records and Debug Mode mutation require `Global` scope.
- The first debugging mutation is `debug_set_mode`; clearing, retention, path-management, and export operations are deferred.
- No extra Agent Session Manager confirmation for authorized MCP mutations.
- Tokens are runtime-only and never persisted or logged.
- Profile environment values are write-only or redacted in read resources.
- Policy changes affect future launches and restarts; existing harness processes must restart to receive changed MCP configuration.
- The app owns all setup work through Swift APIs; terminal panes receive only the final harness invocation.
