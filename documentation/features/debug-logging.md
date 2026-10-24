# Debug Mode

Debug Mode is the switch for durable diagnostic *files*. It does not gate unified logging or Instruments signposts, both of which are always on.

## Signals

- **Always-on (no Debug Mode needed):**
  - Unified logging via `os.Logger` (`AppLog`) — every `TracingService` span/record call forwards
    an entry here, regardless of whether Debug Mode is enabled. Visible in Console.app or
    `log stream`.
  - Instruments signposts (`OSSignposterIntegration`) — every span shows up
    as a `os_signpost` interval in Instruments' Points of Interest, whether or not the JSONL trace
    file exists.
- **Debug-Mode-gated (durable files):**
  - OpenTelemetry JSONL traces under `traces/`
  - Invariant JSONL violations under `invariants/invariants.jsonl`

See `documentation/features/tracing.md` for the trace file schema and `instrument-runtime-telemetry` for the instrumentation checklist (spans fan out to all three sinks from a single call).

## Console recipe

```bash
log stream --predicate 'subsystem == "com.justinfuller.agent-session-manager"' --level debug
```

Use `com.justinfuller.agent-session-manager.dev` for Dev builds. Categories mirror span-name prefixes (`terminal`, `pane`, `tab`, `pr`, `statusline`, `notification`, `session`, `invariant`, `app`); filter further with `category == "pane"` etc. Attribute values render as `<private>` unless the process streaming the log is the logging client itself (e.g. `log stream` run as the same user works; a redacted Console.app view from another session may not).

Production writes under `~/Library/Application Support/agent-session-manager/`. Development builds use the isolated `~/Library/Application Support/agent-session-manager.dev/` directory.

## Settings

Open **Settings → Debug** and enable **Enable Debug Mode**. The setting persists in:

```text
~/Library/Application Support/agent-session-manager/debug-settings.json
```

The schema is:

```json
{"schemaVersion":1,"enabled":true}
```

Older `debug-settings.json` schemas and the removed `tracing-settings.json` file are ignored instead of migrated, so upgrades start with Debug mode disabled.

## Output

Debug mode enables both:

- OpenTelemetry JSONL traces under `traces/`
- invariant JSONL violations under `invariants/invariants.jsonl`

Both outputs use fixed 10 MB caps. Trace files retain their existing one-day cleanup behavior. Invariant logs are size-bounded only so violations remain available during dogfooding.

## Agent control diagnostics

The app-owned MCP server exposes scoped diagnostic resources and bounded query tools for the summary, per-pane traces, invariant occurrences, and app-owned unified logs. Pane and tab callers receive only records attributable to their scope; unified-log queries and Debug Mode changes require Global scope.

Diagnostic output is metadata-first and redacted before it crosses the MCP boundary. Terminal content, harness output, secrets, environment values, and arbitrary system logs are not returned. Queries use bounded limits and cooperative cancellation. When Debug Mode is disabled, existing durable trace and invariant files remain readable while new durable capture is disabled; unified logs remain available because they are always on.

Top-level `debug-trace.log` and `traces.jsonl` files are stale legacy formats when present. Report them separately from current per-pane traces.

Use **Open Trace Dashboard** or **Open Invariant Dashboard** from the Debug settings page. The same windows are available from the Window menu with `⌘⇧D` and `⌘⇧I`.
