# Spec Delta

## MODIFIED Requirements

### Requirement: Dev validation uses an isolated reproducible build

Native UI validation and screenshot commands MUST target the Dev app identity and the Dev persisted-state directory. Validation hooks MUST keep the invoking Git command configuration out of child fixture repositories. Generated Xcode builds MUST use the dependency versions resolved by the repository, and generation MUST fail when that resolved graph is unavailable.

#### Scenario: Fresh or regenerated Xcode project

- **WHEN** a developer generates an Xcode project, including over a stale generated dependency lock
- **THEN** its dependency versions match the repository lock and the Dev validation commands preserve that graph

#### Scenario: Missing dependency lock

- **WHEN** a developer generates the project without the repository dependency lock
- **THEN** generation reports a failure instead of silently selecting another dependency graph

#### Scenario: Pre-push native validation

- **WHEN** the installed pre-push hook evaluates pushed commits that include native changes
- **THEN** it runs the current launch and settings cases against Dev state

#### Scenario: Pre-push without native changes

- **WHEN** the installed pre-push hook evaluates pushed commits that contain no native changes
- **THEN** it does not start native launch validation

#### Scenario: Git fixtures run inside local validation hooks

- **WHEN** a developer selects the repository hooks through command-line or environment Git configuration
- **THEN** unit and Dev validation can commit in their disposable repositories without recursively invoking those hooks
