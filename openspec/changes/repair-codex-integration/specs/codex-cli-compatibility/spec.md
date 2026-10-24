# Spec Delta

## Purpose

Codex pane setup and lifecycle integration use options supported by the installed CLI while preserving the user's ability to configure custom options and security preferences.

## ADDED Requirements

### Requirement: Built-in approval guidance matches the installed CLI

Built-in Codex option guidance MUST advertise values accepted by its supported installed version. For Codex 0.162.1, approval guidance MUST offer `on-request` and `never` and MUST NOT recommend `untrusted`. User-entered custom options MUST remain configurable.

#### Scenario: Configure approvals for the current CLI

- **WHEN** a user configures approval policy for Codex 0.162.1
- **THEN** the built-in guidance describes `on-request` and `never` without suggesting `untrusted`

### Requirement: Invalid saved built-in values have app-level recovery

If a supported CLI version rejects a saved built-in option value, the app MUST identify the option and require correction before launching it. It MUST preserve the saved value until the user changes it and MUST NOT silently substitute a different approval or sandbox policy.

#### Scenario: Restore an obsolete approval value

- **WHEN** a saved pane specifies `untrusted` with Codex 0.162.1
- **THEN** the app explains the unsupported approval value and offers correction without launching or silently changing it

### Requirement: Lifecycle injection uses supported events

App-owned Codex hooks MUST use events supported by the selected compatibility contract. For Codex 0.162.1, native session, prompt, stop, permission, and interrupt integration MUST NOT rely on `StopFailure`. Preparing hooks MUST not print app setup commands or errors in the terminal or change the user's approval, sandbox, or hook trust policy.

#### Scenario: Launch the current CLI

- **WHEN** the app launches Codex 0.162.1
- **THEN** lifecycle integration uses supported event names, omits `StopFailure`, and displays setup failures through the app

#### Scenario: Launch an unrecognized CLI version

- **WHEN** the app cannot establish a supported lifecycle contract for the installed version
- **THEN** it launches the user's configured harness without guessing unsupported lifecycle events and reports limited integration through app diagnostics

### Requirement: Compatibility claims reflect exercised behavior

The app's compatibility selection MUST control runtime integration, not only tests or documentation. Feature documentation MUST distinguish full support, limited support, and unsupported facts. Real-service acceptance evidence MUST use the installed CLI and report its version and any unavailable prerequisites.

#### Scenario: Document current support

- **WHEN** support for the installed Codex release is documented
- **THEN** the claims match runtime compatibility selection and real acceptance evidence rather than a disconnected version predicate
