# Status Line

Agent Session Manager shows a configurable status bar at the bottom of each terminal pane. The bar is composed of rows of facts; each fact displays one fact about the running session.

The catalog controls which chips can be selected for a harness. Each fact declares an owner (`app`, `harness`, or `merged`), supported harnesses, and whether missing data should render as pending or unsupported. Unsupported facts are omitted for that pane; supported facts with no current value render `—`. See [agent-harness-feature-matrix.md]({{ '/documentation/features/agent-harness-feature-matrix/' | relative_url }}) for the per-harness audit.

Facts show their SF Symbol and label by default. Explicit `labelOnly` and `symbolOnly` configurations are preserved; older saved configurations that omitted the style migrate to the symbol-and-label default.

## Item Catalog

| ID | Label | Availability | Source |
|----|-------|-------------|--------|
| `agentName` | Agent | Claude only | Claude hook JSON `agent.name` |
| `context` | Context Used | Claude, Codex | Claude hook JSON; Codex rollout token usage |
| `contextRemaining` | Context Remaining | Claude, Codex | Claude hook JSON; Codex 0.136.x rollout context percentage remainder |
| `cost` | Cost | Claude, OpenCode | Claude hook JSON; OpenCode provider |
| `duration` | Duration | All | App-computed from process start time |
| `effort` | Effort | Claude only | Claude hook JSON `effort.level` |
| `exceeds200k` | Exceeds 200k | Claude only | Claude hook JSON `exceeds_200k_tokens` |
| `inputTokens` | Input Tokens | Claude, Codex, OpenCode | Harness provider token usage |
| `linesAdded` | Lines Added | All | `git diff --shortstat HEAD` (polled every 15s) |
| `linesRemoved` | Lines Removed | All | `git diff --shortstat HEAD` (polled every 15s) |
| `model` | Model | All | Harness provider model data |
| `outputStyle` | Output Style | Claude only | Claude hook JSON `output_style.name` |
| `outputTokens` | Output Tokens | Claude, Codex, OpenCode | Harness provider token usage |
| `pr` | PR | All | GitHub CLI (`gh pr view`) via PRTrackingCoordinator |
| `profileName` | Profile | All | App state (selected profile) |
| `rate5h` | 5h Rate | Claude, Codex | Claude hook JSON; Codex 300-minute primary rate window |
| `rate5hReset` | 5h Resets At | Claude, Codex | Claude hook JSON; Codex 300-minute primary rate window |
| `rate7d` | 7d Rate | Claude, Codex | Claude hook JSON; Codex 10,080-minute secondary rate window |
| `rate7dReset` | 7d Resets At | Claude, Codex | Claude hook JSON; Codex 10,080-minute secondary rate window |
| `sessionName` | Session Name | Claude, OpenCode | Harness provider session metadata |
| `thinking` | Thinking | Claude only | Claude hook JSON `thinking.enabled` |
| `version` | Version | All | Claude hook JSON / Cursor and Codex CLI `--version` |
| `vimMode` | Vim Mode | Claude only | Claude hook JSON `vim.mode` |
| `worktree` | Worktree | All | App-computed from pane working directory; renders as `name • branch` |
| `repo` | Repository | All | App-computed Git remote identity |
| `contextSize` | Context Size | Claude only | Claude hook JSON context-window size |
| `cacheRead` | Cache Read | Claude only | Claude hook JSON cache usage |
| `cacheCreation` | Cache Write | Claude only | Claude hook JSON cache usage |
| `apiDuration` | API Duration | Claude only | Claude hook JSON API duration |

## Providers

`StatusLineMonitor` coordinates one provider path per pane and exposes merged `StatusLineData` to `StatusLineView`.

- Claude panes use the Claude `statusLine` hook payload and preserve the existing I1/I3 enforcement.
- Cursor panes combine app-owned baseline facts with Cursor hook model data.
- Codex panes combine app-owned baseline facts with a hook-bound Codex session. Codex lifecycle hooks write the actual `session_id`, `cwd`, model, and `transcript_path` for the pane. The provider starts baseline polling immediately and keeps watching the pane-scoped hook record path until the first valid pane/tab record arrives, even if that happens after the startup window. Once bound, it pins the session id/transcript path for the pane lifetime, tails only that transcript, and uses `~/.codex/state_5.sqlite` only as optional enrichment by exact session id or exact transcript/rollout path. It never selects by latest same-working-directory row.

Codex rollout parsing is intentionally bounded and content-avoiding. It accepts `session_meta.payload`, `turn_context`, and token-count `event_msg.payload.info` records, maps model/version/token/context/rate facts, and ignores message-content records. Startup catch-up reads only the latest 200 complete rollout lines and buffers partial JSONL writes until the newline arrives. Cost remains unsupported for Codex until Codex exposes a stable source.

## Invariants

The status line enforces runtime invariants that guarantee consistent values regardless of which CLI is in use.

### I1. Worktree name is the pane's working directory

The `worktree` fact always shows `URL(filePath: workingDirectory).lastPathComponent`. The app owns this fact; it does not rely on what a CLI reports. If the CLI sends a different name, the app logs a mismatch and uses its own value.

### I2. Each fact is shown once

The old `gitWorktree` item duplicated what `worktree` already shows. It has been removed. Saved configurations containing `gitWorktree` rows are silently migrated on first load.

### I3. Lines added/removed means vs HEAD

`linesAdded` and `linesRemoved` always reflect `git diff --shortstat HEAD`, polled every 15 seconds in the pane's working directory. This is consistent for all CLIs. For Claude panes, if the Claude hook JSON disagrees, the app logs a mismatch and uses the git-computed value.

### I4. Add Item picker is alphabetical

Items in the Add Item dropdown are sorted by label using `localizedStandardCompare`. The internal `itemOrder` array (which governs default row construction) is unchanged.

### I5. Worktree fact is a single item (name + branch)

The `worktree` fact renders as `name • branch` when both values are available, or just `name` when branch is absent. The old `worktreeBranch` item, which duplicated the branch half of this fact, has been removed. Saved configurations containing `worktreeBranch` rows are migrated on first load: if the row does not already have a `worktree` item, `worktreeBranch` is replaced by `worktree`; otherwise it is dropped.

### I8. Custom field failures preserve the last good value

Custom status line fields run shell commands on their configured cadence and receive the pane context as JSON on standard input. Each scheduled or **Run Now** execution records a start followed by either `statusline.custom_field.exec_succeeded`, `statusline.custom_field.exec_failed`, or `statusline.custom_field.exec_stale`. Runs of the same generation coalesce, and a result from a replaced or removed field is discarded. Failures retain the last successful value instead of replacing it with `—`.

Child-process standard input is nonblocking and configured to return a bounded `stdin_write` failure when the command closes its input. If the command leaves input open without consuming it, the same absolute command deadline returns `timeout`. A custom command can therefore finish or fail without blocking past its timeout or sending `SIGPIPE` to Agent Session Manager. Failure telemetry includes the dynamic trigger, duration, child exit status when available, and bounded input-failure stage and error code for write failures.

## Onboarding

On first launch the setup wizard presents a **Status Line** step (step 4 of 4) that pre-fills the default layout:

- Row 1: `pr`, `profileName`, `model`, `effort`
- Row 2: `context`, `contextRemaining`, `contextSize`, `exceeds200k`
- Row 3: `inputTokens`, `outputTokens`, `cacheRead`, `cacheCreation`
- Row 4: `worktree`, `cost`, `linesAdded`, `linesRemoved`

**Save** persists this config to `statusline-settings.json`. **Skip** writes an empty `rows` array, which renders no status bar. When the draft equals `wizardDefault()`, a **Clear** button empties all rows; once the layout diverges, the button becomes **Reset to Default** and restores the four-row spec.

The wizard default (`StatusLineConfig.wizardDefault()`) and catalog default (`StatusLineConfig()`) use this same four-row layout. The catalog default is used when no saved configuration exists and remains the fallback for code paths that skip the wizard (e.g. the welcome-step **Skip** button). Existing saved layouts and profile-specific overrides are preserved.

See [setup-wizard.md]({{ '/documentation/features/setup-wizard/' | relative_url }}) for the full wizard flow.

## Configuring Rows

1. Open **Settings → Status Line**
2. Use **+ Add Row** to add a new row
3. Click **Add Item** inside any row to see available items, alphabetically sorted. In a profile editor, the list is also filtered to that profile's harness.
4. Click the minus icon to remove an item
5. Use the up/down arrows to reorder rows

## Custom Fields

Custom fields run a shell command and add its plain-text or structured result to a status line. **SF Symbol** opens a searchable popover with curated, categorized suggestions. Each curated suggestion is clickable across its full row, including the space after its label. It searches labels, symbol names, and keywords, and accepts an exact SF Symbol name available on the current macOS version that is not in the curated suggestions. The configured name is preserved; an unavailable script override falls back to the configured icon, and an unavailable configured icon falls back to `terminal` while rendering. **Harnesses** opens a checklist popover that stays open while several harnesses are selected. It defaults to all user-facing harnesses, retains at least one selection, and dismisses with **Done**, or a click outside the popover. A field is filtered from both execution and rendering when its selected harnesses do not include the pane's harness.

**Run Now** runs only the saved field from the configuration being edited. It targets matching panes that use that saved configuration and selected harness. New fields and unsaved edits must be saved before Run Now is available. A profile override can therefore intentionally display a different result from the global field with the same ID.

Custom field commands run through the pane-equivalent interactive zsh shell in the pane's working directory. They inherit the sanitized pane environment and runtime environment values configured for the pane or profile, in addition to the curated `AGENT_SESSION_MANAGER_*` variables. Run Now starts the command immediately but does not bypass a cache or TTL implemented by that command.

## Invariant Violations

When an invariant is violated, the app reports it through `InvariantReporter`, records the preserved trace event (see [tracing.md]({{ '/documentation/features/tracing/' | relative_url }})), and uses the authoritative value. With Debug mode enabled, occurrences are also appended to `invariants/invariants.jsonl` and shown in the Invariant Dashboard.

| Invariant ID | Preserved trace event | When emitted |
|-------|-------------|---|
| `statusline.worktree.name` | `statusline.worktree.name_mismatch` | Claude JSON `worktree.name` or `workspace.git_worktree` disagrees with the app's computed worktree name (I1) |
| `statusline.lines.source` | `statusline.lines.source_mismatch` | Claude JSON `cost.total_lines_added`/`total_lines_removed` disagrees with cached `git diff --shortstat HEAD` (I3) |
| `claude.stop.background_state` | `statusline.claude.stop_background_state_missing` | A Claude `Stop` omits either background-work list; report a warning and finish the active turn even if the remaining list is nonempty |

Other status-line events remain trace events:

| Event | When emitted |
|-------|-------------|
| `statusline.migration.gitworktree_dropped` | A saved config row contained `gitWorktree`; it was removed (I2) |
| `statusline.migration.worktreebranch_merged` | A saved config row contained `worktreeBranch`; it was replaced by `worktree` (`substituted=true`) or dropped (`substituted=false`) (I5) |
| `statusline.provider.started` | A provider starts for a pane |
| `statusline.provider.stopped` | A provider stops for a pane |
| `statusline.provider.update_applied` | A provider snapshot is applied to the pane monitor |
| `statusline.provider.update_failed` | Reserved for provider snapshot failures |
| `statusline.custom_field.exec_started` | A scheduled or Run Now custom field execution starts; includes pane/tab identity, field id, and trigger |
| `statusline.custom_field.exec_succeeded` | A custom field updates its cached value; includes trigger, duration, and output kind |
| `statusline.custom_field.exec_failed` | A custom field fails while retaining its prior value; includes trigger, duration, reason, child exit status when available, and bounded input failure details |
| `statusline.custom_field.exec_stale` | A result for an outdated field generation was ignored; includes pane/tab identity, field id, and trigger |
| `statusline.custom_field.run_now` | A saved field was dispatched to matching panes; includes scope, target, started/coalesced counts, result, and profile id for profile scope |
| `statusline.watcher.lifecycle` | A Claude status payload, attention, or hook-log watcher starts, waits for its file, recovers, or stops |
| `statusline.attention.read_failed` | Claude attention queue open, nonblocking lock, read, or compaction failure; includes pane/tab context, bounded error code, and retry delay/attempt context. Pending state retries with backoff capped at one second while the watcher is active; success resets backoff and teardown cancels retries. |
| `statusline.cursor.<role>_watcher.<state>` | A Cursor hook, lifecycle, or attention watcher starts, fails to attach, recovers, or stops |
| `statusline.codex.hook_waiting` | Codex provider is still waiting for a hook record; includes retry attempt, late-binding state, and hook availability |
| `statusline.codex.hook_bound` | Codex hook record bound the pane to a session; includes hook availability, event name, session id prefix, retry attempt, late-binding state, and transcript availability |
| `statusline.codex.hook_record_ignored` | Codex hook record was present but rejected, usually because the pane/tab ids did not match |
| `statusline.codex.sqlite_enrichment` | Optional Codex SQLite enrichment result; includes exact-match outcome, retry attempt, selected session id prefix, and rollout path match |
| `statusline.codex.selection_failed` | Codex hook binding failed or was still waiting; retryable startup failures include retry reason/attempt |
| `statusline.codex.tailer_started` | Codex transcript/rollout tailer starts for the hook-bound session |
| `statusline.codex.tailer_attachment` | Codex rollout watcher waits for its file or recovers after replacement |
| `statusline.codex.tailer_stopped` | Codex rollout watcher stops |
| `statusline.codex.tailer_read` | Codex rollout tailer reads a bounded batch; includes line/update counts and whether the read was startup catch-up |
| `statusline.codex.parsed_update` | Codex rollout parsing produced a supported update; records model/token/context/rate-limit field presence |
| `statusline.codex.state_unavailable` | Reserved legacy event for Codex state DB failures |
| `statusline.codex.session_ambiguous` | Reserved legacy event for ambiguous Codex state rows |
| `statusline.codex.rollout_unavailable` | Reserved legacy event for missing Codex rollout paths |
| `statusline.codex.schema_unsupported` | The detected Codex version has no rollout adapter |
