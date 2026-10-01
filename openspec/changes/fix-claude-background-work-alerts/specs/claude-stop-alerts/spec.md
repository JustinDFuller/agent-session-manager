## Purpose

Claude panes alert the user when Claude is finished, and stay quiet while Claude is only paused waiting on background work that will resume the session on its own.

## ADDED Requirements

### Requirement: A Stop with pending background work is not finished

When a Claude pane receives a `Stop` event whose `background_tasks` list has any entry, or whose `session_crons` list has any entry, the pane MUST remain in the working state and the app MUST NOT send a "finished" alert. This applies to every background task type and to recurring and non-recurring session crons alike.

#### Scenario: Background agent still running

- **WHEN** a Claude pane receives a `Stop` event whose `background_tasks` contains a task of type `subagent`
- **THEN** the pane remains working and no finished alert is sent

#### Scenario: Background shell command still running

- **WHEN** a Claude pane receives a `Stop` event whose `background_tasks` contains a task of type `shell`
- **THEN** the pane remains working and no finished alert is sent

#### Scenario: Monitor still running

- **WHEN** a Claude pane receives a `Stop` event whose `background_tasks` contains a task of type `monitor`
- **THEN** the pane remains working and no finished alert is sent

#### Scenario: Wakeup scheduled

- **WHEN** a Claude pane receives a `Stop` event whose `session_crons` contains a scheduled wakeup
- **THEN** the pane remains working and no finished alert is sent

#### Scenario: Repeating loop

- **WHEN** a Claude pane receives a `Stop` event whose `session_crons` contains a recurring entry such as a `/loop 5m` schedule
- **THEN** the pane remains working and no finished alert is sent until the schedule is removed or expires and a later `Stop` reports both lists empty

### Requirement: A Stop with nothing pending is finished

When a Claude pane receives a `Stop` event whose `background_tasks` and `session_crons` lists are both present and empty, the pane MUST become stopped and the app MUST send the "finished" alert after the existing grace period.

#### Scenario: Plain prompt with no background work

- **WHEN** a Claude pane receives a `Stop` event with empty `background_tasks` and empty `session_crons`
- **THEN** the pane becomes stopped and the finished alert is sent after the existing grace period

#### Scenario: Background work completes and the session resumes

- **WHEN** a Claude pane receives a `Stop` with a running background agent, then a `UserPromptSubmit` as Claude resumes, then a `Stop` with both lists empty
- **THEN** exactly one finished alert is sent, after the final `Stop`

### Requirement: The idle notification is withheld while the pane is working

The app MUST NOT show an alert or banner for a Claude `Notification` event with `notification_type` `idle_prompt` while the pane is in the working state, including while it waits on background work. While the pane is stopped, the app MUST handle `idle_prompt` as it does without this capability. Other notification types, including permission prompts, questions, and plan approvals, MUST continue to alert regardless of pane state.

#### Scenario: Idle notification while waiting on background work

- **WHEN** a Claude pane is working after a `Stop` with a running background agent and Claude Code sends an `idle_prompt` notification
- **THEN** no alert or banner is produced

#### Scenario: Idle notification after the pane has stopped

- **WHEN** a Claude pane is stopped and Claude Code sends an `idle_prompt` notification
- **THEN** the alert is produced as it is today

#### Scenario: Permission prompt while working

- **WHEN** a Claude pane is working and Claude Code sends a permission prompt notification
- **THEN** the alert is produced

### Requirement: A Stop without a background-work report is surfaced

When a Claude `Stop` event lacks either the `background_tasks` list or the `session_crons` list, the app MUST record a warning invariant named `claude.stop.background_state` and MUST treat the turn as finished.

#### Scenario: Older Claude Code without the lists

- **WHEN** a Claude pane receives a `Stop` event that does not include `background_tasks` or `session_crons`
- **THEN** the `claude.stop.background_state` warning is recorded, the pane becomes stopped, and the finished alert is sent after the existing grace period

### Requirement: Decisions are traceable

For each Claude `Stop`, the trace MUST record whether the alert was suppressed for background work, including the background task types and the session cron count, or fired. Each `idle_prompt` dropped because the pane is working MUST be traced with the reason `pane_working`.

#### Scenario: Suppressed Stop

- **WHEN** a `Stop` is withheld because background work is pending
- **THEN** the trace records the decision `suppressed_background_work` with the pending task types and session cron count

#### Scenario: Dropped idle notification

- **WHEN** an `idle_prompt` is dropped because the pane is working
- **THEN** the trace records a `statusline.attention.suppressed` event with reason `pane_working`
