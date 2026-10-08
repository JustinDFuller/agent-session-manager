## Purpose

This capability gives coding agents a precise procedure for using GitHub's formal stacked pull request metadata through the `gh stack` CLI.

## ADDED Requirements

### Requirement: Agents create formal stacks in bottom-to-top order

The repository guidance SHALL distinguish creating a new stack from linking pull requests that already exist, and SHALL provide the corresponding `gh stack` commands in bottom-to-top order.

#### Scenario: An agent creates a new stack

- **WHEN** dependent branches do not yet have pull requests
- **THEN** the agent SHALL use the documented `gh stack init`/`gh stack add`/`gh stack submit` flow or an equivalent documented `gh stack` flow
- **AND** the resulting pull requests SHALL target the branch immediately below them

#### Scenario: An agent has already-created pull requests

- **WHEN** pull requests exist with the correct branch bases
- **THEN** the agent SHALL still run `gh stack link` with the pull requests or branches listed from bottom to top
- **AND** the agent SHALL NOT treat `gh pr create --base` or matching branch names as proof of formal stack membership

### Requirement: Agents verify formal stack metadata and branch bases

The repository guidance SHALL require both formal stack inspection and per-pull-request base verification after stack creation, linking, or remote import.

#### Scenario: An agent verifies a linked stack

- **WHEN** `gh stack link` or `gh stack submit` completes
- **THEN** the agent SHALL run `gh stack checkout` using the top pull request or another unambiguous stack identifier
- **AND** the agent SHALL run `gh stack view --json` and confirm the expected ordered pull requests are present
- **AND** the agent SHALL run `gh pr view` for each pull request and confirm its base is the immediately preceding layer

#### Scenario: Branch bases are correct but formal metadata is absent

- **WHEN** every pull request targets the expected lower branch but `gh stack view --json` does not show the formal stack
- **THEN** the agent SHALL report the stack as unverified
- **AND** the agent SHALL link or repair the formal stack before continuing

### Requirement: One implementation PR contains one complete top-level task group

The repository guidance SHALL state that a stack layer maps to one top-level OpenSpec task group and includes every subtask in that group.

#### Scenario: A task group has multiple subtasks

- **WHEN** task group `2` contains subtasks `2.1` through `2.5`
- **THEN** one implementation PR SHALL contain all of task group `2`
- **AND** the agent SHALL NOT create one stack PR per subtask

### Requirement: Command side effects are explicit

The repository guidance SHALL identify which `gh stack` commands inspect state, change local checkout or history, update remote branches or pull requests, and merge pull requests.

#### Scenario: An agent considers a remote-changing command

- **WHEN** an agent considers `gh stack link`, `submit`, `push`, `sync`, `rebase`, or `merge`
- **THEN** the guidance SHALL describe the command's side effects and any approval required before execution
- **AND** the guidance SHALL include conflict recovery where the command supports continuation or abort
