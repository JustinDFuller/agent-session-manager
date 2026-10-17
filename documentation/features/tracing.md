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
| Session restore | `session.pane.restore.continuation`, `session.pane.codex_continuation.preflight`, `session.pane.codex_continuation.recovery`, `session.pane.codex_identity.saved`, `session.pane.codex_identity.mismatch` |
| App lifecycle | `app.launched`, `app.termination.requested` |
| Profiles | `profile.save` |
| Agent control | `agent_control.injection_decision.resolved`, `agent_control.server.starting`, `agent_control.server.started`, `agent_control.server.start_failed`, `agent_control.server.stopped`, `agent_control.credential.registered`, `agent_control.credential.revoked`, `agent_control.scope.updated`, `agent_control.session.bound`, `agent_control.session.closed`, `agent_control.request.authorization_failed`, `agent_control.request.cancelled`, `agent_control.request.timed_out`, `agent_control.request.response_too_large`, `agent_control.request.stream_failed`, `agent_control.resource.read`, `agent_control.mutation`, `agent_control.harness.prepare`, `agent_control.diagnostic.query`, `agent_control.tool.authorization_denied`, `agent_control.debug_mode.changed` |
| Terminal | `terminal.process.started`, `terminal.process.exited`, `terminal.attention.delivered`, `terminal.clipboard.copied`, `terminal.clipboard.pasted`, `terminal.scrollback.changed` |
| Status line | `statusline.monitor.started`, `statusline.monitor.stopped`, `statusline.settings_file.written`, `statusline.attention.received`, `statusline.attention.suppressed`, `statusline.attention.recovered`, `statusline.attention.read_failed`, `statusline.payload.applied`, `statusline.payload.decode_failed`, `statusline.payload.stale_recovered`, `statusline.provider.update_applied`, `statusline.repository.identity`, `statusline.pr_transition`, `statusline.migration.gitworktree_dropped`, `statusline.migration.worktreebranch_merged`, `statusline.custom_field.exec_started`, `statusline.custom_field.exec_succeeded`, `statusline.custom_field.exec_failed`, `statusline.custom_field.exec_stale`, `statusline.custom_field.run_now`, `statusline.hook.event` |
| Codex compatibility, sources, foreground binding, activity, attention, and continuation | `statusline.codex.compatibility.selected`, `statusline.codex.compatibility.rejected_option`, `statusline.codex.selection_failed`, `statusline.codex.hook_setup.failed`, `statusline.codex.hook_waiting`, `statusline.codex.hook.invoked`, `statusline.codex.hook_diagnostic.read_failed`, `statusline.codex.hook_queue.write_failed`, `statusline.codex.hook_queue.drained`, `statusline.codex.hook_queue.read_failed`, `statusline.codex.hook_queue.record_ignored`, `statusline.codex.hook_record_ignored`, `statusline.codex.binding.changed`, `statusline.codex.binding.unchanged`, `statusline.codex.binding.transcript_updated`, `statusline.codex.binding.facts_cleared`, `statusline.codex.binding.callback`, `statusline.codex.session.bound.received`, `statusline.codex.tailer_started`, `statusline.codex.tailer_stopped`, `statusline.codex.tailer_attachment`, `statusline.codex.tailer_read`, `statusline.codex.tailer_detached`, `statusline.codex.tailer_update_ignored`, `statusline.codex.parsed_update`, `statusline.codex.sqlite_enrichment`, `statusline.codex.activity.changed`, `statusline.codex.completion`, `statusline.codex.permission.attention`, `statusline.codex.permission.ignored`, `statusline.codex.question.attention`, `statusline.codex.continuation.preflight`, `statusline.codex.continuation.restore_deferred` |
| Layout resizing | `layout.resize.completed`, `layout.resize.canceled`, `layout.resize.reset`, `layout.resize.persistence_failed` |
| Invariants | `statusline.worktree.name_mismatch`, `statusline.lines.source_mismatch`, `session.pane.codex_identity.mismatch`, `statusline.claude.stop_background_state_missing`, `app.bundle_identity.preferred_url_mismatch`, `cursor.agent_control.bridge_missing`, `app.launch.auxiliary_window_opened`, `app.launch.auxiliary_windows_checked`, `invariant.log.write_failed`, `terminal.clipboard.copy_without_selection` |
| Auxiliary windows | `app.auxiliary_window.opened` records the explicitly requested dashboard identifier |
| Notifications | `notification.auth.requested`, `notification.pane_attention.posted`, `notification.pane_attention.skipped`, `notification.pr_merged.posted`, `notification.pr_merged.skipped`, `notification.pr_closed.posted`, `notification.pr_closed.skipped`, `notification.response.navigation` |
| PR tracking | `pr.poll.cycle`, `pr.shell.environment`, `pr.graphql.query`, `pr.response.parsed`, `pr.result.delivered`, `session.pr_check` |
| OpenCode | `opencode.port.allocated`, `opencode.port_allocation.failed`, `opencode.command.built`, `opencode.session.resumed`, `opencode.config_content.injected`, `opencode.config_content.user_override_silenced`, `statusline.opencode.server.bound`, `statusline.opencode.session.bound`, `statusline.opencode.session.expected_missing`, `statusline.opencode.session.waiting_for_create`, `statusline.opencode.session.unbindable`, `statusline.opencode.session.named`, `statusline.opencode.session.rename_failed`, `statusline.opencode.poll.success`, `statusline.opencode.poll.failed`, `statusline.opencode.sse.connecting`, `statusline.opencode.sse.connected`, `statusline.opencode.sse.disconnected`, `statusline.opencode.sse.exhausted`, `statusline.opencode.sse.session_idle`, `statusline.opencode.permission.fired`, `statusline.opencode.stop.fired`, `statusline.opencode.stop.received`, `statusline.opencode.session.bound.received`, `statusline.opencode.version.drift` |
| Other | `trace.cleanup.ran`, `window.snapshot` |

Each decoded Claude `Stop` is traced as `statusline.hook.event` with a `decision` of `suppressed_background_work` (with the comma-joined `background_task_types` sample of at most 16 entries and 64 UTF-8 bytes per entry, total `background_task_count`, and `session_cron_count` attributes), `ignored_not_working` for a lone/duplicate Stop, or `scheduled` for a completion candidate queued for the grace period. A scheduled decision does not prove delivery: a resumed prompt, later pending Stop, forwarded idle event, or teardown can cancel the callback. A dropped `idle_prompt` is traced as `statusline.attention.suppressed` with reason `background_work_pending`. Idle recovery without confirmed background work records `statusline.attention.recovered` with reason `idle_without_background_work`, alongside `pane.activity.changed` with state `stopped` and source `claude_idle_prompt`. These events include `pane.id`, `pane.name`, `tab.id`, and `tab.name`. Question and plan attention use `claude_question` and `claude_plan_approval` sources. The hook log records the Claude notification type under `notification_type`.

`statusline.provider.update_applied` records bounded presence flags for model, context, input/output tokens, rate limits, worktree, repository, and version, without recording any field values. Codex compatibility, source, queue, binding, activity, attention, and continuation spans include pane and owning-tab identity with bounded adapter, source, version, phase, or reason attributes. `statusline.codex.continuation.binding_seeded` records that a resumed pane initialized status lookup from its saved exact session identity before a new hook record arrived; it includes only a 12-character identity prefix and transcript-presence flag. `statusline.codex.continuation.binding_rejected` records a hook identity that differs from the requested session before that requested identity is confirmed; it contains only bounded 12-character prefixes and the allowlisted hook event name. `statusline.codex.hook.invoked` records the allowlisted event name when the generated hook script starts, including when a later queue write fails; `statusline.codex.hook_diagnostic.read_failed` records a bounded file-operation reason. These events exclude hook payloads, prompts, question text, tool arguments or output, environment values, and credentials. Binding diagnostics distinguish unchanged records, changed sessions, transcript updates, fact clearing, and callback publication. For continuation diagnosis, compare `requested_session_id_prefix` on `statusline.codex.continuation.preflight` with `session_id_prefix` on `statusline.codex.binding.changed` or `statusline.codex.session.bound.received`; the 12-character prefixes expose only enough metadata to check requested-versus-bound identity. The preflight event also records a bounded availability result and source (`restore` when applicable), but not the transcript path or full session ID. `statusline.codex.continuation.restore_deferred` records that a pane with an unavailable exact saved session is waiting for user recovery, without including the session identity. `statusline.codex.parsed_update` records field-presence booleans, while `statusline.codex.sqlite_enrichment` records exact-identity enrichment outcomes without database contents. `statusline.codex.activity.changed` records bounded pane and owning-tab identity plus an allowlisted lifecycle state and reason; states include `working`, `stopped`, completion scheduling, cancellation, suppression, delivery, attention request, and attention clear. `statusline.codex.permission.attention` and `statusline.codex.question.attention` record request or resolution decisions without raw request or call IDs; `statusline.codex.permission.ignored` records only the bounded mismatch reason. `statusline.codex.completion` records scheduled, canceled, and delivered foreground completion alerts; `completion_delivered` means the in-app notification row was added and does not establish that macOS displayed a banner. Delegated `SubagentStop` hooks are not registered. Completion matches session identity and, when available, turn identity; legacy records without a turn ID can only be correlated within the bound session. Codex 0.162.1 does not expose a separate Stop failure event in this hook contract, so failed hook transport cannot produce a completion alert and an undelivered Stop cannot be distinguished from a turn that did not complete. Exhausted queue-write retries are reported through redacted failure diagnostics, but do not guarantee event delivery. Unknown Codex versions selecting baseline-only integration and saved-option correction failures are expected outcomes, not invariant violations. In isolated Dev run `3b40c3e1-e951-4aa1-b36f-25ead2de2391`, bounded pane and global captures show `UserPromptSubmit` working, `Stop` completion, native question attention request and matching-call resolution, and completion-row delivery. Computer Use observed the native question flow; the retained question screenshots show a different foreground app and do not prove its visible Dev UI. A separate retained screenshot and matching telemetry prove a macOS completion banner for that pane. The run did not produce a native Codex permission request, so permission attention and acknowledgement remain open. A prior continuation capture showed conversation history after Refresh but no rich status or completion event because hooks were absent; the implementation now seeds status from the exact saved session, and post-change Refresh and relaunch runtime acceptance is pending. See the OpenSpec QA record for retained artifact paths and remaining acceptance gaps.

Not every existing span is pane scoped. Pane-scoped spans should carry `pane.id`, `pane.name`, `tab.id`, and `tab.name`; runtime changes must follow `instrument-runtime-telemetry`.

Layout-resize records use bounded `section`, `axis`, `source`, `before`, `after`, and `result` attributes. For `layout.resize.reset`, `source` is `pointer` for double-clicking a resize handle and `menu` for selecting its local reset item. Grid changes carry tab identity, status viewport changes carry pane and owning-tab identity, and keyboard grid changes also carry the selected `boundary.index`, `direction`, and `action` (`normal_step` or `larger_step`). Persistence failures use `layout.resize.persistence_failed`; they do not include file paths or terminal contents.

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

The Claude attention queue compacts consumed complete records in place under the appenders' exclusive lock after each successful drain. Only unread records and an unfinished suffix remain on disk. Open, lock, read, or compaction failures emit `statusline.attention.read_failed` with pane/tab context, a bounded error code, and bounded retry delay/attempt context. The reader uses nonblocking exclusive locking and retries failures with exponential backoff capped at one second while its watcher remains active, retaining pending offsets and buffers without another append. Successful drains reset backoff; teardown cancels pending retries.
