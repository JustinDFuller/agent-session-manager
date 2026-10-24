# Spec Delta

## Purpose

Codex continuation preserves the specific conversation a user was working on when they refresh a pane or restore saved panes after an app restart.

## ADDED Requirements

### Requirement: Refresh and Continue resumes the exact conversation

Refresh and Continue on a Codex pane MUST resume its current foreground conversation with the same checkout, profile, CLI options, and control-injection decision. The app MUST NOT select a conversation by latest activity or shared working directory. The sheet MUST describe continuation without promising an unsupported `--continue` flag.

#### Scenario: Two Codex panes use distinct checkouts

- **WHEN** the user refreshes one Codex pane while another Codex pane on a distinct checkout has newer conversation activity
- **THEN** the refreshed pane resumes its own conversation and retains its configuration while the other pane remains bound to its conversation

#### Scenario: A user changes conversations before refreshing

- **WHEN** the user switches Codex conversations and then selects Refresh and Continue
- **THEN** the newly selected foreground conversation is resumed

### Requirement: Codex state lookup uses the effective home

The app MUST resolve `CODEX_HOME` from the configured interactive shell's exported value first, then the launch environment value, then the default `~/.codex` directory. SQLite enrichment and exact-session preflight MUST use the same resolved home as the interactive Codex process.

#### Scenario: Shell startup changes Codex home

- **WHEN** the configured shell exports a `CODEX_HOME` different from the inherited launch value
- **THEN** SQLite enrichment and exact-session preflight use the shell-exported home

### Requirement: Enabled restoration resumes saved Codex conversations

With Continue on Restart enabled, the app MUST restore each Codex pane using its saved exact foreground conversation identity when that conversation is available. With the setting disabled, it MUST restore a fresh Codex conversation using the saved pane configuration. Saved worktree resolution MUST follow the existing restoration rules.

#### Scenario: Restore a conversation after relaunch

- **WHEN** a Codex pane with a saved available conversation is restored with Continue on Restart enabled
- **THEN** its previous conversation history is available in the restored pane

#### Scenario: Continuation is disabled

- **WHEN** the app restores a Codex pane with Continue on Restart disabled
- **THEN** it starts a fresh conversation while retaining its worktree and pane configuration

### Requirement: Missing continuation never resumes an unrelated conversation

When no exact resumable conversation is known, Refresh and Continue MUST be unavailable with an explanation. A saved pane whose conversation is missing or inaccessible MUST show an app-level recovery choice to start fresh or retry. Legacy saved panes without a conversation identity MUST retain their prior fresh-start restoration behavior with a notice.

#### Scenario: Refresh before a conversation is identified

- **WHEN** the refresh sheet opens before Codex has reported an exact conversation identity
- **THEN** Refresh and Continue is unavailable and the sheet explains that Codex has not reported a conversation to continue

#### Scenario: A saved conversation was deleted

- **WHEN** restoration cannot access the exact saved conversation
- **THEN** the app offers retry or an explicit fresh start and does not resume another conversation

#### Scenario: Restore a legacy pane

- **WHEN** an older saved Codex pane has no conversation identity
- **THEN** it opens a fresh conversation with its saved configuration and the app explains that no prior conversation was recorded

### Requirement: Continuation preserves compatible saved state

New saved Codex conversation metadata MUST be optional so existing saved tabs, panes, notifications, and settings still load. The app MUST save changes to the foreground conversation identity without requiring a tab change. A resumed process MUST install current status, activity, notification, and control callbacks.

#### Scenario: Change conversation without changing tabs

- **WHEN** a user changes a Codex pane's foreground conversation and later relaunches the app
- **THEN** restoration uses the updated saved identity

#### Scenario: A resumed task finishes

- **WHEN** a restored or refreshed Codex pane runs and completes another foreground turn
- **THEN** its status, activity indicator, and enabled completion notifications update normally
