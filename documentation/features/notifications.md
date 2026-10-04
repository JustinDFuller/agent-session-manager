# Notifications

Agent Session Manager surfaces terminal bell events (sent by Claude Code and similar tools when they need your attention) as in-app notifications with visual indicators, optional **macOS banner notifications** (Notification Center), and a sidebar panel.

**In-app vs macOS:** The sidebar and pane/tab dots are **purely in-app** and do not require notification permission. **macOS banners** use `UNUserNotificationCenter` and require permission in **System Settings → Notifications** for Agent Session Manager. If `requestAuthorization` fails (for example `UNErrorDomain` code **1**, often meaning notifications are not allowed for the app), fix that in System Settings or by resetting the app’s notification registration — **in-app alerts still work** when a bell or hook fires; only banners are affected.

**Bundle IDs (must match the app you run):** Notification permission is per bundle identifier. **Production** (`make app` / `make run`): `com.justinfuller.agent-session-manager` at `<git-common-root>/AgentSessionManager.app`. **Dev** (`make app-dev` / `make run-dev`): `com.justinfuller.agent-session-manager.dev` at `<git-common-root>/AgentSessionManagerDev.app`. Every worktree stages into those same two canonical paths. If Launch Services resolves either ID to an older generated bundle, run `make repair-launch-services`.

**Diagnosing notification failures:** Enable **Settings → Debug** and inspect the trace stream for notification spans. Compare to an **Xcode** build (development-signed) if a **SwiftPM `make app`** build still misbehaves after `make app` (ad-hoc codesign runs automatically).

**Alerts vs authorization:** Even with `authorizationStatus == authorized`, **System Settings** can disable **alerts/banners** for the app (`alertSetting`), in which case the debug log shows `[banner] skipped alertSetting=…` and no banner is scheduled.

## What It Does

- **Pane indicator** — A crisp accent-color waiting dot replaces the soft neutral working glow in the pane header when that pane has an unread notification.
- **Tab indicator** — A crisp accent-color waiting dot appears in the tab button when any pane in that tab has a pending notification.
- **Notification sidebar** — A sidebar panel opens automatically when notifications are queued. It lists the pane name, tab name, and a formatted timestamp. Timestamps show the time (HH:mm) for today's notifications, and the date (MM/dd/yyyy) for older notifications.

- **macOS banners** — When enabled in Settings, a system notification is shown for the same events (typically when the app is not the frontmost app). Clicking the notification brings the app to front, switches to the correct tab, and gives the terminal in that pane keyboard focus. For PR merged banners, the action alert is shown after navigating to the pane. You must allow notifications for Agent Session Manager in **System Settings → Notifications** the first time the app requests permission. **By default macOS banners auto-dismiss after a few seconds.** To keep them on screen until dismissed, open **System Settings → Notifications → Agent Session Manager** and set **Alert Style** to **Persistent**. This is a user-controlled macOS setting — there is no public API to force persistent banners programmatically.

Waiting dots use the app accent color. Sidebar entries are orange for priority panes and blue for regular panes.

**Persistence:** Pending in-app notifications (dots and sidebar rows) are saved in **`sessions.json`** with the rest of the session and restored on launch, so they survive quitting the app (for example alongside **Continue on restart**). They are cleared when you open that pane, dismiss a row, clear all, or remove the tab—as before. macOS banner notifications are not replayed on restore.

## Triggering a Notification

Every harness can signal attention through the shared terminal paths:

1. **ASCII bell** — a BEL character (`\a`). The reason is `Attention needed`. To test manually:

   ```sh
   printf '\a'
   ```

2. **OSC 777** — the sequence `ESC]777;notify;title;body` terminated with BEL (0x07). The reason uses the body, then title, then `Attention needed`; semicolons in the body are preserved. Many tools use this so the BEL byte acts as an OSC string terminator; SwiftTerm delivers that through `notify` rather than `bell()`. Both paths trigger the same in-app notification and optional macOS banner.

3. **Claude attention hooks** — Agent Session Manager always merges focused hooks into each Claude pane’s `--settings` file. `PreToolUse` catches `AskUserQuestion` and `ExitPlanMode`, `PermissionRequest` catches permission dialogs, `Notification` catches `permission_prompt`, `elicitation_dialog`, `idle_prompt`, and `agent_needs_input`, and `Elicitation` catches MCP-driven input. Each invokes the generated hook script to append a bounded record to a per-pane JSONL attention queue and raises the same attention path as a bell. The watcher consumes complete lines by offset, so a later idle notification cannot overwrite an earlier question or plan request during debounce; identical original payloads retain their deduplication fingerprint.

4. **Cursor `stop` hook** (optional, Settings → Notifications → Cursor → **Stop hook for attention**) — Agent Session Manager installs a user-level Cursor hook that writes stdin to a per-pane temp file keyed by `AGENT_SESSION_MANAGER_PANE_ID`. The Cursor provider watches that file and raises `Agent turn completed` when a turn stops. Existing Cursor panes do not currently refresh when this setting changes.

Attention events are surfaced even when the pane is the active (focused) pane, to keep testing and signals consistent.

**Suppressing false "Claude finished" notifications during background work:** Claude's `Stop` hook fires whenever the main agent's turn ends, including while Claude is only paused waiting on background work that will resume the session on its own. [Claude Code v2.1.145 introduced the background-work fields](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md#21145). When the task registry is reachable, Claude reports that work in two lists: `background_tasks` (running background agents, background shell commands, Monitors, and workflows) and `session_crons` (pending scheduled wakeups and recurring `/loop` schedules). Agent Session Manager appends every Claude hook invocation to a per-pane hook-event log (tailed for the `statusline.hook.event` trace spans described in [tracing.md]({{ '/documentation/features/tracing/' | relative_url }})) and reads those two lists from each `Stop`. If both lists are present and either list has any entry, the pane keeps reading as working and no "Claude finished responding" notification is sent, including for a repeating `/loop` schedule, which keeps the pane working and silent until the schedule is removed or expires. If both lists are empty, the pane becomes stopped and the notification fires after the usual grace period. When background work finishes, Claude resumes its turn, `UserPromptSubmit` returns the pane to working, and the final `Stop` with empty lists sends exactly one notification. `StopFailure` (an API error) carries no lists and is not checked: the pane stops and the notification fires as before. A `Stop` that lacks either list records the `claude.stop.background_state` warning and finishes the active turn even when the other list is nonempty. This can occur with older versions or an unavailable registry. Runtime evidence in this change was originally captured on v2.1.286, separately from the documented introduction version. Persistent shells such as dev servers count as pending work and can keep completion alerts silent indefinitely.

**Idle suppression and interrupted-turn recovery:** Claude's `idle_prompt` notification ("Claude is waiting for your input") arrives roughly 60 seconds after a turn ends, which includes turns that ended while background work is still pending. Agent Session Manager drops `idle_prompt` only when its latest `Stop` report confirms pending background work, tracing `statusline.attention.suppressed` with reason `background_work_pending`. Otherwise an idle event recovers a working pane to stopped, cancels delayed completion, records `statusline.attention.recovered`, and forwards the idle attention event without a second finished alert. This covers a foreground turn interrupted with Esc, which emits no `Stop`. Confirmation survives resumed prompts and is cleared by an empty/incomplete `Stop`, `StopFailure`, or monitor teardown; manually cancelling previously reported background work without another report can still leave idle alerts suppressed. Permission requests, `AskUserQuestion`, and `ExitPlanMode` always reach the attention path regardless of background work. Identical attention payloads are deduplicated within a turn; submitting another prompt resets that fingerprint.

**Why both `Stop` and the Notification path exist:** these two signals answer different questions and are not interchangeable.

| | `Stop` / `StopFailure` | `Notification` (`idle_prompt`, `agent_needs_input`, …) |
|---|---|---|
| Answers | "The turn is complete" | "Claude is waiting on you" |
| Timing | Immediate, deterministic — fires every turn | Delayed and conditional — an idle nudge that may never fire if you reply promptly |
| Effect | Drives the `working → stopped` lifecycle transition (`isClaudeWorking`/`isClaudeStopped`), which feeds the tab-loading spinner ([`TabButtonView.swift:25`](../../Sources/AgentSessionManager/Views/TabButtonView.swift)) and pane activity dot ([`PaneView.swift:167`](../../Sources/AgentSessionManager/Views/PaneView.swift)) | Requests attention; idle recovers working to stopped when no pending background work is confirmed |
| Surfaced as | `NotificationKind.claudeStop`, "Claude finished responding", gated by its own **Claude stop notification** toggle | An attention/"needs input" notification with dynamic reason text |

`idle_prompt` cannot replace `Stop`: it arrives late (or not at all). It provides recovery when a foreground turn ends without `Stop`, while `Stop` remains the prompt completion signal and supplies the background-work report. The background-work check above is the price of keeping `Stop` around — it's deterministic but noisy, firing whenever a turn ends with background work pending, so it reads the reported lists to avoid a false "finished".

**Note:** A raw BEL that appears only as the terminator of another OSC sequence does not ring the bell; that is normal terminal behavior.

## Notification Sidebar

The sidebar appears on the right side by default (configurable in Settings → Notifications). By default it is **always visible** — even when there are no pending notifications — so you have a consistent, predictable layout. Toggle **Always Show Notifications Bar** off in Settings → Notifications if you prefer the sidebar to appear only when there are queued notifications.

**Sidebar sections** (when priority notifications are enabled):
1. **Priority** — Notifications from panes marked as priority, at the top.
2. **Other** — Regular notifications below.

**Clearing notifications:**
- Click a notification row to navigate to that pane and clear its notification.
- Focusing a pane (clicking it or switching to its tab) automatically clears its notification.
- Use "Clear All" at the bottom of the sidebar to dismiss all at once.

Each pane has at most one unread row. A new regular attention event refreshes that row's reason and timestamp. A PR-merged row replaces a regular row for the same pane and suppresses lower-priority regular signals until cleared.

## Priority Panes

When creating a new pane, a **Priority Pane** toggle is shown (if priority notifications are enabled in settings). Marking a pane as priority means:

- Its sidebar notification marker is orange instead of blue.
- Its notification appears at the top of the sidebar in the "Priority" section.

Priority is a per-pane setting and persists across app restarts.

## Configuration

Settings → Notifications exposes these controls:

| Setting | Description | Default |
|---|---|---|
| Banner Notifications | Show macOS Notification Center banners for background pane bells (permission required). To keep banners on screen, set Alert Style → Persistent in System Settings → Notifications. | On |
| Stop hook for attention (Cursor) | Install a Cursor `stop` hook for turn-completion attention (see above) | On |
| Sidebar Position | Which side the notification sidebar opens on (Left / Right) | Right |
| Always Show Notifications Bar | Keep the sidebar visible even when there are no pending notifications | On |
| Priority Notifications | Enable the priority pane toggle and priority sidebar section | On |

These settings are persisted to `~/Library/Application Support/agent-session-manager/notification-settings.json` (alongside other app settings such as [debug-settings.json]({{ '/documentation/features/debug-logging/' | relative_url }}) under the same support directory).

## Notification icon

The **banner header icon** (small app icon in the corner of a macOS notification) comes from **Launch Services** and the app bundle’s registered icon—not from `UNNotificationAttachment`. Agent Session Manager ensures Launch Services can resolve the icon as follows:

1. **Full standalone `.icns`** — `make app` / `make app-dev` compile the asset catalog with `actool --standalone-icon-behavior all`, producing a multi-resolution `AppIcon.icns` or `AppIcon-Dev.icns` in `Contents/Resources` (not a minimal placeholder).
2. **Plist keys** — `CFBundleIconFile` and `CFBundleIconName` are synced from `actool`’s partial Info.plist after compile (dev uses `AppIcon-Dev` for both).
3. **Launch Services** — After codesign, the Makefile runs `make repair-launch-services`. It unregisters stale prod/dev URLs, registers canonical bundles that exist, and verifies `NSWorkspace.urlForApplication(withBundleIdentifier:)` resolves each registered identity correctly.
4. **Runtime registration** — On launch, `NSApp.applicationIconImage` is set from the bundle `.icns` so ad-hoc builds run from a worktree (outside `/Applications`) still expose a concrete bitmap to the system.

Notification payloads intentionally do not include a rich-content attachment. The header icon comes from the registered app bundle, and omitting a temporary attachment avoids Notification Center data-store move failures while scheduling.

- **Production** (`make run`): green icon via `AppIcon` / `AppIcon.icns`.
- **Dev** (`make run-dev`): yellow-tinted icon via `AppIcon-Dev` / `AppIcon-Dev.icns`.

There are no user-configurable settings for the notification icon. After changing icons, run `make clean && make run` (or `make run-dev`). If routing is stale, run `make repair-launch-services`. If the banner still shows a generic white icon, remove Agent Session Manager from **System Settings → Notifications**, rebuild, and allow notifications again. Ad-hoc-signed local builds may still show a generic icon on some macOS versions until the app is signed with a Developer ID and notarized.

## See also

- [debug-logging.md]({{ '/documentation/features/debug-logging/' | relative_url }}) — optional in-app debug log (process starts, git, session restore) separate from bell notifications; useful when diagnosing permission or PATH issues alongside panes.
- [panes.md]({{ '/documentation/features/panes/' | relative_url }}) — how panes run the shell and CLI; relates to bell events from background panes.
- [agent-harness-feature-matrix.md]({{ '/documentation/features/agent-harness-feature-matrix/' | relative_url }}) — cross-harness notification coverage and known lifecycle gaps.
