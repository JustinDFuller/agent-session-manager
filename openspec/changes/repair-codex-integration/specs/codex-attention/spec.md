# Spec Delta

## Purpose

Codex activity and attention tell users which pane is working, which has finished its foreground turn, and which needs a human response without requiring them to watch its terminal.

## ADDED Requirements

### Requirement: Codex lifecycle drives pane and tab activity

For supported Codex versions, an active foreground turn MUST produce the working indicator and a finished or interrupted turn MUST stop showing working. Pending attention MUST take precedence over working. Tab indicators MUST aggregate Codex pane states using the same priority as other harnesses. Terminal output alone MUST NOT establish working state.

#### Scenario: A real Codex task is running

- **WHEN** a Codex foreground turn starts in a running pane
- **THEN** its pane and tab show working unless higher-priority pending attention exists

#### Scenario: The user interrupts a task

- **WHEN** the user interrupts the active Codex turn
- **THEN** the pane leaves working and no successful-completion notification is produced

#### Scenario: The process exits

- **WHEN** a Codex process exits without pending attention
- **THEN** its pane shows idle rather than working

### Requirement: Foreground completion produces one completion alert

When Codex completion alerts are enabled, a successfully completed foreground turn MUST produce one notification through the existing attention system. A resumed turn, conversation change, or teardown during the completion grace period MUST cancel the pending alert. Delegated-agent completion MUST NOT be treated as foreground completion.

#### Scenario: A background pane finishes responding

- **WHEN** its foreground turn completes and no new turn begins during the grace period
- **THEN** the sidebar displays one notification with reason "Codex finished responding" and the existing banner policy applies

#### Scenario: Work resumes immediately

- **WHEN** another foreground turn starts during the completion grace period
- **THEN** the previous turn's pending completion notification is canceled and the pane shows working

#### Scenario: A delegated agent completes

- **WHEN** a delegated agent finishes while the foreground turn remains active
- **THEN** the foreground pane remains working and no foreground-completion alert is generated

### Requirement: Permissions and questions request attention

For supported Codex versions, a pending native permission request or native user question MUST produce a distinct actionable notification and waiting indicator. Unrelated tool calls MUST NOT create attention. Reasons MUST use fixed app copy rather than copying prompts, commands, or conversation content into notifications.

#### Scenario: Codex requests permission

- **WHEN** the current foreground turn requests user permission
- **THEN** its notification reason is "Codex needs your approval" and the pane shows waiting

#### Scenario: Codex asks a native user question

- **WHEN** Codex presents a supported native user-question request
- **THEN** its notification reason is "Codex is waiting for your answer" and the pane shows waiting

### Requirement: Attention is acknowledged through normal pane flows

Focusing a Codex pane, selecting its notification, or entering terminal input MUST acknowledge its notification through existing app behavior. Resolving the originating request or starting a new foreground turn MUST clear obsolete Codex attention. Duplicate delivery of one request MUST NOT create multiple sidebar rows or banners.

#### Scenario: The user selects an attention row

- **WHEN** the user selects a Codex notification
- **THEN** the app focuses that pane, clears the notification, and recomputes its indicator from the current lifecycle

#### Scenario: A request is resolved elsewhere

- **WHEN** Codex reports the pending request resolved or a subsequent foreground turn starts
- **THEN** the obsolete attention notification is cleared

### Requirement: Completion alerts have a persistent Codex setting

Settings MUST offer a "Codex completion notifications" toggle defaulting to on, with its value preserved across launches. Disabling it MUST suppress Codex completion alerts without suppressing permission or question attention, terminal bells, or PR notifications. Setting changes MUST apply to existing panes without restarting Codex.

#### Scenario: Completion notifications are disabled

- **WHEN** a user turns off Codex completion notifications and a running Codex pane later finishes
- **THEN** its lifecycle leaves working without generating a completion alert, and later permission requests still request attention
