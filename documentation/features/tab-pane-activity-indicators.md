# Tab & Pane Activity Indicators

Every tab and pane shows a small indicator that answers one question: **where should I focus attention right now?**

## Three states (priority order)

| State | Visual | Meaning |
|-------|--------|---------|
| **Waiting** | Crisp filled accent-color dot, breathing pulse | Agent needs your input — a notification is pending |
| **Working** | Soft secondary-color circular glow, subtle pulse | A supported agent lifecycle signal says work is active |
| **Idle** | Static dim hollow ring | Process stopped or running quietly with no output |

A tab aggregates its panes: it shows `waiting` if any pane is waiting, `working` if any pane is working, and `idle` otherwise. Every tab always shows an indicator so an idle tab is positively identifiable, not just "absent dot."

## Working detection

A pane is `working` when:
- `processState == .running`, **and**
- Claude Code's `UserPromptSubmit` lifecycle hook has fired without a subsequent `Stop` or `StopFailure`, **or** the latest `Stop` reported pending background work (both lists present with a non-empty `background_tasks` or `session_crons` list, including a repeating `/loop` schedule), **or**
- OpenCode's database-derived session status state is `busy` or `retry`

A pane waiting on confirmed background work keeps the working indicator and sends no finished notification, including for persistent shells such as dev servers. An empty or incomplete `Stop` report finishes the active turn; `StopFailure` also clears the pending-work confirmation. If there is no confirmed pending work, `idle_prompt` recovers an interrupted foreground turn to stopped and forwards the idle attention event without a finished alert. Confirmation survives resumed prompts until another report or monitor teardown clears it, so manually cancelling previously reported background work without a later report can still leave the indicator working. See [notifications.md]({{ '/documentation/features/notifications/' | relative_url }}).

Codex and shell panes remain idle unless an explicit attention notification exists. Cursor uses its `beforeSubmitPrompt` and `stop` hooks for explicit working-state detection. PTY reads are intentionally not used for progress detection because terminal output includes echoed keystrokes and other noise that does not mean an agent is working.

## Waiting and notifications

A pane is `waiting` whenever `AppState.notifications` contains an entry for that pane — regardless of notification kind (`terminalBell` or `prMerged`). Focusing the pane clears its notification (`AppState.setActivePane` → `clearNotification`), reverting the indicator to `working` or `idle`. The active pane therefore never shows `waiting`.

This means the activity indicator and the notification are the same signal. There is no separate notification dot in the pane header.

## PR status is separate

PR status (CI checks, merge state) appears only in the status-line `pr` fact and its popover. The activity indicator has no knowledge of PR state. This prevents the indicator from turning red/purple on CI failure or merge — those are informational, not attention-requiring.

## Reduce Motion

When Accessibility → Reduce Motion is enabled:
- **Working**: shows a static soft secondary-color circular glow (no pulse)
- **Waiting**: shows a static crisp accent-color dot (no pulse)
- **Idle**: unchanged (already static)

All three states remain visually distinguishable without animation.

## Accessibility identifiers

Format: `{prefix}-activity-{state}-{name}`

Examples:
- `pane-activity-idle-feature-a`
- `pane-activity-working-feature-a`
- `pane-activity-waiting-feature-a`
- `tab-activity-idle-WorkTab`
- `tab-activity-waiting-WorkTab`

## Enable / disable

Settings → Panes → **Show Activity Indicators** toggle (`settings-activity-indicators-toggle`).

When off, `ActivityIndicatorView` renders nothing. The setting is persisted to `activity-indicator-settings.json`.

## Tracing events

| Event | When |
|-------|------|
| `pane.activity.changed` | Claude lifecycle state changes, with `state`, `source`, and `hook_event` attributes |
| `pane.notification.cleared` | `clearNotification(paneID:)` called with `reason: "cleared"` |

The `pane.notification.added` event was already traced; `cleared` was added to make enter/exit symmetric and debuggable.
