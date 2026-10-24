# Tasks

## 0. Dev-only Launch Services prerequisite

- [x] 0.1 Scope the app-dev repair path to Dev registration while preserving the existing explicit broad-repair behavior and production registration/process; confirm the macOS 26 deployment floor with shell-level checks and a real Dev build launch.

## 1. Codex compatibility and hook transport

- [ ] 1.1 Make version-adapter selection control launch preparation and provider parsing; cover current 0.162, legacy 0.136 metrics, and unknown-version baseline behavior with tests that exercise production selection.
- [ ] 1.2 Prepare only supported hook events and remove StopFailure; cover current Interrupt support, limited legacy hooks, unknown-version launch, and setup failure through launch-argument and app-error tests.
- [ ] 1.3 Add the metadata-only locked Codex hook queue with pane/tab and launch-generation identity; test burst ordering, partial records, compaction, access retries, superseded generations, and bounded redaction.
- [ ] 1.4 Update approval guidance and reject unsupported saved built-in values without policy substitution; test Codex 0.162.1 untrusted rejection, retained saved values, and preserved custom options.
- [ ] 1.5 Update Codex compatibility documentation and its feature matrix, and add compatibility/queue diagnostic coverage; confirm the docs distinguish exercised current support from legacy limitations and diagnostics contain no payload or credential values.

## 2. Foreground conversation tracking and status metrics

- [ ] 2.1 Keep observing foreground session changes after initial binding, detach prior tailers, clear conversation facts, and publish a session-bound callback; test new/resume transitions, repeated binding, delayed files, and rejection of cross-pane hook records by pane/tab/generation identity. Multi-pane runtime acceptance uses distinct worktrees supported by New Pane.
- [ ] 2.2 Retain optional exact-identity SQLite enrichment and use the final CODEX_HOME exported by the configured interactive shell for both the Codex process and continuation preflight; test inherited values preserved by shell startup, shell-exported or overridden values, unavailable enrichment, wrong same-cwd rows, source failure, and recovery without recency-based session selection.
- [ ] 2.3 Parse actual top-level model metadata and separate cumulative token totals from current occupancy; cover real sanitized 0.162 record shapes, legacy shapes, model changes, absent fields, and unreadable current sources.
- [ ] 2.4 Match the upstream normalized and rounded context calculation; test the 236085/475000 snapshot gives 48/52, small windows, baseline occupancy, rounding boundaries, overflow occupancy, and missing data.
- [ ] 2.5 Retain quota snapshots by bucket and select the standard matching windows; test premium null updates, partial standard updates, reset times, used-versus-remaining semantics, and bucket clearing on rebind.
- [ ] 2.6 Update status-line and Codex feature documentation plus binding/source diagnostic coverage; demonstrate a real Dev new/resume transition and model change with current facts rather than an injected transcript or fabricated pane.

## 3. Codex activity and attention

- [ ] 3.1 Connect current Codex foreground lifecycle to pane/tab indicators and existing callback installation; test working, stopped, process exit, interruption, waiting priority, replacement monitors, and legacy capability limitations.
- [ ] 3.2 Deliver one foreground-completion alert after the 1.8-second grace period; test cancellation on new turns, rebind, interruption, failure, teardown, and delegated completion with explicit scheduled/canceled/delivered diagnostics.
- [ ] 3.3 Route permission hooks and allowlisted native question-call metadata into fixed-copy attention, then clear questions by matching call ID and clear unidentifiable permission requests on the next foreground turn; test request identity, unrelated tools, duplicate delivery, normal focus/input acknowledgement, and exclusion of prompt/command/argument content.
- [ ] 3.4 Add the default-on persistent Codex completion toggle and backward-compatible Codex notification kinds; test old settings/notification decoding, relaunch persistence, and live suppression of completion without suppressing other attention.
- [ ] 3.5 Update notifications, activity, Codex feature, and tracing/invariant documentation; capture real Dev working, completion, permission, question, and acknowledgement flows, including allowed macOS banners where the prerequisite is available.

## 4. Exact Codex continuation

- [ ] 4.1 Persist optional exact foreground Codex conversation metadata on binding changes; test legacy saved panes, same-tab conversation changes, and preservation of worktree/profile/options/notifications without persisting control credentials.
- [ ] 4.2 Build exact resume commands for Refresh and Continue and enabled restoration; test two conversations in one checkout through sequential native new/resume in one pane, updated foreground identity, user option preservation, disabled continuation, and fresh control/hook generations.
- [ ] 4.3 Add unknown-binding explanation and missing-session Retry/Start New Conversation recovery before process teardown; test unavailable continuation, preserved invalid identities, explicit fresh starts, and legacy fresh-start notices without latest-session fallback.
- [ ] 4.4 Correct Codex refresh copy and preserve Refresh with New Settings fresh-start behavior; add real Dev coverage that resumes conversation history and completes another turn with working status and notifications after refresh and relaunch.
- [ ] 4.5 Update continuation, Codex, and public recovery documentation with the reviewed copy; test requested-versus-bound identity diagnostics and confirm the docs match real refresh/restore captures.

## 5. Shared Repository and GitHub status

- [ ] 5.1 Start repository identity discovery for all harnesses and merge it independently of rich status/authentication; test HTTPS/SSH remotes, unavailable remotes, and Codex/Cursor/OpenCode/shared-shell snapshots while preserving other baseline facts.
- [ ] 5.2 Resolve the GitHub executable and missing authentication context through the configured interactive shell while honoring explicit overrides; test executable wrappers, PATH precedence, environment precedence, shell timeout/noise, bounded output, and secret redaction.
- [ ] 5.3 Add visible PR loading/current/absent/failed state, stale retained data, and authentication Retry guidance; test failure after success, recovery, confirmed no-PR results, and suppression of merge/close notifications from failed queries.
- [ ] 5.4 Preserve existing GraphQL stdin/timeout behavior and shared resolution notification callbacks; exercise real Dev PR status through the configured authenticated wrapper and report any unavailable GitHub prerequisites distinctly.
- [ ] 5.5 Update PR tracking, shared status, feature-matrix, public authentication-recovery, and diagnostic documentation; confirm the reviewed copy and screenshots distinguish authentication errors from successful no-PR results without changing accounts.

## 6. Runtime integration acceptance

- [ ] 6.1 Add a real Dev Codex integration flow combining native new/resume, model change, context/token comparison, background-pane activity across distinct worktrees, attention acknowledgement, and exact refresh/relaunch continuation; run through real sheets and the installed authenticated CLI using Luna where suitable, recording versions and screenshots/video without fabricated state.
- [ ] 6.2 Exercise cross-feature isolation with two Codex panes on distinct UI-supported worktrees and ordinary Claude/Cursor/OpenCode or shell panes; record that Codex session changes and shared status repairs preserve other panes' lifecycle, configuration, notifications, and Agent Control access. Concurrent panes sharing one checkout are unsupported by New Pane and are out of scope.
- [ ] 6.3 Exercise real authentication failure/retry and available banner prerequisites in Dev, and deliver an acceptance record linking each capability's scenarios to runtime captures and bounded diagnostics; separate source/unit evidence, executed runtime evidence, skips, and unresolved blockers before declaring acceptance complete.

The separate Dev-only Launch Services prerequisite owns group 0. One implementation pull request owns all six Codex groups 1 through 6 and their subtasks as an approved exception to the usual one-group-per-pull-request rule. All proposal tasks remain pending; implementation and QA completion belong to later layers. Review, OpenSpec validation, CI monitoring, and the later archive-only transition are workflow steps rather than completed implementation tasks.
