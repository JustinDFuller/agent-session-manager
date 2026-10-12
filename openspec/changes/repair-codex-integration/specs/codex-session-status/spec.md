# Spec Delta

## Purpose

Codex pane status describes the foreground conversation users are currently interacting with, including its model, token usage, context, and standard usage quotas.

## ADDED Requirements

### Requirement: Status follows the foreground conversation

The app MUST update a Codex pane's status when its foreground conversation changes without recreating the pane. Facts from the previous conversation MUST stop appearing once the change is recognized. Background or delegated conversations MUST NOT replace the foreground conversation's status.

#### Scenario: Start another conversation in the same pane

- **WHEN** the user starts a new Codex conversation in an existing pane
- **THEN** its status describes the new conversation and previous model, token, context, and quota facts are cleared until current facts arrive

#### Scenario: Resume through Codex's native picker

- **WHEN** the user selects a different saved conversation through Codex's resume flow
- **THEN** the pane's status follows that selected conversation

#### Scenario: A delegated task finishes

- **WHEN** a background agent emits status or completion data
- **THEN** the foreground conversation remains the pane's status source

### Requirement: Model and tokens stay current

For a supported Codex version, the app MUST show the current conversation's selected model and cumulative input and output token counts. A model change MUST update the model fact without restarting the pane. Token totals MUST NOT be presented as the amount currently occupying the context window.

#### Scenario: Change the selected model

- **WHEN** the user changes the model and Codex publishes current model metadata
- **THEN** the app's model fact updates to the selected model

#### Scenario: A conversation has accumulated many requests

- **WHEN** Codex reports cumulative usage and current context usage for that conversation
- **THEN** token facts show the cumulative totals and context facts use current context usage

### Requirement: Context percentages agree with Codex

For a supported Codex version with current context data, Context Used and Context Remaining MUST match that version's native context percentage calculation for the same update. The values MUST stay within zero through 100 and sum to 100. Missing context data MUST appear unavailable rather than as zero usage.

#### Scenario: Replay the October 12 active conversation update

- **WHEN** Codex 0.162.1 reports 236085 current context tokens and a 475000-token context window
- **THEN** Context Used shows 48% and Context Remaining shows 52%

#### Scenario: Context usage exceeds the usable window

- **WHEN** current context usage reaches or exceeds the supported usable context window
- **THEN** Context Used shows 100% and Context Remaining shows 0%

### Requirement: Quota facts retain their usage bucket

The five-hour and weekly quota facts MUST describe Codex's standard usage bucket and its matching window reset times. Updates for another usage bucket MUST NOT replace or erase those facts. Used percentages MUST NOT be interpreted as remaining percentages.

#### Scenario: Another quota bucket has no windows

- **WHEN** an update for a premium usage bucket arrives without primary or secondary windows after a valid standard quota update
- **THEN** the standard five-hour and weekly values remain available

#### Scenario: Standard usage changes

- **WHEN** the standard bucket reports 15% five-hour use and 65% weekly use with reset times
- **THEN** the app shows those used percentages and their matching reset times

### Requirement: Unsupported rich status is visibly unavailable

The app MUST populate rich Codex facts only through a supported compatibility contract. With an unsupported version or unavailable rich-data source, app-owned baseline facts MUST continue updating while unsupported facts appear unavailable. Previously bound conversation facts MUST NOT masquerade as current data.

#### Scenario: An unknown Codex version starts

- **WHEN** a Codex pane launches a version without a supported rich-status contract
- **THEN** worktree, repository, duration, changed lines, profile, version, and available PR facts still update while unsupported rich facts appear unavailable

#### Scenario: Rich data becomes unreadable

- **WHEN** the current conversation's rich-data source cannot be read or decoded
- **THEN** the app records a bounded diagnostic and marks affected facts unavailable until a valid current update recovers them
