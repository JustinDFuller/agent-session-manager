## Purpose

The OpenSpec merge gate ensures every pull request has a durable, reviewable, and completed requirements record before its implementation can be merged into the default branch. It also defines how a formal stacked pull request coordinates one OpenSpec change across its base and higher implementation layers.

## ADDED Requirements

### Requirement: Every pull request has an OpenSpec change

The repository SHALL require every pull request to include an OpenSpec change in its cumulative diff, regardless of whether the pull request changes source code, documentation, automation, dependencies, or only repository metadata. The same requirement SHALL apply to every layer of a formal stacked pull request.

#### Scenario: Pull request has no OpenSpec artifacts

- **WHEN** a pull request's cumulative diff contains no OpenSpec change artifacts
- **THEN** the OpenSpec required check SHALL fail with an actionable missing-change finding

#### Scenario: Pull request contains an OpenSpec change

- **WHEN** a pull request's cumulative diff contains an OpenSpec change
- **THEN** the OpenSpec required check SHALL evaluate that change's structure, validation, tasks, and archive state

#### Scenario: Pull request only inherits an archived change

- **WHEN** the candidate checkout contains a valid archived OpenSpec change but the pull request's effective diff introduces no OpenSpec change directory
- **THEN** the OpenSpec required check SHALL fail with an actionable missing-change finding

#### Scenario: Draft pull request is incomplete

- **WHEN** a draft pull request is missing the required OpenSpec change or has an incomplete change
- **THEN** the OpenSpec check SHALL fail rather than downgrade the finding to a non-blocking notice

#### Scenario: Higher stacked layer sees an incomplete base change

- **WHEN** a higher layer of a formal stack contains implementation changes while the base PR's OpenSpec change is active, incomplete, or unarchived
- **THEN** the OpenSpec check SHALL fail with guidance to complete and archive the change in the base PR and cascade-rebase the stack, and SHALL NOT instruct the contributor to archive the change in the higher layer

#### Scenario: Higher stacked layer inherits the base change

- **WHEN** a higher layer's effective diff from the stack trunk includes the base PR's newly introduced OpenSpec change
- **THEN** the OpenSpec presence requirement SHALL be satisfied by that cumulative change, while the higher layer SHALL still use the same strict artifact and archive validation

### Requirement: OpenSpec artifacts are complete and valid

The OpenSpec check SHALL require the pull request's archived change to contain the repository's spec-driven planning artifacts, a corresponding main specification, and no invalid or unsupported specification shortcut. The complete artifact set SHALL pass strict OpenSpec validation.

#### Scenario: Required artifact is missing

- **WHEN** an archived change is missing its metadata, proposal, design, task checklist, delta specification, or corresponding main specification
- **THEN** the OpenSpec check SHALL fail and identify the missing artifact

#### Scenario: Artifact structure is invalid

- **WHEN** `openspec validate --all --strict` reports an error for the pull request contents
- **THEN** the OpenSpec check SHALL fail and report the validation findings

#### Scenario: Specification shortcut is used

- **WHEN** a pull request uses a skip-specification marker or equivalent shortcut instead of providing the required specification
- **THEN** the OpenSpec check SHALL fail

### Requirement: Tasks are complete and the change is archived

The OpenSpec check SHALL pass only when no active change remains in the pull request contents, every task in the relevant active and archived change set is checked, and archived-change validation succeeds. For a formal stack rooted at the default branch, the bottom PR SHALL own completion and archiving of the change; higher implementation PRs SHALL not independently archive it.

#### Scenario: Active change remains

- **WHEN** the pull request contents include an unarchived change directory
- **THEN** the OpenSpec check SHALL fail and direct the contributor to archive the change after review feedback is resolved

#### Scenario: Task checklist is incomplete

- **WHEN** any task in the relevant change set remains unchecked
- **THEN** the OpenSpec check SHALL fail and report the incomplete task count or task names

#### Scenario: Change is archived and complete

- **WHEN** the pull request contains a valid archived change, its main specification, and no incomplete tasks
- **THEN** the OpenSpec check SHALL pass the OpenSpec state requirements

#### Scenario: Base PR owns finalization for a stack

- **WHEN** a formal stack contains implementation layers above a base PR with an active OpenSpec change
- **THEN** contributors SHALL complete the task checklist and archive the change in the base PR, cascade-rebase the higher branches, and rerun the strict check before merging the stack

#### Scenario: Higher PR attempts to own finalization

- **WHEN** a higher implementation PR archives the change or creates a competing finalized change instead of updating the base PR
- **THEN** the OpenSpec check SHALL fail and identify the base PR as the required location for completion and archiving

### Requirement: The CI guidance documents stacked OpenSpec workflow

The OpenSpec check and repository OpenSpec documentation SHALL describe the distinct responsibilities of non-stacked, base-stack, and higher-stack pull requests.

#### Scenario: Base-stack failure explains finalization

- **WHEN** the strict check fails on the bottom PR of a stack because tasks are incomplete or the change is unarchived
- **THEN** the failure SHALL instruct the contributor to complete tasks and archive the change in that base PR

#### Scenario: Higher-stack failure explains rebasing

- **WHEN** the strict check fails on a higher implementation PR because the base PR has not been finalized
- **THEN** the failure SHALL state that the higher PR must not archive the change, identify the base branch or PR when available, and instruct the contributor to cascade-rebase after base-PR finalization

#### Scenario: Documentation matches CI guidance

- **WHEN** a contributor reads the OpenSpec repository guide while using a stacked pull request
- **THEN** the guide SHALL explain that strict failures in higher layers are expected until the base PR is completed and archived, and SHALL prescribe finalizing only the base PR before rebasing and merging

### Requirement: The OpenSpec check is a merge prerequisite

The default branch SHALL require the named OpenSpec check to pass before a pull request can merge. The check SHALL run for every pull request update, including draft transitions and subsequent commits, and SHALL validate the pull request's cumulative diff rather than only its latest commit.

#### Scenario: Required check is failing or absent

- **WHEN** the OpenSpec check fails, is skipped, or has not reported for the current pull request revision
- **THEN** GitHub SHALL prevent the pull request from merging through the default branch ruleset

#### Scenario: Required check passes

- **WHEN** the OpenSpec check passes for the current pull request revision and all other branch rules are satisfied
- **THEN** the pull request SHALL be eligible for merge subject to the repository's review requirements

#### Scenario: Higher layer remains blocked by strict base requirements

- **WHEN** a higher layer's own implementation is valid but a lower layer in the same main-rooted stack has not satisfied the strict OpenSpec requirement
- **THEN** GitHub SHALL continue to block the higher layer from merging until the lower layer is finalized and the stack is rebased

### Requirement: The agent cannot alter or bypass the enforcement

The OpenSpec enforcement logic SHALL be sourced from the protected default branch, and the agent account SHALL have no permission to bypass the required check or modify the enforcement surface without the existing human code-owner approval. Only `JustinDFuller` SHALL be authorized to approve enforcement-surface changes or bypass the OpenSpec merge requirement.

#### Scenario: Agent changes enforcement logic in a pull request

- **WHEN** `JustinDFuller-Agents` modifies the OpenSpec workflow, validation logic, ownership rules, or related enforcement configuration
- **THEN** the required check SHALL continue using the protected base-branch enforcement logic and the pull request SHALL require `JustinDFuller` code-owner approval

#### Scenario: Agent attempts to bypass the check

- **WHEN** `JustinDFuller-Agents` attempts to merge without a passing OpenSpec check or invokes a repository ruleset bypass
- **THEN** GitHub SHALL deny the merge or bypass because the agent lacks the authorized bypass permission

#### Scenario: Human owner bypasses the check

- **WHEN** `JustinDFuller` explicitly uses the configured repository ruleset bypass
- **THEN** GitHub MAY allow the bypass and SHALL record the actor as the human owner
