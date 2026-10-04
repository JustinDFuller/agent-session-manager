# Tracing

Agent Session Manager writes bounded OpenTelemetry JSONL spans while **Settings → Debug → Enable Debug Mode** is enabled.

## App Modes

Production writes under `~/Library/Application Support/agent-session-manager/`. Development builds write under `~/Library/Application Support/agent-session-manager.dev/`.

## File Layout

```text
traces/
  <sanitized-tab-name>-<tab-id8>/
    <sanitized-pane-name>-<pane-id8>.jsonl
  _global/
    global.jsonl
```

Each file begins with a metadata header:

```json
{
  "_type": "metadata",
  "paneId": "...", "paneName": "...", "tabId": "...", "tabName": "...", "createdAt": "...",
  "resource": {
    "service.name": "AgentSessionManager",
    "service.version": "...",
    "os.type": "darwin",
    "os.name": "macOS",
    "os.description": "...",
    "os.version": "...",
    "device.model.identifier": "...",
    "telemetry.sdk.name": "opentelemetry",
    "telemetry.sdk.language": "swift",
    "telemetry.sdk.version": "..."
  }
}
```

`resource` is the process-wide OTel `Resource` (`TracingService.configure`), written once per file and identical across every file from the same process. It comes from `ResourceExtension`'s `DefaultResources()` merged with an explicit `service.name`/`service.version` override; `device.id` may also appear.

The exporter routes every span with `pane.id` to a pane file. Spans without `pane.id` route to `_global/global.jsonl`. Tab and pane names are sanitized only for paths; diagnosis should read metadata rather than derive filenames.

## App Lifecycle Correlation

The app synchronously writes `app-lifecycle.json` in its application-support directory. Launch writes `running` with a launch UUID; an approved AppKit termination writes `clean` after Agent Control stops only when the on-disk marker still belongs to that launch. This ownership check prevents an older concurrent instance from marking a newer instance clean; an interprocess file lock keeps the read/check/write sequence atomic across instances. A later launch that finds `running` reports `previous_exit=unclean`, while a missing, unsupported, or unreadable marker reports `previous_exit=unknown`.

`app.launched` records the previous-exit classification and marker write result after tracing is configured. `app.termination.requested` records whether the clean marker was written. A force kill, signal crash, or power loss cannot emit a final span, so the next launch's marker classification is the durable evidence for an unclean process exit.

## Auto-forwarding to other signals

Every `TracingService.startSpan`/`record`/`withSpan` call also, unconditionally:

- writes a unified-log line via `AppLog` (see `documentation/features/debug-logging.md`) — always on, independent of Debug Mode
- emits an `os_signpost` interval (`OSSignposterIntegration`/`SignPostIntegration`) for Instruments' Points of Interest — also always on

Instrumenting a code path is a single `TracingService` call, not three. Do not add separate `print`/`NSLog`/log calls alongside a span for the same event.

Each file is trimmed at the fixed 10 MB cap. `TraceCleanupService` removes files older than one day on app launch and emits `trace.cleanup.ran`.

## Current Span Catalog

| Area | Spans |
|---|---|
| Pane lifecycle | `pane.activated`, `pane.focus_mode.changed`, `pane.notification.added`, `pane.notification.cleared`, `pane.activity.changed`, `pane.pr_merged.cleared`, `pane.pr_closed.cleared`, `tab.pane.added`, `tab.worktree.resolved` |
| Session restore | `session.pane.restore.continuation` |
| App lifecycle | `app.launched`, `app.termination.requested` |
| Profiles | `profile.save` |
| Agent control | `agent_control.injection_decision.resolved`, `agent_control.server.starting`, `agent_control.server.started`, `agent_control.server.start_failed`, `agent_control.server.stopped`, `agent_control.credential.registered`, `agent_control.credential.revoked`, `agent_control.scope.updated`, `agent_control.session.bound`, `agent_control.session.closed`, `agent_control.request.authorization_failed`, `agent_control.request.cancelled`, `agent_control.request.timed_out`, `agent_control.request.response_too_large`, `agent_control.request.stream_failed`, `agent_control.resource.read`, `agent_control.mutation`, `agent_control.harness.prepare`, `agent_control.diagnostic.query`, `agent_control.tool.authorization_denied`, `agent_control.debug_mode.changed` |
| Terminal | `terminal.process.started`, `terminal.process.exited`, `terminal.attention.delivered`, `terminal.clipboard.copied`, `terminal.clipboard.pasted`, `terminal.scrollback.changed` |
| Status line | `statusline.monitor.started`, `statusline.monitor.stopped`, `statusline.settings_file.written`, `statusline.attention.received`, `statusline.attention.suppressed`, `statusline.attention.recovered`, `statusline.attention.read_failed`, `statusline.payload.applied`, `statusline.payload.decode_failed`, `statusline.payload.stale_recovered`, `statusline.pr_transition`, `statusline.migration.gitworktree_dropped`, `statusline.migration.worktreebranch_merged`, `statusline.custom_field.exec_started`, `statusline.custom_field.exec_succeeded`, `statusline.custom_field.exec_failed`, `statusline.custom_field.exec_stale`, `statusline.custom_field.run_now`, `statusline.hook.event` |
| Invariants | `statusline.worktree.name_mismatch`, `statusline.lines.source_mismatch`, `statusline.claude.stop_background_state_missing`, `app.bundle_identity.preferred_url_mismatch`, `cursor.agent_control.bridge_missing`, `app.launch.auxiliary_window_opened`, `app.launch.auxiliary_windows_checked`, `invariant.log.write_failed`, `terminal.clipboard.copy_without_selection` |
| Notifications | `notification.auth.requested`, `notification.pane_attention.posted`, `notification.pane_attention.skipped`, `notification.pr_merged.posted`, `notification.pr_merged.skipped`, `notification.pr_closed.posted`, `notification.pr_closed.skipped`, `notification.response.navigation` |
| PR tracking | `pr.poll.cycle`, `pr.graphql.query`, `pr.response.parsed`, `pr.result.delivered`, `session.pr_check` |
| OpenCode | `opencode.port.allocated`, `opencode.port_allocation.failed`, `opencode.command.built`, `opencode.session.resumed`, `opencode.config_content.injected`, `opencode.config_content.user_override_silenced`, `statusline.opencode.server.bound`, `statusline.opencode.session.bound`, `statusline.opencode.session.expected_missing`, `statusline.opencode.session.waiting_for_create`, `statusline.opencode.session.unbindable`, `statusline.opencode.session.named`, `statusline.opencode.session.rename_failed`, `statusline.opencode.poll.success`, `statusline.opencode.poll.failed`, `statusline.opencode.sse.connecting`, `statusline.opencode.sse.connected`, `statusline.opencode.sse.disconnected`, `statusline.opencode.sse.exhausted`, `statusline.opencode.sse.session_idle`, `statusline.opencode.permission.fired`, `statusline.opencode.stop.fired`, `statusline.opencode.stop.received`, `statusline.opencode.session.bound.received`, `statusline.opencode.version.drift` |
| Other | `trace.cleanup.ran`, `window.snapshot` |

Each decoded Claude `Stop` is traced as `statusline.hook.event` with a `decision` of `suppressed_background_work` (with the comma-joined `background_task_types` sample of at most 16 entries and 64 UTF-8 bytes per entry, total `background_task_count`, and `session_cron_count` attributes), `ignored_not_working` for a lone/duplicate Stop, or `scheduled` for a completion candidate queued for the grace period. A scheduled decision does not prove delivery: a resumed prompt, later pending Stop, forwarded idle event, or teardown can cancel the callback. A dropped `idle_prompt` is traced as `statusline.attention.suppressed` with reason `background_work_pending`. Idle recovery without confirmed background work records `statusline.attention.recovered` with reason `idle_without_background_work`, alongside `pane.activity.changed` with state `stopped` and source `claude_idle_prompt`. These events include `pane.id`, `pane.name`, `tab.id`, and `tab.name`. Question and plan attention use `claude_question` and `claude_plan_approval` sources. The hook log records the Claude notification type under `notification_type`.

Not every existing span is pane scoped. Pane-scoped spans should carry `pane.id`, `pane.name`, `tab.id`, and `tab.name`; runtime changes must follow `instrument-runtime-telemetry`.

## Diagnosis

Use the metadata-aware read-only collector:

```bash
.agents/skills/agent-data-access/scripts/collect-telemetry.sh \
  --app prod \
  --tab "Agent Session Manager" \
  --pane "telemetry-skill"
```

The top-level historical `debug-trace.log` and `traces.jsonl` files are legacy formats. Inventory them separately; do not merge them with current per-pane JSONL output.

Claude hook records sample at most 32 tasks and 32 crons, with identifiers/types capped at 64 UTF-8 bytes, statuses at 32, ordinary scalar metadata at 64 or 128, and message/title/transcript path at 1,024. Full list counts and omitted-entry counts are retained; lifecycle classification uses full counts so logging truncation cannot generate completion. Descriptions, commands, and cron prompts are excluded. Both hook and attention readers consume bounded 64 KiB chunks. Attention uses locked append-only JSONL, per-file offsets, an incomplete-line buffer, and a stable fingerprint of original input. `statusline.attention.read_failed` records pane/tab context and an error code without file contents.
