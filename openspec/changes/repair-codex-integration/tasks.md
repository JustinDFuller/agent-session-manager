# Tasks

## 1. Codex compatibility and hook transport

- [x] 1.1 Make version-adapter selection control launch preparation and provider parsing; cover current 0.162, legacy 0.136 metrics, and unknown-version baseline behavior with tests that exercise production selection.
- [x] 1.2 Prepare only supported hook events and remove StopFailure; cover current Interrupt support, limited legacy hooks, unknown-version launch, and setup failure through launch-argument and app-error tests.
- [x] 1.3 Add the metadata-only locked Codex hook queue with pane/tab and launch-generation identity; test burst ordering, partial records, compaction, access retries, superseded generations, and bounded redaction.
- [x] 1.4 Update approval guidance and reject unsupported saved built-in values without policy substitution; test Codex 0.162.1 untrusted rejection, retained saved values, and preserved custom options.
- [x] 1.5 Update Codex compatibility documentation and its feature matrix, and add compatibility/queue diagnostic coverage; confirm the docs distinguish exercised current support from legacy limitations and diagnostics contain no payload or credential values.

## 2. Foreground conversation tracking and status metrics

- [x] 2.1 Keep observing foreground session changes after initial binding, detach prior tailers, clear conversation facts, and publish a session-bound callback; test new/resume transitions, repeated binding, delayed files, and two panes sharing a checkout without cross-binding.
- [x] 2.2 Retain optional exact-identity SQLite enrichment and resolve the effective CODEX_HOME from configured-shell exports, launch environment, or the default home; test exported and explicit nondefault homes, unavailable enrichment, wrong same-cwd rows, source failure, and recovery without recency-based session selection.
- [x] 2.3 Parse actual top-level model metadata and separate cumulative token totals from current occupancy; cover real sanitized 0.162 record shapes, legacy shapes, model changes, absent fields, and unreadable current sources.
- [x] 2.4 Match the upstream normalized and rounded context calculation; test the 236085/475000 snapshot gives 48/52, small windows, baseline occupancy, rounding boundaries, overflow occupancy, and missing data.
- [x] 2.5 Retain quota snapshots by bucket and select the standard matching windows; test premium null updates, partial standard updates, reset times, used-versus-remaining semantics, and bucket clearing on rebind.
- [x] 2.6 Update status-line and Codex feature documentation plus binding/source diagnostic coverage; demonstrate a real Dev new/resume transition and model change with current facts rather than an injected transcript or fabricated pane.

## 3. Codex activity and attention

- [x] 3.1 Connect current Codex foreground lifecycle to pane/tab indicators and existing callback installation; test working, stopped, process exit, interruption, waiting priority, replacement monitors, and legacy capability limitations.
- [x] 3.2 Deliver one foreground-completion alert after the 1.8-second grace period; test cancellation on new turns, rebind, interruption, failure, teardown, and delegated completion with explicit scheduled/canceled/delivered diagnostics.
- [x] 3.3 Route permission hooks and allowlisted native question-call metadata into fixed-copy attention, then clear questions by matching call ID and clear unidentifiable permission requests on the next foreground turn; test request identity, unrelated tools, duplicate delivery, normal focus/input acknowledgement, and exclusion of prompt/command/argument content.
- [x] 3.4 Add the default-on persistent Codex completion toggle and backward-compatible Codex notification kinds; test old settings/notification decoding, relaunch persistence, and live suppression of completion without suppressing other attention.
- [ ] 3.5 Update notifications, activity, Codex feature, and tracing/invariant documentation; capture real Dev working, completion, permission, question, and acknowledgement flows, including allowed macOS banners where the prerequisite is available.

## 4. Exact Codex continuation

- [x] 4.1 Persist optional exact foreground Codex conversation metadata on binding changes; test legacy saved panes, same-tab conversation changes, and preservation of worktree/profile/options/notifications without persisting control credentials.
- [x] 4.2 Build exact resume commands for Refresh and Continue and enabled restoration; test two conversations in one checkout, updated foreground identity, user option preservation, disabled continuation, and fresh control/hook generations.
- [x] 4.3 Add unknown-binding explanation and missing-session Retry/Start New Conversation recovery before process teardown; test unavailable continuation, preserved invalid identities, explicit fresh starts, and legacy fresh-start notices without latest-session fallback.
- [ ] 4.4 Correct Codex refresh copy and preserve Refresh with New Settings fresh-start behavior; add real Dev coverage that resumes conversation history and completes another turn with working status and notifications after refresh and relaunch.
- [ ] 4.5 Update continuation, Codex, and public recovery documentation with the reviewed copy; test requested-versus-bound identity diagnostics and confirm the docs match real refresh/restore captures.

## 5. Shared Repository and GitHub status

- [x] 5.1 Start repository identity discovery for all harnesses and merge it independently of rich status/authentication; test HTTPS/SSH remotes, unavailable remotes, and Codex/Cursor/OpenCode/shared-shell snapshots while preserving other baseline facts.
- [x] 5.2 Resolve the GitHub executable and missing authentication context through the configured interactive shell while honoring explicit overrides; test executable wrappers, PATH precedence, environment precedence, shell timeout/noise, bounded output, and secret redaction.
- [x] 5.3 Add visible PR loading/current/absent/failed state, stale retained data, and authentication Retry guidance; test failure after success, recovery, confirmed no-PR results, and suppression of merge/close notifications from failed queries.
- [x] 5.4 Preserve existing GraphQL stdin/timeout behavior and shared resolution notification callbacks; exercise real Dev PR status through the configured authenticated wrapper and report any unavailable GitHub prerequisites distinctly.
- [ ] 5.5 Update PR tracking, shared status, feature-matrix, public authentication-recovery, and diagnostic documentation; confirm the reviewed copy and screenshots distinguish authentication errors from successful no-PR results without changing accounts.

## 6. Runtime integration acceptance

- [ ] 6.1 Add a real Dev Codex integration flow combining native new/resume, model change, context/token comparison, background-pane activity, attention acknowledgement, and exact refresh/relaunch continuation; run through real sheets and the installed authenticated CLI using Luna where suitable, recording versions and screenshots/video without fabricated state.
- [ ] 6.2 Exercise cross-feature isolation with two Codex panes on one checkout and ordinary Claude/Cursor/OpenCode or shell panes; record that Codex session changes and shared status repairs preserve other panes' lifecycle, configuration, notifications, and Agent Control access.
- [ ] 6.3 Exercise real authentication failure/retry and available banner prerequisites in Dev, and deliver an acceptance record linking each capability's scenarios to runtime captures and bounded diagnostics; separate source/unit evidence, executed runtime evidence, skips, and unresolved blockers before declaring acceptance complete.

Each implementation PR owns one complete top-level group and its subtasks. All tasks are pending in this proposal. Review, OpenSpec validation, CI monitoring, and the later archive-only transition are workflow steps rather than completed implementation tasks.
