# Design

## Context

See proposal.md for motivation and the five capability deltas for the behavior contract. Exploration used the production app, its current pane traces and metadata, the October 12 screenshot, installed Codex 0.162.1, and a real read-only Luna response. These establish existing failures rather than acceptance evidence for a repair.

| Finding | Evidence | Implementation consequence |
| --- | --- | --- |
| Status frozen on an older conversation | Screenshot input/output counts 1740561/14102 exactly match the October 10 11:37 AM update; the later foreground conversation had different usage | Keep observing session changes after initial binding |
| Context arithmetic differs | At screenshot time the active conversation had 236085 current tokens and a 475000-token window: the existing app formula yields 49%, while the CLI yields 48% | Implement the CLI's versioned normalization and rounding |
| Model changes are missed | Real metadata uses top-level `turn_context`; the parser only accepts nested `event_msg` turn context | Recognize actual metadata shapes |
| Rich-data compatibility is not gated | The version predicate is called by tests, not production | Make an adapter selection control the runtime path |
| Codex activity and native attention are absent | The provider does not emit lifecycle changes or attention, despite launch-time binding hooks | Add explicit lifecycle and attention transport |
| Repository is empty for Codex | Repository discovery starts only in the Claude monitor path | Move discovery into shared monitor startup |
| GitHub auth differs between app and shell | Production records authentication failures; the shell's executable wrapper selects an agents configuration while the underlying Homebrew CLI is unauthenticated | Respect executable wrappers and configured shell authentication context |
| Continuation is absent | Codex refresh and restore build a fresh `codex` invocation | Persist and resume an exact foreground session ID |

## Goals / Non-Goals

**Goals:** Repair current Codex integration through the existing provider, monitor, pane, persistence, and GitHub runner architecture. Keep exact conversation identity, callback installation, and diagnostic ownership consistent across create, native conversation changes, refresh, and restore.

**Non-Goals:** Replace Codex with a headless harness, infer activity from PTY output, collect conversation content, add a goal-status chip or a background-task registry, install global hooks, change authentication identity, or alter approval and hook trust decisions. Public documentation updates follow the existing Diátaxis boundaries; these planning artifacts remain internal.

## Decisions

### 1. Use explicit version adapters

Replace the disconnected version predicate with adapter selection consumed by launch preparation and the provider. Detect the executable version through the same configured shell context used to launch it, before creating version-dependent hook arguments. Maintain one current adapter for the 0.162 release family, verified against installed 0.162.1, and retain the legacy 0.136 rich-metric adapter. Patch-family recognition must still validate required record shapes; another minor version is unrecognized until added deliberately.

The current adapter supports SessionStart, UserPromptSubmit, Stop, PermissionRequest, PostToolUse, and Interrupt. It omits StopFailure, which is absent from the upstream 0.162.1 contract. The legacy adapter retains its session-binding and rich-status capabilities using the documented 0.136 hooks; its schema has no Interrupt, so documentation must identify its limited lifecycle support rather than injecting that event. Unknown versions launch with baseline status and no guessed app lifecycle hook configuration. Agent Control remains independently prepared through its existing adapter.

This keeps known legacy metrics working while avoiding the current behavior of parsing every release as though its internals were compatible. Refer to the upstream [0.162.1 hook schema](https://github.com/openai/codex/blob/rust-v0.162.1/codex-rs/config/src/hook_config.rs), [0.136.0 hook schema](https://github.com/openai/codex/blob/rust-v0.136.0/codex-rs/hooks/src/schema.rs), and [current hook documentation](https://learn.chatgpt.com/docs/hooks).

### 2. Follow foreground session changes through a bounded hook queue

Retain the app-owned per-pane hook script, but replace the single overwritten binding record as the lifecycle transport with a locked append queue. Records contain only pane/tab IDs, a per-process launch generation, event name, session ID, turn/request IDs when supplied, timestamp, source, model, transcript path, and bounded result metadata. The script discards prompt, command, question, assistant message, tool input/output, and credential fields. Queue appends and reader compaction use the same locking discipline as existing Claude attention transport.

SessionStart and foreground UserPromptSubmit establish or update binding; the provider keeps consuming subsequent events instead of returning permanently after its first successful bind. A changed foreground session detaches the old tailer, cancels pending completion, clears conversation-derived model/tokens/context/quotas, and attaches only to the new exact transcript. Baseline facts continue updating. Repeated binding to the same session is idempotent. Events for another pane, launch generation, or a superseded turn are ignored with bounded reasons. SubagentStart/SubagentStop and unrelated sessions never choose the pane's foreground identity.

Use SQLite only as optional enrichment by exact session ID or exact known transcript path. Do not rank rows by cwd, recency, or launch-time proximity. Use the final CODEX_HOME exported by each pane's configured interactive shell for the interactive Codex process, optional SQLite enrichment, and exact-session continuation preflight. This value may be inherited from the app or pane when shell startup preserves it, or set or overridden by shell startup. All three consumers must use the same final value. If enrichment is unavailable, keep watching the exact reported transcript and retry its attachment. An unreadable current source clears the affected rich fields until valid data returns; a normally idle source does not expire simply because no tokens are being generated.

Alternatives considered: pinning forever repeats the observed freeze; choosing the newest cwd match can select another pane or delegated task; replacing the terminal with an app-server client would expand this repair substantially. The selected approach retains the real CLI TUI and treats transcript parsing as an explicit internal compatibility adapter.

### 3. Separate metadata updates, context occupancy, and usage buckets

Recognize top-level turn_context model metadata and retain supported legacy shapes. Use cumulative total_token_usage input/output fields for token facts and last_token_usage.total_tokens for current occupancy. Do not parse message bodies to derive status. Recognize native question requests by allowlisted function-call metadata (`request_user_input` and its matching call ID), reading only type, tool name, and IDs from response records; never read arguments or output content. A matching result or subsequent foreground turn clears question attention.

For supported 0.136 and 0.162 context calculations, use the upstream 12000-token baseline. If the window is at most the baseline, remaining is zero. Otherwise subtract the baseline from the window and from current occupancy, clamp occupancy at zero, compute and round remaining percentage to the nearest whole percent, clamp to 0...100, and derive used as 100 minus remaining. This reproduces the screenshot's 48/52 result and the upstream Rust calculation, including its nonnegative rounding behavior. Missing data stays missing. See the [upstream context calculation](https://github.com/openai/codex/blob/rust-v0.162.1/codex-rs/protocol/src/protocol.rs#L2474-L2493).

Key quota snapshots by limit_id. The existing five-hour/weekly chips select the standard `codex` bucket; an omitted ID is treated as the legacy standard bucket only in that adapter. Accept its matching 300-minute and 10080-minute windows and retain independent window fields across partial updates. A premium bucket with null windows cannot clear standard data. Reset bucket state when the foreground session changes. No new premium-quota chip is introduced.

### 4. Route Codex lifecycle and attention through existing pane callbacks

Add Codex working/stopped state, a session-bound callback, completion and attention callbacks, and request-resolution handling to the provider/monitor integration. Reuse pane installation methods so replacing a controller or monitor reinstalls callbacks. Pane and tab indicators include Codex state in their existing aggregation, priority, and Reduce Motion behavior.

UserPromptSubmit and supported foreground task-start metadata establish working. Stop schedules successful-completion attention after the existing 1.8-second grace period. A new turn, Interrupt, supported aborted/error outcome metadata, session rebind, process exit, or teardown cancels the candidate. Interruption stops working without claiming success. Only the current foreground turn may deliver completion; delegated-agent events are excluded. Automatic foreground continuation during the grace period cancels the prior candidate; this design does not infer long-lived goal or background-work completion from unavailable registry data.

PermissionRequest creates fixed-copy approval attention. Codex 0.162.1 does not provide a request identifier in this hook payload, so approval attention clears on the next foreground turn. Native request_user_input metadata creates fixed-copy question attention and its matching function-call output clears it. Completion copy is "Codex finished responding", approval copy is "Codex needs your approval", and question copy is "Codex is waiting for your answer". Retain existing focus/input acknowledgement, duplicate coalescing, priority, sidebar persistence, and banner permission rules.

Add a persistent Codex completion toggle defaulting to true alongside the existing Claude/OpenCode toggles. It is checked at delivery, so changing settings affects live panes immediately. Disabling it does not disable working/stopped state or permission/question attention. Extend persisted notification kind/source enums with Codex cases and keep existing decoding backward compatible.

### 5. Persist exact continuation and distinguish fresh starts

Add optional codexSessionID and codexTranscriptPath metadata to pane persistence. Save foreground identity updates immediately using the existing persistence flow. Never persist control credentials or queue offsets. Create a fresh hook generation and control registration for every process replacement while preserving the pane's settings and injection decision.

Construct continuation as `codex [global app/user options] resume <exact-session-id>` through the shared launch builder; do not append Claude's --continue and do not use --last. Normalize any previously stored app-owned resume target before inserting the exact current target, retaining unrelated user options. Refresh and Continue uses the current foreground identity. Enabled app restoration uses the saved identity; disabled restoration starts fresh. Refresh with New Settings retains its existing fresh-start semantics and the UI identifies that behavior for Codex.

Before terminating a pane for continuation, check the exact known session through the supported adapter. Unknown binding disables Refresh and Continue with "Codex has not reported a conversation to continue." A known missing or inaccessible saved session produces an app-level recovery state with Retry and Start New Conversation. Legacy panes without saved identity keep their earlier fresh-start restore behavior, with an app notice. No fallback selects a newer conversation. A failure after the harness itself starts remains a real harness failure, never fabricated continuation success.

### 6. Share Repository discovery and respect the GitHub command context

Move repository discovery into shared monitor startup before branching by harness; preserve the existing HTTPS/SSH parser. Merge cached repository identity into every provider snapshot independently of GitHub success. Preserve existing worktree/branch/diff ownership and custom-field context.

Prepare GitHub execution context from the configured interactive shell. An explicit inherited GH_PATH takes precedence; otherwise resolve the first executable `gh` in that shell's unmodified PATH before app fallback paths are merged. Executable wrappers are valid endpoints. Preserve explicitly inherited GitHub configuration/authentication variables; fill missing values from the configured shell's exported environment. Obtain that environment with a bounded app-owned process, keep credential values only in memory, and never trace its stdout or environment values. Keep direct Process execution of the resulting absolute executable and the existing GraphQL stdin writer, timeout, and error classification. Do not run login, change auth configuration, or guess the agents-account directory.

Introduce a shared per-pane PR polling state with loading, current, absent, and failed outcomes. On failure, preserve any prior PR with a stale indication; use a warning affordance and popover copy "GitHub authentication required" for authentication failures, with Retry and guidance to authenticate the configured gh. A successful query clears the error; a confirmed empty result clears prior PR state. Failed queries do not emit merge/close transitions. Retry refreshes command context so repaired shell configuration can recover without a pane restart. No new MCP mutation or signature is required.

### 7. Make diagnostics prove routing and failure outcomes

Extend the existing statusline.codex event family with binding changes, compatibility decisions, hook drains, lifecycle transitions, attention scheduling/cancellation/delivery, continuation outcomes, and source failures. Include pane.id, pane.name, tab.id, and tab.name everywhere a pane owns the event. Use bounded session/turn prefixes, field-presence flags, event names, adapter IDs, reason codes, and counts; exclude full records and environment values.

Report invariants for cross-pane/launch identity contamination, unsupported rich data being displayed, and mismatch between requested and bound continuation identities. Ordinary startup waiting, unknown-version degradation, and user authentication prerequisites are diagnostic outcomes rather than false invariant failures. Update the tracing and invariant catalogs and exercise both Debug Mode capture and always-on unified-log forwarding.

## Risks / Trade-offs

- Internal transcript and hook schemas can change → gate adapters by version and required shapes; baseline status remains usable and unknown versions are honestly limited.
- An atomic single-record overwrite loses short-lived lifecycle events → use the bounded locked queue and test bursts, partial writes, compaction, and teardown.
- Late old-session or old-process events could change the active pane → reject generation/turn mismatches and cancel old tailers and pending alerts before rebinding.
- Shell startup can be slow or noisy → bound context preparation, delimit structured output, validate the resolved executable, and surface recoverable app errors without leaking stdout.
- Continuation may encounter deleted conversations or unavailable storage → use exact identity, retain the pane configuration, and require an explicit fresh start for known failed continuation.
- Rate-limit, approval, and macOS banner prerequisites can be unavailable during acceptance → report blockers distinctly; do not substitute fabricated UI state or claim skipped cases passed.

## Migration Plan

Implement the Dev-only Launch Services prerequisite as its own task group before the Codex implementation pull request. Consolidate all six Codex task groups and their subtasks into one implementation pull request as an approved exception to the normal one-group-per-pull-request rule. Keep the macOS deployment floor at 26.0. Add optional persisted fields and the default-on toggle without rewriting existing pane settings or notifications. Migrate displayed refresh copy and rejected built-in approval guidance when the corresponding adapter is selected; preserve invalid saved values until explicitly corrected.

Capture Dev runtime evidence before finalizing the change, including foreground conversation changes, model changes, interruption, completion, permission/question attention, exact refresh/relaunch continuation, and real GitHub status recovery. Use distinct worktrees for multi-pane acceptance; concurrent panes sharing one checkout are unsupported by New Pane and remain out of scope. Continue implementation and QA with the shared change active; the later archive-only layer synchronizes main specs and archives after review. This planning PR neither changes runtime nor declares unchecked tasks complete.

Rollback is a source revert that leaves optional saved conversation metadata in place. Older builds ignore those optional pane fields and retain their prior fresh-start behavior; do not delete users' Codex conversations or credentials. Document that rollback restores the older limited integration rather than preserving the repaired behavior.

### 7. Isolate Dev Launch Services registration

The Dev build's app-dev repair path targets only the Dev bundle registration. Running or repairing the Dev build must leave the production Launch Services registration and production process unchanged. Preserve the existing explicit broad-repair entry point and its intentional broad scope. Keep the macOS deployment floor at 26.0. Verify the registration scope with shell-level checks and a real Dev build launch; do not treat a build alone as proof of Launch Services behavior.
