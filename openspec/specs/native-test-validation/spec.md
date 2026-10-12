# native-test-validation Specification

## Purpose
Native validation provides reproducible Dev builds and honest evidence from the same pane and application flows that users exercise.

## Requirements

### Requirement: Dev validation uses an isolated reproducible build

Native UI validation and screenshot commands MUST target the Dev app identity and the Dev persisted-state directory. Validation hooks MUST keep the invoking Git command configuration out of child fixture repositories. Generated Xcode builds MUST use the dependency versions resolved by the repository, and generation MUST fail when that resolved graph is unavailable.

#### Scenario: Fresh or regenerated Xcode project

- **WHEN** a developer generates an Xcode project, including over a stale generated dependency lock
- **THEN** its dependency versions match the repository lock and the Dev validation commands preserve that graph

#### Scenario: Missing dependency lock

- **WHEN** a developer generates the project without the repository dependency lock
- **THEN** generation reports a failure instead of silently selecting another dependency graph

#### Scenario: Pre-push native validation

- **WHEN** the installed pre-push hook runs native launch validation
- **THEN** it runs the current launch and settings cases against Dev state

#### Scenario: Git fixtures run inside local validation hooks

- **WHEN** a developer selects the repository hooks through command-line or environment Git configuration
- **THEN** unit and Dev validation can commit in their disposable repositories without recursively invoking those hooks

### Requirement: Regression evidence comes from real runtime flows

The repaired pane loading/error, restart, Agent Control, and notification UI cases MUST create state through real user flows and run the same terminal and service initialization used by the app. Notification captures MUST wait for a real notification row. Tests MUST NOT replace those flows with injected pane or notification state or a terminal bypass.

#### Scenario: Restored pane

- **WHEN** a pane created through the app is restored after a Dev relaunch
- **THEN** its real terminal is initialized and launches after its view is ready

#### Scenario: Worktree checkout is delayed or fails

- **WHEN** real Git checkout work delays or fails during pane creation
- **THEN** the loading or failure overlay reflects that operation without injected state

#### Scenario: Terminal notification capture

- **WHEN** the walkthrough captures the notification sidebar after a shell emits attention
- **THEN** the emitted notification row exists before capture

#### Scenario: Agent Control with an empty test launch

- **WHEN** a Dev validation launch starts without restoring prior sessions
- **THEN** Agent Control remains available through its normal configuration and startup flow

### Requirement: External prerequisites are reported honestly

Validation requiring an authenticated harness or repository access MUST report an explicit skip when its prerequisite is unavailable. A skipped case MUST NOT be presented as executed runtime or screenshot evidence. A stored Cursor login that cannot fetch account details MUST NOT satisfy the real MCP test's authenticated-account prerequisite.

#### Scenario: Harness remains signed out

- **WHEN** a real service case requires authentication that is unavailable or intentionally absent
- **THEN** the test reports its unmet prerequisite and leaves the account unchanged

#### Scenario: Stored Cursor credentials cannot validate the account

- **WHEN** Cursor reports stored credentials but cannot fetch account details
- **THEN** the real MCP binding case reports an authentication prerequisite rather than claiming connection evidence
